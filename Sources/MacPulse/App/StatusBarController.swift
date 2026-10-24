import AppKit
import SwiftUI
import Combine

/// Manages the macOS menu bar NSStatusItem, dynamic title/icon updates, and popover presentation.
@MainActor
public final class StatusBarController: NSObject, NSPopoverDelegate {
    private let appState: AppState
    private var statusItem: NSStatusItem?
    private var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()
    private var visibilityObservation: NSKeyValueObservation?
    private var isProgrammaticHiding = false
    private var isRestoring = false
    private var restorationWorkItem: DispatchWorkItem?
    
    public init(appState: AppState) {
        self.appState = appState
        super.init()
        setupStatusItem()
        setupPopover()
        observeAppState()
    }
    
    private func setupStatusItem() {
        guard statusItem == nil else {
            updateStatusItemDisplay()
            return
        }
        
        // Clear any previous autosaved hidden state that macOS may have persisted in preferences
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Visible com.macpulse.status.active")
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Preferred Position com.macpulse.status.active")
        
        // 1. Create a variable length status item on system status bar
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "com.macpulse.status.active"
        // Explicitly set empty behavior: do NOT allow removal so Command-drag does not intentionally delete it
        item.behavior = []
        item.isVisible = appState.showInMenuBar
        
        // 2. Observe isVisible property via KVO to immediately detect if macOS hides or detaches the item
        visibilityObservation?.invalidate()
        visibilityObservation = item.observe(\.isVisible, options: [.new, .old]) { [weak self] observedItem, change in
            let isVisible = change.newValue ?? observedItem.isVisible
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if !isVisible && self.appState.showInMenuBar && !self.isProgrammaticHiding {
                    print("MacPulse: Status item was unexpectedly hidden by system/drag. Automatically restoring...")
                    self.scheduleRestoration()
                }
            }
        }
        
        self.statusItem = item
        
        if let button = item.button {
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "MacPulse — Power & Wi-Fi Usage Tracker"
            updateStatusItemDisplay()
            print("MacPulse: Status item created successfully. Button frame: \(button.frame)")
        }
    }
    
    /// Fully removes and recreates the status item. Completely idempotent.
    public func recreateStatusItem() {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        
        restorationWorkItem?.cancel()
        restorationWorkItem = nil
        
        visibilityObservation?.invalidate()
        visibilityObservation = nil
        
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            self.statusItem = nil
        }
        
        // Clear any stored hidden preferences
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Visible com.macpulse.status.active")
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Preferred Position com.macpulse.status.active")
        
        setupStatusItem()
    }
    
    /// Debounced restoration helper to prevent rapid recreation cycles.
    private func scheduleRestoration() {
        restorationWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.appState.showInMenuBar else { return }
            self.recreateStatusItem()
        }
        restorationWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
    
    /// Verifies the status item is alive, attached to a window, and visible.
    /// If it was detached or removed, it re-establishes it immediately.
    public func ensureStatusItemVisible() {
        guard appState.showInMenuBar else { return }
        
        let isMissing = statusItem == nil
        let isDisconnected = statusItem?.button?.window == nil
        let isHidden = !(statusItem?.isVisible ?? false)
        
        if isMissing || isDisconnected || isHidden {
            print("MacPulse: ensureStatusItemVisible detected missing/detached item (missing: \(isMissing), disconnected: \(isDisconnected), hidden: \(isHidden)). Restoring...")
            recreateStatusItem()
        } else {
            updateStatusItemDisplay()
        }
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
            .sink { [weak self] show in
                guard let self = self else { return }
                if show {
                    self.ensureStatusItemVisible()
                } else {
                    self.isProgrammaticHiding = true
                    self.statusItem?.isVisible = false
                    self.isProgrammaticHiding = false
                }
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
            isProgrammaticHiding = true
            item.isVisible = false
            isProgrammaticHiding = false
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
        if let button = statusItem?.button {
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
