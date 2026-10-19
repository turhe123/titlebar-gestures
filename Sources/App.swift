import AppKit
import ServiceManagement
import SwiftUI

/// Entry point: a menu-bar-only app with a Settings window.
@main
struct TitlebarGesturesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("TitlebarGestures", systemImage: "hand.raised.fill") {
            MenuContent()
        }
        Window("TitlebarGestures Settings", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
    }
}

/// Registers defaults and starts the gesture monitor at launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        GestureMonitor.shared.start()
    }
}

/// Items shown in the menu bar extra's menu.
struct MenuContent: View {
    @AppStorage(Prefs.enabled) private var enabled = true
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("Enabled", isOn: $enabled)
        Divider()
        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
        Button("Support / Donate ❤️") { Links.openDonation() }
        Divider()
        Button("Quit TitlebarGestures") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// External links opened by the app.
enum Links {
    static func openDonation() {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
    }
}

/// Wraps `SMAppService` registration of the main app as a login item.
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns an error message on failure, `nil` on success.
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
