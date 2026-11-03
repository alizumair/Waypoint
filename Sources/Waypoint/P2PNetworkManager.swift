import Foundation
import Network
import CryptoKit
import Combine

/// P2PNetworkManager manages Bonjour advertising, peer browsing, and raw TCP socket
/// communication using Apple's Network.framework.
@MainActor
public final class P2PNetworkManager: ObservableObject {
    public static let shared = P2PNetworkManager()
    
    // Bonjour Service Type
    public static let serviceType = "_waypoint._tcp"
    public static let defaultPort: UInt16 = 53890
    
    // Published UI State
    @Published public private(set) var isListening: Bool = false
    @Published public private(set) var isBrowsing: Bool = false
    @Published public private(set) var discoveredPeers: [PeerDevice] = []
    @Published public private(set) var activeTransfers: [FileTransferProgress] = []
    @Published public private(set) var receivedFolderURL: URL
    
    // Callbacks for Ecosystem Bridges
    public var onClipboardReceived: ((ClipboardSyncPayload) -> Void)?
    public var onNotificationReceived: ((NotificationRelayPayload) -> Void)?
    public var onMediaMetadataReceived: ((MediaMetadataPayload) -> Void)?
    public var onMediaCommandReceived: ((MediaCommandPayload) -> Void)?
    public var onVideoFrameReceived: ((VideoNALUPayload) -> Void)?
    
    // Network.framework primitives
    private var listener: NWListener?
    private var browser: NWBrowser?
    private let networkQueue = DispatchQueue(label: "com.waypoint.network", qos: .userInitiated)
    
    // Active connections mapped by device ID or remote endpoint
    private var activeConnections: [String: NWConnection] = [:]
    private var incomingFileHandles: [String: (handle: FileHandle, manifest: FileManifestPayload, receivedBytes: Int64, tempURL: URL, destURL: URL)] = [:]
    
    public let localDeviceId = UUID().uuidString
    public let localDeviceName = Host.current().localizedName ?? "My Mac"
    
    public init() {
        // Resolve ~/Downloads/Waypoint Received
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let waypointFolder = downloads.appendingPathComponent("Waypoint Received", isDirectory: true)
        self.receivedFolderURL = waypointFolder
        
        try? FileManager.default.createDirectory(at: waypointFolder, withIntermediateDirectories: true)
        
        startListener()
        startBrowsing()
    }
    
    // MARK: - Listener (Bonjour Advertising)
    
    public func startListener(port: UInt16 = defaultPort) {
        do {
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableKeepalive = true
            tcpOptions.keepaliveIdle = 5
            
            let params = NWParameters(tls: nil, tcp: tcpOptions)
            params.includePeerToPeer = true
            
            let nwPort = NWEndpoint.Port(rawValue: port) ?? .any
            let listener = try NWListener(using: params, on: nwPort)
            
            // Advertise via Bonjour
            listener.service = NWListener.Service(
                name: localDeviceName,
                type: P2PNetworkManager.serviceType,
                domain: "local.",
                txtRecord: createTXTRecord()
            )
            
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    switch state {
                    case .ready:
                        self.isListening = true
                    case .failed(let error):
                        print("[Waypoint Listener] Failed: \(error.localizedDescription)")
                        self.isListening = false
                    case .cancelled:
                        self.isListening = false
                    default:
                        break
                    }
                }
            }
            
            listener.newConnectionHandler = { [weak self] newConnection in
                Task { @MainActor [weak self] in
                    self?.handleIncomingConnection(newConnection)
                }
            }
            
