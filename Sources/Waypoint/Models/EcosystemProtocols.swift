import Foundation

// MARK: - Device Info & Handshake

public enum DevicePlatform: String, Codable, Sendable {
    case macOS = "macOS"
    case iOS = "iOS"
    case android = "Android"
    case windows = "Windows"
    case linux = "Linux"
    case web = "Web"
}

public struct DeviceHandshake: Codable, Sendable {
    public let deviceId: String
    public let deviceName: String
    public let platform: DevicePlatform
    public let model: String
    public let appVersion: String
    public let supportedFeatures: [String]
    public let localPort: UInt16
    
    public init(
        deviceId: String = UUID().uuidString,
        deviceName: String = Host.current().localizedName ?? "My Mac",
        platform: DevicePlatform = .macOS,
        model: String = "Mac",
        appVersion: String = "1.0.0",
        supportedFeatures: [String] = ["file_transfer", "clipboard_sync", "notification_relay", "media_bridge", "video_mirroring"],
        localPort: UInt16 = 53890
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.platform = platform
        self.model = model
        self.appVersion = appVersion
        self.supportedFeatures = supportedFeatures
        self.localPort = localPort
    }
}

// MARK: - File Transfer Models

public struct FileManifestPayload: Codable, Sendable {
    public let transferId: String
    public let fileName: String
    public let fileSize: Int64
    public let mimeType: String
    public let sha256Checksum: String
    public let chunkSize: Int
    public let totalChunks: Int
    
    public init(
        transferId: String = UUID().uuidString,
        fileName: String,
        fileSize: Int64,
        mimeType: String = "application/octet-stream",
        sha256Checksum: String = "",
        chunkSize: Int = 64 * 1024,
        totalChunks: Int
    ) {
        self.transferId = transferId
        self.fileName = fileName
        self.fileSize = fileSize
        self.mimeType = mimeType
        self.sha256Checksum = sha256Checksum
        self.chunkSize = chunkSize
        self.totalChunks = totalChunks
    }
}

public struct FileChunkHeader: Codable, Sendable {
    public let transferId: String
    public let chunkIndex: Int
    public let totalChunks: Int
    public let dataLength: Int
}

// MARK: - Universal Clipboard Sync

public struct ClipboardSyncPayload: Codable, Sendable {
    public let id: String
    public let text: String
    public let timestamp: TimeInterval
    public let senderId: String
    public let senderName: String
    
    public init(
        id: String = UUID().uuidString,
        text: String,
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        senderId: String,
        senderName: String
    ) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.senderId = senderId
        self.senderName = senderName
    }
}

// MARK: - Notification Relay Receiver

public struct NotificationActionPayload: Codable, Sendable {
    public let actionId: String
    public let title: String
    public let isReply: Bool
    
    public init(actionId: String, title: String, isReply: Bool = false) {
        self.actionId = actionId
        self.title = title
        self.isReply = isReply
    }
}

public struct NotificationRelayPayload: Codable, Sendable {
    public let notificationId: String
    public let packageName: String
    public let appName: String
    public let title: String
    public let text: String
    public let subText: String?
    public let postTime: TimeInterval
    public let iconBase64: String?
    public let actions: [NotificationActionPayload]
    public let isClearable: Bool
    
    public init(
        notificationId: String,
        packageName: String,
        appName: String,
        title: String,
        text: String,
        subText: String? = nil,
        postTime: TimeInterval = Date().timeIntervalSince1970,
        iconBase64: String? = nil,
        actions: [NotificationActionPayload] = [],
        isClearable: Bool = true
    ) {
        self.notificationId = notificationId
        self.packageName = packageName
        self.appName = appName
        self.title = title
        self.text = text
        self.subText = subText
        self.postTime = postTime
        self.iconBase64 = iconBase64
        self.actions = actions
        self.isClearable = isClearable
    }
}

// MARK: - Media Control Bridge

public enum MediaControlCommandType: String, Codable, Sendable {
    case play = "PLAY"
    case pause = "PAUSE"
    case playPauseToggle = "PLAY_PAUSE_TOGGLE"
    case nextTrack = "NEXT"
    case previousTrack = "PREVIOUS"
    case volumeUp = "VOLUME_UP"
    case volumeDown = "VOLUME_DOWN"
    case seek = "SEEK"
}

public struct MediaCommandPayload: Codable, Sendable {
    public let command: MediaControlCommandType
    public let seekPositionSeconds: Double?
    public let volumeStep: Float?
    
