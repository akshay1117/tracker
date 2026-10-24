import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState!
    var statusBarController: StatusBarController!
    var mainWindowController: MainWindowController!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent AppKit automatic termination for background monitoring
        ProcessInfo.processInfo.disableAutomaticTermination("MacPulse menu bar tracking")
        
        let state = AppState()
        self.appState = state
        self.statusBarController = StatusBarController(appState: state)
        self.mainWindowController = MainWindowController(appState: state)
        
        state.onResetMenuBar = { [weak self] in
            self?.statusBarController?.recreateStatusItem()
        }
        
        state.onVerifyMenuBar = { [weak self] in
            self?.statusBarController?.ensureStatusItemVisible()
        }
        
        setupMainMenu()
        
        // Show main dashboard window on launch so the user immediately gets the UI
        mainWindowController.showWindow()
        
        print("MacPulse: Initialized successfully.")
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // When user clicks the app icon in Finder/Dock/Spotlight, ensure menu bar icon is restored
        statusBarController?.ensureStatusItemVisible()
        mainWindowController?.showWindow()
        return true
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        // Ensure menu bar icon is healthy whenever app gains focus
        statusBarController?.ensureStatusItemVisible()
    }
    
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        
        let openItem = NSMenuItem(title: "Open Dashboard", action: #selector(handleOpenDashboardFromDock), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        
        let restoreItem = NSMenuItem(title: "Restore Menu Bar Icon", action: #selector(handleRestoreMenuBarFromDock), keyEquivalent: "")
        restoreItem.target = self
        menu.addItem(restoreItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let refreshItem = NSMenuItem(title: "Refresh Metrics", action: #selector(handleRefreshFromDock), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        return menu
    }
    
    @objc private func handleOpenDashboardFromDock() {
        mainWindowController?.showWindow()
    }
    
    @objc private func handleRestoreMenuBarFromDock() {
        appState?.resetMenuBarPosition()
        statusBarController?.ensureStatusItemVisible()
    }
    
    @objc private func handleRefreshFromDock() {
        appState?.performTick()
    }
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // Application Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About MacPulse", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide MacPulse", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit MacPulse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // View Menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        
        let showDash = NSMenuItem(title: "Open Dashboard", action: #selector(handleOpenDashboardFromDock), keyEquivalent: "0")
        showDash.target = self
        viewMenu.addItem(showDash)
        
        let restoreBar = NSMenuItem(title: "Restore Menu Bar Icon", action: #selector(handleRestoreMenuBarFromDock), keyEquivalent: "m")
        restoreBar.keyEquivalentModifierMask = [.command, .option]
        restoreBar.target = self
        viewMenu.addItem(restoreBar)
        
        let refresh = NSMenuItem(title: "Refresh Metrics Now", action: #selector(handleRefreshFromDock), keyEquivalent: "r")
        refresh.target = self
        viewMenu.addItem(refresh)
        
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)
        
        // Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        windowMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        
        NSApp.mainMenu = mainMenu
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Allow the app to remain running in the background/menu bar when dashboard window is closed
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        appState?.sessionManager.handleWillTerminate()
        print("MacPulse: Terminated gracefully.")
    }
}

@main
@MainActor
struct MacPulseMain {
    // Strongly retain the delegate on MainActor for the lifetime of the process
    private static var appDelegate: AppDelegate?
    
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        self.appDelegate = delegate
        app.delegate = delegate
        
        ProcessInfo.processInfo.disableAutomaticTermination("MacPulse menu bar tracking")
        
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
