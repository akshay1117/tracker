import AppKit
import SwiftUI
import Combine

/// Manages the macOS menu bar NSStatusItem, dynamic title/icon updates, and popover presentation.
@MainActor
public final class StatusBarController: NSObject, NSPopoverDelegate {
    private let appState: AppState
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()
    
    public init(appState: AppState) {
        self.appState = appState
        super.init()
        setupStatusItem()
        setupPopover()
        observeAppState()
    }
    
    private func setupStatusItem() {
        // Use unique autosave name explicitly whitelisted and disallow accidental removal
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "com.macpulse.status.active"
        statusItem.behavior = [] // Explicitly disallow removal so Command-drag cannot accidentally remove it
        statusItem.isVisible = true
        
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "MacPulse — Power & Wi-Fi Usage Tracker"
            updateStatusItemDisplay()
            print("MacPulse: Status item created successfully. Button frame: \(button.frame)")
        }
    }
    
    public func recreateStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        setupStatusItem()
    }
    
    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 640, height: 780)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverView(appState: appState))
    }
    
    private func observeAppState() {
        // Observe showInMenuBar toggle
        appState.$showInMenuBar
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemDisplay()
            }
            .store(in: &cancellables)
            
        // Observe status item title changes
        appState.$statusItemTitle
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemDisplay()
            }
            .store(in: &cancellables)
            
        appState.$menuBarMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemDisplay()
            }
            .store(in: &cancellables)
    }
    
    public func updateStatusItemDisplay() {
        guard let item = statusItem, let button = item.button else { return }
        
        guard appState.showInMenuBar else {
            item.isVisible = false
            return
        }
        item.isVisible = true
        
        // Crisp SF Symbol bolt template
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let icon = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "MacPulse")?.withSymbolConfiguration(config)
        icon?.isTemplate = true
        button.image = icon
        
        let title = appState.statusItemTitle
        if title.isEmpty || appState.menuBarMode == .iconOnly {
            item.length = NSStatusItem.squareLength
            button.imagePosition = .imageOnly
            button.title = ""
        } else {
            item.length = NSStatusItem.variableLength
            button.imagePosition = .imageLeft
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.title = " " + title
        }
        
        button.needsDisplay = true
    }
    
    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || (event?.modifierFlags.contains(.control) ?? false) {
            showContextMenu(sender)
        } else {
            togglePopover(sender)
        }
    }
    
    public func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            appState.isPopoverOpen = false
        } else {
            // Activate the app to ensure popover receives key focus
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            appState.isPopoverOpen = true
            appState.performTick() // Immediate fresh sample on open
        }
    }
    
    private func showContextMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open MacPulse", action: #selector(openPopoverFromMenu), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)
        
        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshMetrics), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit MacPulse", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        // Pop up contextual menu cleanly without modifying statusItem.menu
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }
    
    @objc private func openPopoverFromMenu() {
        if let button = statusItem.button {
            togglePopover(button)
        }
    }
    
    @objc private func refreshMetrics() {
        appState.performTick()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - NSPopoverDelegate
    
    public func popoverDidClose(_ notification: Notification) {
        appState.isPopoverOpen = false
    }
}
