import SwiftUI
import AppKit

@main
struct HouseholdCommandCenterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = DemoHouseholdStore()

    var body: some Scene {
        WindowGroup {
            HouseholdRootView(store: store)
                .frame(minWidth: 390, idealWidth: 430, minHeight: 720, idealHeight: 844)
        }
        .commands {
            CommandMenu("Household") {
                Button("Discover Gmail Emails") {
                    Task { await store.importGmailLabel() }
                }
                .keyboardShortcut("i", modifiers: [.command])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
