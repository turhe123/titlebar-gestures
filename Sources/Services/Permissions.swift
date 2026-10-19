import ApplicationServices
import AppKit
import CoreGraphics

/// Checks and requests the Accessibility and Input Monitoring privileges the app relies on.
enum Permissions {
    static var hasAccessibility: Bool { AXIsProcessTrusted() }
    static var hasInputMonitoring: Bool { CGPreflightListenEventAccess() }
    static var allGranted: Bool { hasAccessibility && hasInputMonitoring }

    /// Shows the system Accessibility prompt and opens the matching Settings pane.
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            openPane("Privacy_Accessibility")
        }
    }

    /// Requests Input Monitoring access, falling back to the Settings pane if already denied.
    static func requestInputMonitoring() {
        if !CGRequestListenEventAccess() {
            openPane("Privacy_ListenEvent")
        }
    }

    private static func openPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