    public init(
        command: MediaControlCommandType,
        seekPositionSeconds: Double? = nil,
        volumeStep: Float? = nil
    ) {
        self.command = command
        self.seekPositionSeconds = seekPositionSeconds
        self.volumeStep = volumeStep
    }
}

public struct MediaMetadataPayload: Codable, Sendable {
    public let title: String
    public let artist: String
    public let album: String
    public let durationSeconds: Double
    public let positionSeconds: Double
    public let isPlaying: Bool
    public let artworkBase64: String?
    
    public init(
        title: String,
        artist: String,
        album: String,
        durationSeconds: Double,
        positionSeconds: Double,
        isPlaying: Bool,
        artworkBase64: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
        self.positionSeconds = positionSeconds
        self.isPlaying = isPlaying
        self.artworkBase64 = artworkBase64
    }
}

// MARK: - Low-Latency Video Mirroring

public enum NALUnitType: UInt8, Codable, Sendable {
    case unspecified = 0
    case nonIDR = 1       // P/B-slice
    case idr = 5          // Keyframe / I-slice
    case sei = 6          // Supplemental Enhancement Information
    case sps = 7          // Sequence Parameter Set
    case pps = 8          // Picture Parameter Set
}

public struct VideoNALUPayload: Sendable {
    public let nalType: NALUnitType
    public let isKeyframe: Bool
    public let timestampUs: UInt64
    public let nalData: Data
    
    public init(nalType: NALUnitType, isKeyframe: Bool, timestampUs: UInt64, nalData: Data) {
        self.nalType = nalType
        self.isKeyframe = isKeyframe
        self.timestampUs = timestampUs
        self.nalData = nalData
    }
    
    public func serialize() -> Data {
        var data = Data()
        data.append(nalType.rawValue)
        data.append(isKeyframe ? 1 : 0)
        var tsBigEndian = timestampUs.bigEndian
        withUnsafeBytes(of: &tsBigEndian) { data.append(contentsOf: $0) }
        data.append(nalData)
        return data
    }
    
    public static func deserialize(from data: Data) -> VideoNALUPayload? {
        guard data.count > 10 else { return nil }
        guard let type = NALUnitType(rawValue: data[0]) else { return nil }
        let isKeyframe = data[1] == 1
        var rawTs: UInt64 = 0
        _ = withUnsafeMutableBytes(of: &rawTs) { tsBuf in
            data.copyBytes(to: tsBuf, from: 2..<10)
        }
        let timestampUs = UInt64(bigEndian: rawTs)
        let nalBytes = data.subdata(in: 10..<data.count)
        return VideoNALUPayload(nalType: type, isKeyframe: isKeyframe, timestampUs: timestampUs, nalData: nalBytes)
    }
}

// MARK: - Peer Device & Transfer UI Models

public struct PeerDevice: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var platform: DevicePlatform
    public var model: String
    public var ipAddress: String
    public var port: UInt16
    public var isConnected: Bool
    public var lastSeen: Date
    public var endpointString: String?
    
    public init(
        id: String,
        name: String,
        platform: DevicePlatform = .macOS,
        model: String = "Device",
        ipAddress: String,
        port: UInt16,
        isConnected: Bool = false,
        lastSeen: Date = Date(),
        endpointString: String? = nil
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.model = model
        self.ipAddress = ipAddress
        self.port = port
        self.isConnected = isConnected
        self.lastSeen = lastSeen
        self.endpointString = endpointString
    }
}

public struct FileTransferProgress: Identifiable, Sendable {
    public let id: String
    public let fileName: String
    public let fileSize: Int64
    public var bytesTransferred: Int64
    public var isOutbound: Bool
    public var targetDeviceName: String
    public var isCompleted: Bool
    public var error: String?
    
    public var fractionCompleted: Double {
        guard fileSize > 0 else { return 0 }
        return min(1.0, max(0.0, Double(bytesTransferred) / Double(fileSize)))
    }
    
    public var formattedSpeed: String {
        let mb = Double(bytesTransferred) / (1024 * 1024)
        let totalMb = Double(fileSize) / (1024 * 1024)
        return String(format: "%.1f / %.1f MB", mb, totalMb)
    }
    
    public init(
        id: String = UUID().uuidString,
        fileName: String,
        fileSize: Int64,
        bytesTransferred: Int64 = 0,
        isOutbound: Bool = true,
        targetDeviceName: String = "Peer",
        isCompleted: Bool = false,
        error: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.fileSize = fileSize
        self.bytesTransferred = bytesTransferred
        self.isOutbound = isOutbound
        self.targetDeviceName = targetDeviceName
        self.isCompleted = isCompleted
        self.error = error
    }
}
