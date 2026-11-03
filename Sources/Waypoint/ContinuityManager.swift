import Foundation
import AppKit
import UserNotifications
import Combine

/// ContinuityManager powers Universal Clipboard Sync, the Notification Relay Receiver,
/// and the Media Control Bridge.
@MainActor
public final class ContinuityManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    public static let shared = ContinuityManager()
    
    // MARK: - State
    @Published public var isClipboardSyncEnabled: Bool = true
    @Published public var isNotificationRelayEnabled: Bool = true
    @Published public var isMediaBridgeEnabled: Bool = true
    
    @Published public private(set) var latestClipboardSnippet: String = ""
    @Published public private(set) var latestNotification: NotificationRelayPayload?
    @Published public private(set) var currentMediaMetadata: MediaMetadataPayload?
    
    // Deduplication tracking
    private var lastObservedChangeCount: Int = 0
    private var lastReceivedHash: Int = 0
    private var clipboardTimer: Timer?
    
    public override init() {
        self.lastObservedChangeCount = NSPasteboard.general.changeCount
        super.init()
        setupNotificationRelay()
        setupClipboardWatcher()
        bindP2PCallbacks()
    }
    
    // MARK: - P2P Network Wiring
    
    private func bindP2PCallbacks() {
        let p2p = P2PNetworkManager.shared
        
        p2p.onClipboardReceived = { [weak self] payload in
            Task { @MainActor in
                self?.handleIncomingClipboard(payload)
            }
        }
        
        p2p.onNotificationReceived = { [weak self] payload in
            Task { @MainActor in
                self?.handleIncomingNotification(payload)
            }
        }
        
        p2p.onMediaMetadataReceived = { [weak self] payload in
            Task { @MainActor in
                self?.currentMediaMetadata = payload
            }
        }
        
        p2p.onMediaCommandReceived = { [weak self] payload in
            Task { @MainActor in
                self?.handleIncomingMediaCommand(payload)
            }
        }
    }
    
    // MARK: - Universal Clipboard Sync Engine
    
    private func setupClipboardWatcher() {
        // Poll NSPasteboard changeCount every 500ms
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkLocalClipboardChange()
            }
        }
    }
    
    private func checkLocalClipboardChange() {
        guard isClipboardSyncEnabled else { return }
        
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastObservedChangeCount else { return }
        lastObservedChangeCount = pasteboard.changeCount
        
        guard let stringValue = pasteboard.string(forType: .string), !stringValue.isEmpty else {
            return
        }
        
        // Suppress echo if this matches what we just received externally
        let stringHash = stringValue.hashValue
        if stringHash == lastReceivedHash {
            return
        }
        
        self.latestClipboardSnippet = stringValue
        // Broadcast over local network to all connected peers
        P2PNetworkManager.shared.broadcastClipboard(text: stringValue)
    }
    
    public func updateClipboardFromExternal(_ text: String) {
        guard isClipboardSyncEnabled, !text.isEmpty else { return }
        
        self.lastReceivedHash = text.hashValue
        self.latestClipboardSnippet = text
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        self.lastObservedChangeCount = pasteboard.changeCount
    }
    
    private func handleIncomingClipboard(_ payload: ClipboardSyncPayload) {
        updateClipboardFromExternal(payload.text)
    }
    
    // MARK: - Notification Relay Receiver
    
    private func setupNotificationRelay() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[Waypoint Notifications] Auth error: \(error)")
            }
        }
    }
    
    private func handleIncomingNotification(_ payload: NotificationRelayPayload) {
        guard isNotificationRelayEnabled else { return }
        self.latestNotification = payload
        
        let content = UNMutableNotificationContent()
        content.title = "\(payload.appName)"
        content.subtitle = payload.title
        content.body = payload.text
        content.sound = UNNotificationSound.default
        content.userInfo = [
            "id": payload.notificationId,
            "package": payload.packageName
        ]
        
        // Setup action categories if notification includes quick actions
        if !payload.actions.isEmpty {
            let actions: [UNNotificationAction] = payload.actions.map { action in
                if action.isReply {
                    return UNTextInputNotificationAction(
                        identifier: action.actionId,
                        title: action.title,
                        options: [],
                        textInputButtonTitle: "Send",
                        textInputPlaceholder: "Reply..."
                    )
                } else {
                    return UNNotificationAction(
                        identifier: action.actionId,
                        title: action.title,
                        options: []
                    )
                }
            }
            
            let categoryId = "CATEGORY_\(payload.packageName)"
            let category = UNNotificationCategory(identifier: categoryId, actions: actions, intentIdentifiers: [], options: [])
            UNUserNotificationCenter.current().setNotificationCategories([category])
            content.categoryIdentifier = categoryId
        }
        
        let request = UNNotificationRequest(
            identifier: "waypoint_\(payload.notificationId)",
            content: content,
            trigger: nil // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[Waypoint Notifications] Delivery failed: \(error)")
            }
        }
    }
    
    // UNUserNotificationCenterDelegate: Display banner even if app is foreground
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
    
    // MARK: - Media Control Bridge
    
    private func handleIncomingMediaCommand(_ command: MediaCommandPayload) {
        guard isMediaBridgeEnabled else { return }
        
        switch command.command {
        case .play:
            executeMediaScript("tell application \"Music\" to play")
        case .pause:
            executeMediaScript("tell application \"Music\" to pause")
        case .playPauseToggle:
            executeMediaScript("tell application \"Music\" to playpause")
        case .nextTrack:
            executeMediaScript("tell application \"Music\" to next track")
        case .previousTrack:
            executeMediaScript("tell application \"Music\" to previous track")
        case .volumeUp:
            executeMediaScript("set volume output volume ((output volume of (get volume settings)) + 6)")
        case .volumeDown:
            executeMediaScript("set volume output volume ((output volume of (get volume settings)) - 6)")
        case .seek:
            if let pos = command.seekPositionSeconds {
                executeMediaScript("tell application \"Music\" to set player position to \(pos)")
            }
        }
    }
    
    public func sendRemoteMediaCommand(_ type: MediaControlCommandType) {
        P2PNetworkManager.shared.sendMediaCommand(type)
    }
    
    private func executeMediaScript(_ source: String) {
        DispatchQueue.global(qos: .userInteractive).async {
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: source) {
                scriptObject.executeAndReturnError(&error)
                if let error = error {
                    print("[Waypoint Media] Script error: \(error)")
                }
            }
        }
    }
}
