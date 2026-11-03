import SwiftUI
import AppKit

@main
struct WaypointApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup("Waypoint") {
            MainWindowView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .newItem) {
                Button("Open Downloads Folder") {
                    NSWorkspace.shared.open(P2PNetworkManager.shared.receivedFolderURL)
                }
                .keyboardShortcut("O", modifiers: [.command])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a regular macOS desktop application with Dock icon and main window
        NSApp.setActivationPolicy(.regular)
        
        setupPopover()
        setupStatusItem()
        setupGlobalClickMonitor()
        
        // Eagerly initialize core network managers
        _ = P2PNetworkManager.shared
        _ = ContinuityManager.shared
        _ = LocalWebServer.shared
        _ = VideoStreamingPipeline.shared
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                if window.canBecomeMain {
                    window.makeKeyAndOrderFront(nil)
                    return true
                }
            }
        }
        return true
    }
    
    // MARK: - Status Item Setup
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            let image = NSImage(
                systemSymbolName: "point.3.filled.connected.trianglepath.dotted",
                accessibilityDescription: "Waypoint Local Bridge"
            )?.withSymbolConfiguration(symbolConfig)
            
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(togglePopover)
            button.toolTip = "Waypoint — Local-First Ecosystem Bridge"
        }
    }
    
    // MARK: - Popover Setup
    
    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 500)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PopoverView())
        self.popover = popover
    }
    
    // MARK: - Popover Presentation & Event Handling
    
    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        
        if popover.isShown {
            closePopover()
        } else {
            showPopover(button: button)
        }
    }
    
    private func showPopover(button: NSStatusBarButton) {
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    
    private func closePopover() {
        popover.performClose(nil)
    }
    
    private func setupGlobalClickMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, self.popover.isShown else { return }
            self.closePopover()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        LocalWebServer.shared.stop()
    }
}
