import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct PopoverView: View {
    @ObservedObject var networkManager = P2PNetworkManager.shared
    @ObservedObject var webServer = LocalWebServer.shared
    @ObservedObject var continuity = ContinuityManager.shared
    
    @State private var selectedTab: DashboardTab = .peers
    @State private var isTargetedForDrop: Bool = false
    @State private var quickTextInput: String = ""
    @State private var copiedURLFeedback: Bool = false
    
    public enum DashboardTab: String, CaseIterable, Identifiable {
        case peers = "Peers"
        case web = "Guest Web"
        case continuity = "Continuity"
        public var id: String { self.rawValue }
    }
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            headerBar
            
            Divider().opacity(0.4)
            
            // MARK: - Navigation Tabs
            tabSelector
            
            // MARK: - Content Area
            ScrollView {
                VStack(spacing: 16) {
                    switch selectedTab {
                    case .peers:
                        peersSection
                        dragAndDropZone
                        if !networkManager.activeTransfers.isEmpty {
                            transfersSection
                        }
                    case .web:
                        webFallbackSection
                    case .continuity:
                        continuitySection
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: 480)
            
            Divider().opacity(0.4)
            
            // MARK: - Footer Actions
            footerBar
        }
        .frame(width: 380)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
    }
    
    // MARK: - Subviews
    
    private var headerBar: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Waypoint")
                        .font(.system(size: 14, weight: .bold))
                    Text(networkManager.localDeviceName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Live Status Indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(networkManager.isListening ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                    .shadow(color: (networkManager.isListening ? Color.green : Color.orange).opacity(0.6), radius: 3)
                
                Text(networkManager.isListening ? "Broadcasting" : "Offline")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private var tabSelector: some View {
        Picker("Dashboard Tab", selection: $selectedTab) {
            ForEach(DashboardTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    // MARK: - Peers Section
    
    private var peersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Discovered Peers (\(networkManager.discoveredPeers.count))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                if networkManager.isBrowsing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                }
            }
            
            if networkManager.discoveredPeers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.7))
                    Text("Scanning local Wi-Fi for nearby devices...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(10)
            } else {
                VStack(spacing: 6) {
                    ForEach(networkManager.discoveredPeers) { peer in
                        peerRow(peer)
                    }
                }
            }
        }
    }
    
    private func peerRow(_ peer: PeerDevice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconForPlatform(peer.platform))
                .font(.system(size: 18))
                .foregroundColor(.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(peer.name)
                    .font(.system(size: 13, weight: .medium))
                Text("\(peer.platform.rawValue) • \(peer.ipAddress)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                networkManager.connect(to: peer)
            }) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(peer.isConnected ? Color.green : Color.gray.opacity(0.5))
                        .frame(width: 6, height: 6)
                    Text(peer.isConnected ? "Connected" : "Connect")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(peer.isConnected ? Color.green.opacity(0.15) : Color.primary.opacity(0.08))
                .foregroundColor(peer.isConnected ? .green : .primary)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(10)
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
    
    // MARK: - Drag and Drop Zone
    
    private var dragAndDropZone: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isTargetedForDrop ? Color.accentColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
                    .background(isTargetedForDrop ? Color.accentColor.opacity(0.06) : Color.primary.opacity(0.02))
                    .cornerRadius(12)
                
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 22))
                        .foregroundColor(isTargetedForDrop ? .accentColor : .secondary)
                    
                    Text("Drop files here to beam")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text("Beams to connected peers or stages for Web Guest download")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .padding(.vertical, 18)
            }
            .frame(height: 105)
            .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
                handleDroppedFiles(providers)
                return true
            }
            
            // Quick text beam
            HStack {
                TextField("Quick beam text...", text: $quickTextInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                
                Button("Beam") {
                    guard !quickTextInput.isEmpty else { return }
                    P2PNetworkManager.shared.broadcastClipboard(text: quickTextInput)
                    webServer.stagedText = quickTextInput
                    quickTextInput = ""
                }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }
    
    private func handleDroppedFiles(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                
                Task { @MainActor in
                    // Stage for guest web
                    webServer.stageFile(url: url)
                    
                    // Beam to first connected peer if available
                    if let firstPeer = networkManager.discoveredPeers.first(where: { $0.isConnected }) {
                        networkManager.sendFile(url: url, to: firstPeer)
                    }
                }
            }
        }
    }
    
    // MARK: - File Transfer Cards
    
    private var transfersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Transfers")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                ForEach(networkManager.activeTransfers.prefix(3)) { transfer in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: transfer.isOutbound ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                .foregroundColor(transfer.isOutbound ? .blue : .green)
                            
                            Text(transfer.fileName)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            
                            Spacer()
                            
                            if transfer.isCompleted {
                                Text("Complete")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.green)
                            } else {
                                Text(transfer.formattedSpeed)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        ProgressView(value: transfer.fractionCompleted)
                            .progressViewStyle(.linear)
                            .tint(transfer.isCompleted ? .green : .accentColor)
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)
                }
            }
        }
    }
    
    // MARK: - Web Fallback Section
    
    private var webFallbackSection: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fallback Guest Mode")
                        .font(.system(size: 13, weight: .bold))
                    Text("Connect Windows, Android, or guest browsers")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { webServer.isRunning },
                    set: { $0 ? webServer.start() : webServer.stop() }
                ))
                .toggleStyle(.switch)
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(10)
            
            if webServer.isRunning {
                VStack(spacing: 12) {
                    // QR Code
                    if let qrImage = webServer.qrCodeImage {
                        Image(nsImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 150, height: 150)
                            .padding(8)
                            .background(Color.white)
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.15), radius: 6)
                    }
                    
                    Text("Scan with phone camera to connect")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    // URL and Copy
                    HStack {
                        Text(webServer.serverURLString)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(webServer.serverURLString, forType: .string)
                            copiedURLFeedback = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedURLFeedback = false
                            }
                        }) {
                            Image(systemName: copiedURLFeedback ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            if let url = URL(string: webServer.serverURLString) {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            Image(systemName: "safari")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)
                    
                    // Staged files list count
                    if !webServer.stagedFiles.isEmpty {
                        Text("\(webServer.stagedFiles.count) file(s) staged for guest download")
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                    }
                }
            }
        }
    }
    
    // MARK: - Continuity Section
    
    private var continuitySection: some View {
        VStack(spacing: 14) {
            // Clipboard Sync Box
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Universal Clipboard", systemImage: "doc.on.clipboard")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Toggle("", isOn: $continuity.isClipboardSyncEnabled)
                        .toggleStyle(.switch)
                        .scaleEffect(0.8)
                }
                
                if !continuity.latestClipboardSnippet.isEmpty {
                    Text(continuity.latestClipboardSnippet)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(6)
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(10)
            
            // Notification Relay Box
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Notification Relay", systemImage: "bell.badge")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Toggle("", isOn: $continuity.isNotificationRelayEnabled)
                        .toggleStyle(.switch)
                        .scaleEffect(0.8)
                }
                
                if let notif = continuity.latestNotification {
                    HStack(spacing: 8) {
                        Image(systemName: "app.badge")
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(notif.appName)
                                .font(.system(size: 10, weight: .bold))
                            Text(notif.title)
                                .font(.system(size: 11))
                                .lineLimit(1)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(6)
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(10)
            
            // Media Control Bridge Box
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Media Control Bridge", systemImage: "playpause")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Toggle("", isOn: $continuity.isMediaBridgeEnabled)
                        .toggleStyle(.switch)
                        .scaleEffect(0.8)
                }
                
                HStack(spacing: 16) {
                    Button(action: { continuity.sendRemoteMediaCommand(.previousTrack) }) {
                        Image(systemName: "backward.fill")
                    }
                    Button(action: { continuity.sendRemoteMediaCommand(.playPauseToggle) }) {
                        Image(systemName: "playpause.fill")
                    }
                    Button(action: { continuity.sendRemoteMediaCommand(.nextTrack) }) {
                        Image(systemName: "forward.fill")
                    }
                    Spacer()
                    Button(action: { continuity.sendRemoteMediaCommand(.volumeDown) }) {
                        Image(systemName: "speaker.wave.1.fill")
                    }
                    Button(action: { continuity.sendRemoteMediaCommand(.volumeUp) }) {
                        Image(systemName: "speaker.wave.3.fill")
                    }
                }
                .font(.system(size: 14))
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(10)
        }
    }
    
    // MARK: - Footer Bar
    
    private var footerBar: some View {
        HStack {
            Button(action: {
                NSWorkspace.shared.open(networkManager.receivedFolderURL)
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                    Text("Received Folder")
                }
                .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// VisualEffectView for macOS vibrancy popover effect
public struct VisualEffectView: NSViewRepresentable {
    public let material: NSVisualEffectView.Material
    public let blendingMode: NSVisualEffectView.BlendingMode
    
    public init(material: NSVisualEffectView.Material, blendingMode: NSVisualEffectView.BlendingMode) {
        self.material = material
        self.blendingMode = blendingMode
    }
    
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
