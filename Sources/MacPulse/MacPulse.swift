import AppKit
import SwiftUI

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
        
        // Show main dashboard window on launch so the user immediately gets the UI
        mainWindowController.showWindow()
        
        print("MacPulse: Initialized successfully.")
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindowController?.showWindow()
        return true
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
