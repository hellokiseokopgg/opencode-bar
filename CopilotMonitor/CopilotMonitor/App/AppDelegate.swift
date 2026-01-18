import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var loginWindow: NSWindow?
    var statusBarController: StatusBarController!
    private var sessionExpiredObserver: NSObjectProtocol?
    private var billingLoadedObserver: NSObjectProtocol?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        sessionExpiredObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("sessionExpired"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showLoginWindow()
        }
        
        billingLoadedObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("billingPageLoaded"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hideLoginWindow()
        }
    }
    
    func showLoginWindow() {
        if let window = loginWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "GitHub 로그인"
        window.center()
        window.contentView = NSHostingView(rootView: LoginView(webView: AuthManager.shared.webView))
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        loginWindow = window
        AuthManager.shared.loadLoginPage()
    }
    
    func hideLoginWindow() {
        loginWindow?.orderOut(nil)
    }
    
    deinit {
        if let observer = sessionExpiredObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = billingLoadedObserver { NotificationCenter.default.removeObserver(observer) }
    }
}