            listener.start(queue: networkQueue)
            self.listener = listener
        } catch {
            print("[Waypoint Listener] Could not start: \(error.localizedDescription)")
        }
    }
    
    private func createTXTRecord() -> NWTXTRecord {
        var txt = NWTXTRecord()
        txt["id"] = localDeviceId
        txt["name"] = localDeviceName
        txt["model"] = "Mac"
        txt["platform"] = DevicePlatform.macOS.rawValue
        txt["v"] = "1.0.0"
        return txt
    }
    
    // MARK: - Browser (Bonjour Discovery)
    
    public func startBrowsing() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: P2PNetworkManager.serviceType, domain: "local.")
        let params = NWParameters()
        params.includePeerToPeer = true
        
        let browser = NWBrowser(for: descriptor, using: params)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.isBrowsing = true
                case .failed(let err):
                    print("[Waypoint Browser] Failed: \(err.localizedDescription)")
                    self.isBrowsing = false
                case .cancelled:
                    self.isBrowsing = false
                default:
                    break
                }
            }
        }
        
        browser.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor [weak self] in
                self?.handleBrowseResults(results)
            }
        }
        
        browser.start(queue: networkQueue)
        self.browser = browser
    }
    
    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        var updatedPeers: [PeerDevice] = []
        
        for result in results {
            switch result.endpoint {
            case .service(let name, _, _, _):
                // Don't show our own service
                if name == localDeviceName { continue }
                
                var peerId = name
                var model = "Device"
                var platform = DevicePlatform.macOS
                
                // Parse TXT record metadata if resolved
                if case let .bonjour(txt) = result.metadata {
                    if let id = txt["id"] { peerId = id }
                    if let mod = txt["model"] { model = mod }
                    if let plat = txt["platform"], let parsedPlatform = DevicePlatform(rawValue: plat) {
                        platform = parsedPlatform
                    }
                }
                
                let peer = PeerDevice(
                    id: peerId,
                    name: name,
                    platform: platform,
                    model: model,
                    ipAddress: "Local Wi-Fi",
                    port: P2PNetworkManager.defaultPort,
                    isConnected: activeConnections[peerId] != nil,
                    lastSeen: Date(),
                    endpointString: result.endpoint.debugDescription
                )
                updatedPeers.append(peer)
            default:
                break
            }
        }
        
        self.discoveredPeers = updatedPeers
    }
    
    // MARK: - Outbound Connection & Beaming
    
    public func connect(to peer: PeerDevice) {
        guard activeConnections[peer.id] == nil else { return }
        
        let endpoint = NWEndpoint.service(
            name: peer.name,
            type: P2PNetworkManager.serviceType,
            domain: "local.",
            interface: nil
        )
        
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        let params = NWParameters(tls: nil, tcp: tcpOptions)
        params.includePeerToPeer = true
        
        let connection = NWConnection(to: endpoint, using: params)
        registerConnection(connection, peerId: peer.id, peerName: peer.name)
        connection.start(queue: networkQueue)
        
        // Send initial handshake
        sendHandshake(connection: connection)
    }
    
    private func handleIncomingConnection(_ connection: NWConnection) {
        let tempId = UUID().uuidString
        registerConnection(connection, peerId: tempId, peerName: "Incoming Peer")
        connection.start(queue: networkQueue)
    }
    
    private func registerConnection(_ connection: NWConnection, peerId: String, peerName: String) {
        self.activeConnections[peerId] = connection
        
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.updatePeerConnectionState(peerId: peerId, isConnected: true)
                    self.readNextPacket(from: connection, peerId: peerId)
                case .failed(let err):
                    print("[Waypoint Connection] Error on \(peerName): \(err)")
                    self.activeConnections.removeValue(forKey: peerId)
                    self.updatePeerConnectionState(peerId: peerId, isConnected: false)
                case .cancelled:
                    self.activeConnections.removeValue(forKey: peerId)
                    self.updatePeerConnectionState(peerId: peerId, isConnected: false)
                default:
                    break
                }
            }
        }
    }
    
    private func updatePeerConnectionState(peerId: String, isConnected: Bool) {
        if let idx = discoveredPeers.firstIndex(where: { $0.id == peerId }) {
            discoveredPeers[idx].isConnected = isConnected
        }
    }
    
    // MARK: - Packet Read Loop
    
    private func readNextPacket(from connection: NWConnection, peerId: String) {
        // First read the 10-byte header
        connection.receive(minimumIncompleteLength: WaypointPacketHeader.headerLength,
                           maximumLength: WaypointPacketHeader.headerLength) { [weak self] content, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                if let error = error {
                    print("[Waypoint Packet] Read error: \(error.localizedDescription)")
                    return
                }
                
                guard let headerData = content,
                      let header = WaypointPacketHeader.parse(from: headerData) else {
                    if !isComplete {
                        self.readNextPacket(from: connection, peerId: peerId)
                    }
                    return
                }
                
                // Read exact payloadLength
                if header.payloadLength == 0 {
                    self.processPacket(type: header.type, payload: Data(), from: peerId, connection: connection)
                    self.readNextPacket(from: connection, peerId: peerId)
                    return
                }
                
                connection.receive(minimumIncompleteLength: Int(header.payloadLength),
                                   maximumLength: Int(header.payloadLength)) { [weak self] payloadData, _, _, payloadError in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        if let payloadData = payloadData {
                            self.processPacket(type: header.type, payload: payloadData, from: peerId, connection: connection)
                        }
                        self.readNextPacket(from: connection, peerId: peerId)
                    }
                }
            }
        }
    }
    
    // MARK: - Packet Dispatching
    
    private func processPacket(type: WaypointPacketType, payload: Data, from peerId: String, connection: NWConnection) {
        switch type {
        case .handshake:
            if let handshake = try? JSONDecoder().decode(DeviceHandshake.self, from: payload) {
                // Update peer details
                if let index = discoveredPeers.firstIndex(where: { $0.id == peerId || $0.name == handshake.deviceName }) {
                    discoveredPeers[index].name = handshake.deviceName
                    discoveredPeers[index].platform = handshake.platform
                    discoveredPeers[index].model = handshake.model
                    discoveredPeers[index].isConnected = true
                }
                // Reply with HandshakeAck
                sendHandshakeAck(connection: connection)
            }
            
        case .handshakeAck:
            print("[Waypoint Handshake] Handshake acknowledged by peer \(peerId)")
            
        case .ping:
            sendPacket(WaypointPacket(type: .pong, payload: Data()), via: connection)
            
        case .pong:
            break
            
        case .fileManifest:
            handleIncomingFileManifest(payload: payload)
            
        case .fileChunk:
            handleIncomingFileChunk(payload: payload)
            
        case .fileTransferComplete:
            handleIncomingFileComplete(payload: payload)
            
        case .fileTransferCancel:
            break
            
        case .clipboardSync:
            if let clipboardPayload = try? JSONDecoder().decode(ClipboardSyncPayload.self, from: payload) {
                self.onClipboardReceived?(clipboardPayload)
            }
            
        case .notificationRelay:
            if let notification = try? JSONDecoder().decode(NotificationRelayPayload.self, from: payload) {
                self.onNotificationReceived?(notification)
            }
            
        case .mediaMetadataSync:
            if let media = try? JSONDecoder().decode(MediaMetadataPayload.self, from: payload) {
                self.onMediaMetadataReceived?(media)
            }
            
        case .mediaCommand:
            if let command = try? JSONDecoder().decode(MediaCommandPayload.self, from: payload) {
                self.onMediaCommandReceived?(command)
            }
            
        case .videoNALUnit:
            if let nalu = VideoNALUPayload.deserialize(from: payload) {
                self.onVideoFrameReceived?(nalu)
            }
        }
    }
    
    // MARK: - Inbound File Transfer Handling
    
    private func handleIncomingFileManifest(payload: Data) {
        guard let manifest = try? JSONDecoder().decode(FileManifestPayload.self, from: payload) else { return }
        
        let tempURL = receivedFolderURL.appendingPathComponent(".\(manifest.transferId).tmp")
        let destURL = receivedFolderURL.appendingPathComponent(manifest.fileName)
        
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        guard let fileHandle = try? FileHandle(forWritingTo: tempURL) else { return }
        
        incomingFileHandles[manifest.transferId] = (fileHandle, manifest, 0, tempURL, destURL)
        
        let transfer = FileTransferProgress(
            id: manifest.transferId,
            fileName: manifest.fileName,
            fileSize: manifest.fileSize,
            bytesTransferred: 0,
            isOutbound: false,
            targetDeviceName: "Peer",
            isCompleted: false
        )
        activeTransfers.insert(transfer, at: 0)
    }
    
    private func handleIncomingFileChunk(payload: Data) {
        let headerSize = MemoryLayout<UInt32>.size * 2
        guard payload.count > headerSize else { return }
        
        // Read transferId length and header
        // Simple encoding: First 36 bytes UUID string, then chunk index, then chunk data
        guard payload.count >= 40 else { return }
        let transferIdData = payload.subdata(in: 0..<36)
        guard let transferId = String(data: transferIdData, encoding: .utf8),
              var entry = incomingFileHandles[transferId] else { return }
        
        let chunkData = payload.subdata(in: 40..<payload.count)
        entry.handle.write(chunkData)
        entry.receivedBytes += Int64(chunkData.count)
        incomingFileHandles[transferId] = entry
        
        // Update UI Progress
        if let idx = activeTransfers.firstIndex(where: { $0.id == transferId }) {
            activeTransfers[idx].bytesTransferred = entry.receivedBytes
        }
    }
    
    private func handleIncomingFileComplete(payload: Data) {
        guard let transferId = String(data: payload, encoding: .utf8),
              let entry = incomingFileHandles.removeValue(forKey: transferId) else { return }
        
        try? entry.handle.close()
        
        // Rename temp file to final destination
        try? FileManager.default.removeItem(at: entry.destURL)
        try? FileManager.default.moveItem(at: entry.tempURL, to: entry.destURL)
        
        if let idx = activeTransfers.firstIndex(where: { $0.id == transferId }) {
            activeTransfers[idx].bytesTransferred = entry.manifest.fileSize
            activeTransfers[idx].isCompleted = true
        }
        
        print("[Waypoint File] File received completely: \(entry.destURL.lastPathComponent)")
    }
    
    // MARK: - Outbound File Streaming
    
    public func sendFile(url: URL, to peer: PeerDevice) {
        guard let connection = activeConnections[peer.id] ?? activeConnections.values.first else {
            // Auto-connect and then send
            connect(to: peer)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.sendFile(url: url, to: peer)
            }
            return
        }
        
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = fileAttributes[.size] as? Int64 else { return }
        
        let chunkSize = 64 * 1024 // 64 KB
        let totalChunks = Int(ceil(Double(fileSize) / Double(chunkSize)))
        let transferId = UUID().uuidString
        let fileName = url.lastPathComponent
        
        let manifest = FileManifestPayload(
            transferId: transferId,
            fileName: fileName,
            fileSize: fileSize,
            chunkSize: chunkSize,
            totalChunks: totalChunks
        )
        
        let transferUI = FileTransferProgress(
            id: transferId,
            fileName: fileName,
            fileSize: fileSize,
            bytesTransferred: 0,
            isOutbound: true,
            targetDeviceName: peer.name,
            isCompleted: false
        )
        activeTransfers.insert(transferUI, at: 0)
        
        // Send Manifest
        if let manifestData = try? JSONEncoder().encode(manifest) {
            let packet = WaypointPacket(type: .fileManifest, payload: manifestData)
            sendPacket(packet, via: connection)
        }
        
        // Stream Chunks asynchronously
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return }
            defer { try? fileHandle.close() }
            
            var chunkIndex = 0
            var bytesSent: Int64 = 0
            
            while bytesSent < fileSize {
                let chunk = fileHandle.readData(ofLength: chunkSize)
                if chunk.isEmpty { break }
                
                var payload = Data()
                // 36 bytes Transfer ID
                if let idData = transferId.data(using: .utf8) {
                    payload.append(idData)
                }
                var idxBE = UInt32(chunkIndex).bigEndian
                withUnsafeBytes(of: &idxBE) { payload.append(contentsOf: $0) }
                payload.append(chunk)
                
                let chunkPacket = WaypointPacket(type: .fileChunk, payload: payload)
                self?.sendPacket(chunkPacket, via: connection)
                
                bytesSent += Int64(chunk.count)
                chunkIndex += 1
                
                let currentBytes = bytesSent
                Task { @MainActor [weak self] in
                    if let idx = self?.activeTransfers.firstIndex(where: { $0.id == transferId }) {
                        self?.activeTransfers[idx].bytesTransferred = currentBytes
                    }
                }
                
                // Slight throttle to prevent TCP buffer congestion
                usleep(500)
            }
            
            // Send complete signal
            if let completeData = transferId.data(using: .utf8) {
                let completePacket = WaypointPacket(type: .fileTransferComplete, payload: completeData)
                self?.sendPacket(completePacket, via: connection)
            }
            
            Task { @MainActor [weak self] in
                if let idx = self?.activeTransfers.firstIndex(where: { $0.id == transferId }) {
                    self?.activeTransfers[idx].isCompleted = true
                }
            }
        }
    }
    
    // MARK: - Continuity Broadcasters
    
    public func broadcastClipboard(text: String) {
        let payload = ClipboardSyncPayload(
            text: text,
            senderId: localDeviceId,
            senderName: localDeviceName
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let packet = WaypointPacket(type: .clipboardSync, payload: data)
        broadcastPacket(packet)
    }
    
    public func sendMediaCommand(_ command: MediaControlCommandType) {
        let payload = MediaCommandPayload(command: command)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let packet = WaypointPacket(type: .mediaCommand, payload: data)
        broadcastPacket(packet)
    }
    
    // MARK: - Low-Level Packet Transmission
    
    private func sendHandshake(connection: NWConnection) {
        let handshake = DeviceHandshake(
            deviceId: localDeviceId,
            deviceName: localDeviceName,
            platform: .macOS,
            model: "MacBook Pro",
            appVersion: "1.0.0"
        )
        if let data = try? JSONEncoder().encode(handshake) {
            sendPacket(WaypointPacket(type: .handshake, payload: data), via: connection)
        }
    }
    
    private func sendHandshakeAck(connection: NWConnection) {
        sendPacket(WaypointPacket(type: .handshakeAck, payload: Data()), via: connection)
    }
    
    public nonisolated func sendPacket(_ packet: WaypointPacket, via connection: NWConnection) {
        let data = packet.serialize()
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("[Waypoint Packet] Send failed: \(error.localizedDescription)")
            }
        })
    }
    
    public func broadcastPacket(_ packet: WaypointPacket) {
        for (_, connection) in activeConnections {
            sendPacket(packet, via: connection)
        }
    }
}
