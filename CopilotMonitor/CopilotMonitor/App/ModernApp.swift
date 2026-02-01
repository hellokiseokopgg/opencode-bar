import SwiftUI

@main
struct ModernApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var isMenuPresented = false
    @State private var isMenuEnabled = false
    
    var body: some Scene {
        MenuBarExtra(isInserted: $isMenuEnabled) {
            Text("Loading...")
        } label: {
            Image(systemName: "gauge.medium")
        }
        .menuBarExtraStyle(.menu)
        
        Settings {
            EmptyView()
        }
    }
}
