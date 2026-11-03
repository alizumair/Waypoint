import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation

public struct MainWindowView: View {
    @ObservedObject var networkManager = P2PNetworkManager.shared
    @ObservedObject var webServer = LocalWebServer.shared
    @ObservedObject var continuity = ContinuityManager.shared
    @ObservedObject var videoPipeline = VideoStreamingPipeline.shared
    
    @State private var selectedNav: NavigationSection = .radar
    @State private var isTargetedForDrop: Bool = false
    @State private var quickBeamText: String = ""
    @State private var copiedURLFeedback: Bool = false
    
    public enum NavigationSection: String, CaseIterable, Identifiable {
        case radar = "Radar & Peers"
        case guestWeb = "Guest Web Portal"
        case transfers = "Transfers Hub"
        case continuity = "Continuity Suite"
        case screenMirror = "Screen Mirroring"
        case settings = "Settings & Storage"
        
        public var id: String { self.rawValue }
        
        public var iconName: String {
            switch self {
            case .radar: return "antenna.radiowaves.left.and.right"
            case .guestWeb: return "globe.badge.chevron.backward"
            case .transfers: return "arrow.up.arrow.down.circle"
            case .continuity: return "doc.on.clipboard"
            case .screenMirror: return "display.2"
            case .settings: return "gearshape"
            }
        }
    }
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            detailContent
                .frame(minWidth: 620, minHeight: 520)
        }
        .frame(minWidth: 860, minHeight: 600)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                HStack(spacing: 8) {
                    Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.accentColor)
                    
                    Text("Waypoint")
                        .font(.headline)
                        .fontWeight(.bold)
                }
            }
            
            ToolbarItemGroup(placement: .primaryAction) {
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(networkManager.isListening ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(networkManager.isListening ? "Listening on Wi-Fi" : "Offline")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(12)
                    
                    Button(action: {
                        NSWorkspace.shared.open(networkManager.receivedFolderURL)
                    }) {
                        Label("Downloads", systemImage: "folder")
                    }
                    .help("Open Waypoint Received folder in Finder")
                }
            }
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebarContent: some View {
        List(NavigationSection.allCases, id: \.self, selection: $selectedNav) { section in
            NavigationLink(value: section) {
                Label {
                    Text(section.rawValue)
                        .font(.system(size: 13, weight: .medium))
                } icon: {
                    Image(systemName: section.iconName)
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)
                }
                .badge(badgeForSection(section))
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            sidebarFooter
        }
    }
    
    private func badgeForSection(_ section: NavigationSection) -> Int {
        switch section {
        case .radar:
            return networkManager.discoveredPeers.count
        case .transfers:
            return networkManager.activeTransfers.filter { !$0.isCompleted }.count
        default:
            return 0
        }
    }
    
    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(networkManager.localDeviceName)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Text("IP: \(webServer.localIP)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Detail Content Switcher
    
    @ViewBuilder
    private var detailContent: some View {
        switch selectedNav {
        case .radar:
            radarPeersView
        case .guestWeb:
            guestWebPortalView
        case .transfers:
            transfersHubView
        case .continuity:
            continuitySuiteView
        case .screenMirror:
            screenMirrorView
        case .settings:
            settingsStorageView
        }
    }
    
    // MARK: - 1. Radar & Peers View
    
    private var radarPeersView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerBanner(
                    title: "Nearby Radar & Local Peers",
                    subtitle: "Zero-configuration Bonjour discovery on your Wi-Fi network. Beam files directly to any connected device."
                )
                
                // Drag-and-drop beaming banner
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            isTargetedForDrop ? Color.accentColor : Color.secondary.opacity(0.3),
                            style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                        )
                        .background(isTargetedForDrop ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.02))
                    
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 30))
                            .foregroundColor(isTargetedForDrop ? .accentColor : .secondary)
                        
                        Text("Drop files here to beam to connected peers")
                            .font(.system(size: 14, weight: .semibold))
                        
                        Text("Files are sent over direct encrypted TCP chunks or staged for guest web download")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(24)
                }
                .frame(height: 130)
                .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
                    handleDroppedFiles(providers)
                    return true
                }
                
                // Discovered peers grid
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Discovered Devices (\(networkManager.discoveredPeers.count))")
                            .font(.headline)
                        
                        Spacer()
                        
                        if networkManager.isBrowsing {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Scanning...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    if networkManager.discoveredPeers.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("No peers discovered yet on this Wi-Fi network.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("Ensure other devices have Waypoint running or scan the Guest Web QR code.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                        .background(Color.primary.opacity(0.02))
                        .cornerRadius(12)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260))], spacing: 14) {
                            ForEach(networkManager.discoveredPeers) { peer in
                                peerCard(peer)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    private func peerCard(_ peer: PeerDevice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: iconForPlatform(peer.platform))
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(peer.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text("\(peer.platform.rawValue) • \(peer.model)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Circle()
                    .fill(peer.isConnected ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 8, height: 8)
            }
            
            Divider().opacity(0.4)
            
            HStack {
                Button(action: {
                    selectAndSendFiles(to: peer)
                }) {
                    Label("Send File", systemImage: "paperplane")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                
                Spacer()
                
                Button(action: {
                    networkManager.connect(to: peer)
                }) {
                    Text(peer.isConnected ? "Connected" : "Connect")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    private func selectAndSendFiles(to peer: PeerDevice) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                networkManager.sendFile(url: url, to: peer)
            }
        }
    }
    
    // MARK: - 2. Guest Web Portal View
    
    private var guestWebPortalView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerBanner(
                    title: "Guest Web Portal & QR Connect",
                    subtitle: "No app required on guest devices. Windows PCs, Android phones, and iPhones can open your Mac's portal in their browser to download shared files and upload new ones."
                )
                
                // Server Control Bar
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HTTP Fallback Server Status")
                            .font(.system(size: 13, weight: .semibold))
                        Text(webServer.isRunning ? "Online at \(webServer.serverURLString)" : "Offline (stopped)")
                            .font(.system(size: 11))
                            .foregroundColor(webServer.isRunning ? .green : .secondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: Binding(
                        get: { webServer.isRunning },
                        set: { $0 ? webServer.start() : webServer.stop() }
                    ))
                    .toggleStyle(.switch)
                }
                .padding(14)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(12)
                
                if webServer.isRunning {
                    HStack(alignment: .top, spacing: 24) {
                        // QR Code Card
                        VStack(spacing: 12) {
                            if let qr = webServer.qrCodeImage {
                                Image(nsImage: qr)
                                    .interpolation(.none)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 180, height: 180)
                                    .padding(10)
                                    .background(Color.white)
                                    .cornerRadius(14)
                                    .shadow(color: .black.opacity(0.15), radius: 8)
                            }
                            
                            Text("Scan with phone camera to connect")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text(webServer.serverURLString)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(webServer.serverURLString, forType: .string)
                                    copiedURLFeedback = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedURLFeedback = false }
                                }) {
                                    Image(systemName: copiedURLFeedback ? "checkmark" : "doc.on.doc")
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: {
                                    if let url = URL(string: webServer.serverURLString) {
                                        NSWorkspace.shared.open(url)
                                    }
                                }) {
                                    Image(systemName: "safari")
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(8)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(8)
                        }
                        .frame(width: 240)
                        .padding(16)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(14)
                        
                        // Staged Files for Guests
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Files Shared for Guest Download (\(webServer.stagedFiles.count))")
                                    .font(.system(size: 13, weight: .semibold))
                                
                                Spacer()
                                
                                Button(action: stageFilesForGuest) {
                                    Label("Add Files", systemImage: "plus")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            if webServer.stagedFiles.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "tray")
                                        .font(.system(size: 28))
                                        .foregroundColor(.secondary.opacity(0.6))
                                    Text("No files currently staged for guests.")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    Text("Click 'Add Files' or drop files into Waypoint to make them available for download.")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary.opacity(0.8))
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(30)
                                .background(Color.primary.opacity(0.02))
                                .cornerRadius(10)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(webServer.stagedFiles, id: \.self) { url in
                                        HStack {
                                            Image(systemName: "doc.fill")
                                                .foregroundColor(.accentColor)
                                            Text(url.lastPathComponent)
                                                .font(.system(size: 12, weight: .medium))
                                                .lineLimit(1)
                                            Spacer()
                                            Button(action: { webServer.removeStagedFile(url: url) }) {
                                                Image(systemName: "xmark.circle")
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(8)
                                        .background(Color.primary.opacity(0.04))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                            
                            // Guest Upload Instruction
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Guest Uploads Enabled", systemImage: "arrow.up.circle")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.accentColor)
                                Text("Guests can tap 'Choose Files' or drag photos/documents on the web portal. All uploaded files stream directly to your 'Waypoint Received' folder.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .padding(12)
                            .background(Color.accentColor.opacity(0.08))
                            .cornerRadius(10)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    private func stageFilesForGuest() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            for url in panel.urls {
                webServer.stageFile(url: url)
            }
        }
    }
    
    // MARK: - 3. Transfers Hub View
    
    private var transfersHubView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerBanner(
                    title: "Transfers Hub",
                    subtitle: "Track live high-speed file transfers across local sockets and incoming uploads from guest web browsers."
                )
                
                HStack {
                    Text("Transfer Queue (\(networkManager.activeTransfers.count))")
                        .font(.headline)
                    Spacer()
                    Button("Open Received Folder") {
                        NSWorkspace.shared.open(networkManager.receivedFolderURL)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                if networkManager.activeTransfers.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.up.arrow.down.circle")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No active or recent file transfers.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(50)
                    .background(Color.primary.opacity(0.02))
                    .cornerRadius(12)
                } else {
                    VStack(spacing: 10) {
                        ForEach(networkManager.activeTransfers) { transfer in
                            transferRow(transfer)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    private func transferRow(_ transfer: FileTransferProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: transfer.isOutbound ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(transfer.isOutbound ? .blue : .green)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(transfer.fileName)
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(transfer.isOutbound ? "Sending to" : "Received from") \(transfer.targetDeviceName)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if transfer.isCompleted {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Completed")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green)
                    }
                } else {
                    Text(transfer.formattedSpeed)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            
            ProgressView(value: transfer.fractionCompleted)
                .progressViewStyle(.linear)
                .tint(transfer.isCompleted ? .green : .accentColor)
        }
        .padding(14)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(10)
    }
    
    // MARK: - 4. Continuity Suite View
    
    private var continuitySuiteView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerBanner(
                    title: "Continuity Suite",
                    subtitle: "Universal clipboard synchronization, Android notification mirroring, and remote media player controls."
                )
                
                // Universal Clipboard Box
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Universal Clipboard", systemImage: "doc.on.clipboard")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Toggle("", isOn: $continuity.isClipboardSyncEnabled)
                            .toggleStyle(.switch)
                    }
                    
                    Text("Any text copied on your Mac automatically syncs across connected devices, and text copied on your phone updates your Mac pasteboard silently.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    if !continuity.latestClipboardSnippet.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Latest Synced Text:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(continuity.latestClipboardSnippet)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.04))
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(16)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(12)
                
                // Mirrored Notifications Box
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Notification Relay Receiver", systemImage: "bell.badge")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Toggle("", isOn: $continuity.isNotificationRelayEnabled)
                            .toggleStyle(.switch)
                    }
                    
                    Text("Incoming Android notifications mirror natively to macOS Notification Center with support for quick replies and notification actions.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    if let notif = continuity.latestNotification {
                        HStack(spacing: 12) {
                            Image(systemName: "app.badge.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(notif.appName) • \(notif.title)")
                                    .font(.system(size: 12, weight: .bold))
                                Text(notif.text)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(8)
                    }
                }
                .padding(16)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(12)
                
                // Media Control Bridge Box
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Media Control Bridge", systemImage: "playpause.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Toggle("", isOn: $continuity.isMediaBridgeEnabled)
                            .toggleStyle(.switch)
                    }
                    
                    HStack(spacing: 20) {
                        Button(action: { continuity.sendRemoteMediaCommand(.previousTrack) }) {
                            Image(systemName: "backward.fill")
                        }
                        Button(action: { continuity.sendRemoteMediaCommand(.playPauseToggle) }) {
                            Image(systemName: "playpause.fill")
                        }
                        Button(action: { continuity.sendRemoteMediaCommand(.nextTrack) }) {
                            Image(systemName: "forward.fill")
                        }
                        
                        Divider().frame(height: 20)
                        
                        Button(action: { continuity.sendRemoteMediaCommand(.volumeDown) }) {
                            Image(systemName: "speaker.wave.1.fill")
                        }
                        Button(action: { continuity.sendRemoteMediaCommand(.volumeUp) }) {
                            Image(systemName: "speaker.wave.3.fill")
                        }
                    }
                    .font(.system(size: 16))
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                .padding(16)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(12)
            }
            .padding(24)
        }
    }
    
    // MARK: - 5. Screen Mirroring View
    
    private var screenMirrorView: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hardware-Accelerated Screen Mirroring")
                        .font(.headline)
                    Text("Direct AVC/H.264 stream rendered via AVSampleBufferDisplayLayer with zero latency")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                if videoPipeline.isStreamActive {
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("\(Int(videoPipeline.currentResolution.width))x\(Int(videoPipeline.currentResolution.height))")
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(8)
                }
                
                Button("Reset Stream") {
                    videoPipeline.resetStream()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            // Video Display Canvas
            ZStack {
                Color.black.cornerRadius(12)
                
                VideoDisplayView(displayLayer: videoPipeline.displayLayer)
                    .cornerRadius(12)
                
                if !videoPipeline.isStreamActive {
                    VStack(spacing: 10) {
                        Image(systemName: "display.trianglebadge.exclamationmark")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("Waiting for incoming video stream...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("Connect a companion device running the Waypoint Screen Mirror module")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(24)
    }
    
    // MARK: - 6. Settings & Storage View
    
    private var settingsStorageView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerBanner(
                    title: "Settings & Local Storage",
                    subtitle: "Configure designated download paths, network ports, and discovery parameters."
                )
                
                VStack(alignment: .leading, spacing: 14) {
                    Text("Storage Location")
                        .font(.system(size: 13, weight: .semibold))
                    
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.accentColor)
                        Text(networkManager.receivedFolderURL.path)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Button("Change...") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.canCreateDirectories = true
                            if panel.runModal() == .OK, let selectedURL = panel.url {
                                networkManager.updateReceivedFolder(url: selectedURL)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(10)
                }
                .padding(16)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(12)
                
                VStack(alignment: .leading, spacing: 14) {
                    Text("Network Configuration")
                        .font(.system(size: 13, weight: .semibold))
                    
                    HStack {
                        Text("Bonjour Service Type:")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("_waypoint._tcp")
                            .font(.system(size: 12, design: .monospaced))
                    }
                    Divider().opacity(0.4)
                    HStack {
                        Text("TCP P2P Port:")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(P2PNetworkManager.defaultPort)")
                            .font(.system(size: 12, design: .monospaced))
                    }
                    Divider().opacity(0.4)
                    HStack {
                        Text("HTTP Guest Portal Port:")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(webServer.port)")
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
                .padding(16)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(12)
            }
            .padding(24)
        }
    }
    
    // MARK: - Helpers
    
    private func headerBanner(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private func iconForPlatform(_ platform: DevicePlatform) -> String {
        switch platform {
        case .macOS: return "laptopcomputer"
        case .iOS: return "iphone"
        case .android: return "phone.badge.waveform"
        case .windows: return "pc"
        case .linux: return "terminal"
        case .web: return "globe"
        }
    }
    
    private func handleDroppedFiles(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    webServer.stageFile(url: url)
                    if let firstPeer = networkManager.discoveredPeers.first(where: { $0.isConnected }) {
                        networkManager.sendFile(url: url, to: firstPeer)
                    }
                }
            }
        }
    }
}

// NSView wrapper to host AVSampleBufferDisplayLayer
public struct VideoDisplayView: NSViewRepresentable {
    public let displayLayer: AVSampleBufferDisplayLayer
    
    public init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
    }
    
    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer = displayLayer
        return view
    }
    
    public func updateNSView(_ nsView: NSView, context: Context) {
        displayLayer.frame = nsView.bounds
    }
}
