import AppKit
import SwiftUI

/// Manages the primary dashboard window for MacPulse, featuring a spacious precision interface.
@MainActor
public final class MainWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let appState: AppState
    
    public init(appState: AppState) {
        self.appState = appState
        super.init()
    }
    
    public func showWindow() {
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 900),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.center()
            win.minSize = NSSize(width: 720, height: 780)
            win.title = "MacPulse — Power & Wi-Fi Tracker"
            win.titleVisibility = .hidden
            win.titlebarAppearsTransparent = true
            win.backgroundColor = NSColor(red: 0.015, green: 0.018, blue: 0.024, alpha: 1.0)
            win.appearance = NSAppearance(named: .darkAqua)
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.tabbingMode = .disallowed
            
            // Embed PopoverView as root view
            win.contentViewController = NSHostingController(rootView: PopoverView(appState: appState))
            self.window = win
        }
        
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        appState.isWindowOpen = true
        appState.performTick()
    }
    
    public func toggleWindow() {
        if let win = window, win.isVisible {
            win.orderOut(nil)
            appState.isWindowOpen = false
        } else {
            showWindow()
        }
    }
    
    // MARK: - NSWindowDelegate
    
    public func windowWillClose(_ notification: Notification) {
        // App stays running in background when window is closed
        appState.isWindowOpen = false
    }
}
