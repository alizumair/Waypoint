import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation

public struct MainWindowView: View {
    @ObservedObject var networkManager = P2PNetworkManager.shared
    @ObservedObject var webServer = LocalWebServer.shared
    @ObservedObject var continuity = ContinuityManager.shared
    @ObservedObject var videoPipeline = VideoStreamingPipeline.shared
    
    @State private var activeTab: WindowTab = .notifications
    @State private var isScreenMirroringActive: Bool = false
    @State private var isTargetedForDrop: Bool = false
    @State private var quickTextInput: String = ""
    @State private var expandedAppGroups: Set<String> = []
    @State private var showClipboardSheet: Bool = false
    
    public enum WindowTab: String, CaseIterable, Identifiable {
        case notifications = "Notifications"
        case mirror = "Screen Mirror"
        case fileShare = "File Share"
        case settings = "Settings"
        
        public var id: String { self.rawValue }
        
        public var iconName: String {
            switch self {
            case .notifications: return "bell.fill"
            case .mirror: return "rectangle.fill"
            case .fileShare: return "square.and.arrow.up.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // macOS Vibrant Translucent Background with subtle warm ambient aura matching reference
            ambientGlassBackground
            
            VStack(spacing: 0) {
                // Top Custom macOS Titlebar & Navigation Toolbar
                customTopBar
                
                // Main Split Stage: Left Phone Bezel + Right Content
                HStack(alignment: .top, spacing: 24) {
                    // Left Column: Interactive Connected Phone Device Card
                    leftPhoneCard
                        .frame(width: 280)
                    
                    // Right Column: Dynamic Stage
                    VStack(alignment: .leading, spacing: 0) {
                        switch activeTab {
                        case .notifications:
                            notificationStreamView
                        case .mirror:
                            screenMirrorStageView
                        case .fileShare:
                            fileSharePortalView
                        case .settings:
                            settingsPortalView
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(minWidth: 920, minHeight: 640)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showClipboardSheet) {
            clipboardSyncSheet
        }
    }
    
    // MARK: - Ambient Glass Background
    
    private var ambientGlassBackground: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
            
            // Warm sunset aura inspired by the reference image
            RadialGradient(
                colors: [
                    Color(red: 0.85, green: 0.45, blue: 0.25).opacity(0.18),
                    Color(red: 0.65, green: 0.35, blue: 0.15).opacity(0.10),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 80,
                endRadius: 550
            )
            
            Color.black.opacity(0.45)
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Custom Top Bar
    
    private var customTopBar: some View {
        HStack {
            // Left Device Name
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .shadow(color: .green.opacity(0.6), radius: 3)
                
                Text(connectedDeviceName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            // Center Segmented Capsule Toolbar
            HStack(spacing: 4) {
                ForEach(WindowTab.allCases) { tab in
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            activeTab = tab
                            if tab == .mirror {
                                isScreenMirroringActive = true
                            }
                        }
                    }) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(activeTab == tab ? .white : .secondary)
                            .frame(width: 34, height: 30)
                            .background(activeTab == tab ? Color.white.opacity(0.2) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color.black.opacity(0.35))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            
            Spacer()
            
            // Right Quick Actions (Clipboard + Beacon counter)
            HStack(spacing: 12) {
                Button(action: { showClipboardSheet = true }) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 32, height: 30)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("Universal Clipboard")
                
                // Wireless Beacon with Notification Badge
                ZStack(alignment: .topTrailing) {
                    Button(action: { activeTab = .notifications }) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 32, height: 30)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    if !continuity.notificationHistory.isEmpty {
                        Text("\(continuity.notificationHistory.count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .offset(x: 5, y: -4)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    private var connectedDeviceName: String {
        if let first = networkManager.discoveredPeers.first(where: { $0.isConnected }) {
            return first.name
        }
        return "Sameera's Pixel"
    }
    
    // MARK: - Left Column: Phone Device Mockup Card
    
    private var leftPhoneCard: some View {
        VStack(spacing: 16) {
            // Realistic Phone Frame
            ZStack {
                // Phone Wallpaper / Gradient Screen
                RoundedRectangle(cornerRadius: 32)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.10, green: 0.20, blue: 0.40),
                                Color(red: 0.35, green: 0.55, blue: 0.75),
                                Color(red: 0.95, green: 0.65, blue: 0.55),
                                Color(red: 0.85, green: 0.35, blue: 0.35)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        // Subtle star / clouds effect
                        VStack {
                            Spacer()
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 180, height: 180)
                                .blur(radius: 20)
                                .offset(y: 40)
                        }
                    )
                
                // If mirroring is active, render live video stream inside the phone frame
                if isScreenMirroringActive && videoPipeline.isStreamActive {
                    VideoDisplayView(displayLayer: videoPipeline.displayLayer)
                        .clipShape(RoundedRectangle(cornerRadius: 32))
                } else {
                    // Default Ambient Phone UI matching reference screenshot
                    VStack(spacing: 0) {
                        // Top Status Bar (Battery + Volume)
                        HStack {
                            HStack(spacing: 5) {
                                Image(systemName: "battery.100")
                                    .font(.system(size: 11))
                                Text("100%")
                                    .font(.system(size: 10, weight: .semibold))
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 10))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.35))
                            .clipShape(Capsule())
                        }
                        .padding(.top, 14)
                        
                        Spacer()
                        
                        // Large Digital Clock
                        VStack(spacing: -6) {
                            Text(currentHourString)
                                .font(.system(size: 54, weight: .medium, design: .rounded))
                            Text(currentMinuteString)
                                .font(.system(size: 54, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.25), radius: 6)
                        
                        Spacer()
                        
                        // Embedded Media Player Card
                        mediaPlayerWidget
                            .padding(.horizontal, 14)
                            .padding(.bottom, 12)
                        
                        // Quick Action Buttons (Share + Mirror)
                        HStack(spacing: 8) {
                            Button(action: { activeTab = .fileShare }) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 48, height: 38)
                                    .background(Color.white.opacity(0.25))
                                    .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                withAnimation {
                                    activeTab = .mirror
                                    isScreenMirroringActive.toggle()
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "iphone")
                                        .font(.system(size: 13))
                                    Text("Mirror")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(Color.white.opacity(0.25))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 16)
                    }
                }
            }
            .frame(height: 480)
            .clipShape(RoundedRectangle(cornerRadius: 32))
            .overlay(
                RoundedRectangle(cornerRadius: 32)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
            
            // Disconnect Button
            Button(action: {
                if let first = networkManager.discoveredPeers.first(where: { $0.isConnected }) {
                    networkManager.connect(to: first)
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                    Text("Disconnect")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.35))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    private var mediaPlayerWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                
                Text(continuity.currentMediaMetadata?.title ?? "Run")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            
            Text(continuity.currentMediaMetadata?.artist ?? "Becky Hill & Galantis")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
            
            // Controls
            HStack {
                Spacer()
                Button(action: { continuity.sendRemoteMediaCommand(.previousTrack) }) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: { continuity.sendRemoteMediaCommand(.playPauseToggle) }) {
                    Image(systemName: (continuity.currentMediaMetadata?.isPlaying ?? true) ? "pause.fill" : "play.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color(red: 0.10, green: 0.50, blue: 1.0))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: { continuity.sendRemoteMediaCommand(.nextTrack) }) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(12)
        .background(Color.black.opacity(0.40))
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
    
    private var currentHourString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH"
        return formatter.string(from: Date())
    }
    
    private var currentMinuteString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "mm"
        return formatter.string(from: Date())
    }
    
    // MARK: - Right Column: Grouped Notification Stream View
    
    private var notificationStreamView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Group notifications by App Name
                let grouped = Dictionary(grouping: continuity.notificationHistory, by: { $0.appName })
                let sortedKeys = grouped.keys.sorted()
                
                if sortedKeys.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("No notifications received yet")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(60)
                } else {
                    ForEach(sortedKeys, id: \.self) { appKey in
                        if let items = grouped[appKey], let first = items.first {
                            VStack(alignment: .leading, spacing: 8) {
                                // Group Header
                                Text(appKey)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.6))
                                    .padding(.leading, 4)
                                
                                // Primary Card
                                notificationCard(first)
                                
                                // Show More button if more than 1 notification for this app
                                if items.count > 1 {
                                    let isExpanded = expandedAppGroups.contains(appKey)
                                    
                                    if isExpanded {
                                        ForEach(items.dropFirst()) { notif in
                                            notificationCard(notif)
                                        }
                                    }
                                    
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            if isExpanded {
                                                expandedAppGroups.remove(appKey)
                                            } else {
                                                expandedAppGroups.insert(appKey)
                                            }
                                        }
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                                .font(.system(size: 10, weight: .bold))
                                            Text(isExpanded ? "Show Less" : "Show \(items.count - 1) More")
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .foregroundColor(.white.opacity(0.7))
                                        .padding(.leading, 12)
                                        .padding(.top, 2)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.top, 8)
        }
    }
    
    private func notificationCard(_ item: NotificationRelayPayload) -> some View {
        HStack(spacing: 14) {
            // Brand Icon Circle
            brandIconView(appName: item.appName, packageName: item.packageName)
            
            // Text Content
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(item.text)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            Color.black.opacity(0.35)
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
    
    @ViewBuilder
    private func brandIconView(appName: String, packageName: String) -> some View {
        let name = appName.lowercased()
        if name.contains("facebook") {
            ZStack {
                Circle().fill(Color(red: 0.09, green: 0.47, blue: 0.95))
                Text("f")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .offset(x: 2, y: 1)
            }
            .frame(width: 36, height: 36)
        } else if name.contains("github") {
            ZStack {
                Circle().fill(Color(red: 0.12, green: 0.12, blue: 0.15))
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 36, height: 36)
        } else if name.contains("gmail") {
            ZStack {
                Circle().fill(Color.white)
                Image(systemName: "envelope.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color(red: 0.92, green: 0.26, blue: 0.21))
            }
            .frame(width: 36, height: 36)
        } else if name.contains("whatsapp") {
            ZStack {
                Circle().fill(Color(red: 0.15, green: 0.78, blue: 0.35))
                Image(systemName: "phone.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
            }
            .frame(width: 36, height: 36)
        } else {
            ZStack {
                Circle().fill(Color.accentColor)
                Image(systemName: "bell.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.white)
            }
            .frame(width: 36, height: 36)
        }
    }
    
    // MARK: - Screen Mirror Full Stage View
    
    private var screenMirrorStageView: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Display Mirroring")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Low-latency H.264 stream rendered with VideoToolbox hardware acceleration")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Reset Stream") {
                    videoPipeline.resetStream()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            ZStack {
                Color.black.cornerRadius(18)
                
                VideoDisplayView(displayLayer: videoPipeline.displayLayer)
                    .cornerRadius(18)
                
                if !videoPipeline.isStreamActive {
                    VStack(spacing: 12) {
                        Image(systemName: "display.trianglebadge.exclamationmark")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("Ready to Mirror")
                            .font(.headline)
                        Text("Start screen sharing from your phone or companion device to stream to this Mac.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .padding(.top, 8)
    }
    
    // MARK: - File Share & Guest Web Portal View
    
    private var fileSharePortalView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Dropzone
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            isTargetedForDrop ? Color.accentColor : Color.white.opacity(0.2),
                            style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                        )
                        .background(isTargetedForDrop ? Color.accentColor.opacity(0.1) : Color.black.opacity(0.25))
                    
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 28))
                            .foregroundColor(isTargetedForDrop ? .accentColor : .secondary)
                        Text("Drop files here to beam to \(connectedDeviceName)")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Also staged for guest mobile download")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(20)
                }
                .frame(height: 120)
                .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
                    handleDroppedFiles(providers)
                    return true
                }
                
                // Guest Web Connect Box
                HStack(alignment: .center, spacing: 20) {
                    if let qr = webServer.qrCodeImage {
                        Image(nsImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 130, height: 130)
                            .padding(8)
                            .background(Color.white)
                            .cornerRadius(12)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Guest Web Fallback")
                            .font(.headline)
                        Text("Scan this QR code with any iPhone, Android, or PC camera to upload files or download files from your Mac.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text(webServer.serverURLString)
                                .font(.system(size: 11, design: .monospaced))
                            
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(webServer.serverURLString, forType: .string)
                            }) {
                                Image(systemName: "doc.on.doc")
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
                        .padding(6)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(6)
                    }
                }
                .padding(16)
                .background(Color.black.opacity(0.3))
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
                
                // Active / Recent Transfers
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent Transfers (\(networkManager.activeTransfers.count))")
                        .font(.headline)
                    
                    if networkManager.activeTransfers.isEmpty {
                        Text("No transfers recorded yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(networkManager.activeTransfers) { transfer in
                            HStack {
                                Image(systemName: transfer.isOutbound ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                    .foregroundColor(transfer.isOutbound ? .blue : .green)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(transfer.fileName)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("\(transfer.isOutbound ? "Sent to" : "Received from") \(transfer.targetDeviceName)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if transfer.isCompleted {
                                    Text("✓ Complete")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.green)
                                } else {
                                    Text(transfer.formattedSpeed)
                                        .font(.system(size: 10, design: .monospaced))
                                }
                            }
                            .padding(10)
                            .background(Color.black.opacity(0.25))
                            .cornerRadius(10)
                        }
                    }
                }
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - Settings Portal View
    
    private var settingsPortalView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings & Continuity")
                    .font(.title3)
                    .fontWeight(.bold)
                
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Universal Clipboard Sync", isOn: $continuity.isClipboardSyncEnabled)
                    Toggle("Notification Relay Receiver", isOn: $continuity.isNotificationRelayEnabled)
                    Toggle("Media Control Bridge", isOn: $continuity.isMediaBridgeEnabled)
                }
                .padding(16)
                .background(Color.black.opacity(0.3))
                .cornerRadius(14)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Received Folder Path")
                        .font(.headline)
                    HStack {
                        Text(networkManager.receivedFolderURL.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("Open") {
                            NSWorkspace.shared.open(networkManager.receivedFolderURL)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(16)
                .background(Color.black.opacity(0.3))
                .cornerRadius(14)
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - Clipboard Quick Sheet
    
    private var clipboardSyncSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Universal Clipboard", systemImage: "doc.on.clipboard")
                    .font(.headline)
                Spacer()
                Button("Done") { showClipboardSheet = false }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            
            if !continuity.latestClipboardSnippet.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Latest Synced Text:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(continuity.latestClipboardSnippet)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(10)
                    
                    Button("Copy to Mac Clipboard") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(continuity.latestClipboardSnippet, forType: .string)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } else {
                Text("No text synced yet. Copy text on your phone to see it appear here!")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(width: 420, height: 260)
    }
    
    // MARK: - Drop Handling
    
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

// Model conformance for ForEach
extension NotificationRelayPayload: Identifiable {
    public var id: String { notificationId }
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
