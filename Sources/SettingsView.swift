import SwiftUI

/// The Settings window: permissions banner, gesture-to-action mappings and safeguards.
struct SettingsView: View {
    @AppStorage(Prefs.modifier) private var modifier = ModifierRequirement.none.rawValue
    @AppStorage(Prefs.sensitivity) private var sensitivity = 0.5
    @AppStorage(Prefs.titleBarHeight) private var titleBarHeight = 28.0
    @AppStorage(Prefs.showFeedback) private var showFeedback = true
    @AppStorage(Prefs.closeNeedsModifier) private var closeNeedsModifier = true

    @State private var hasAccessibility = Permissions.hasAccessibility
    @State private var hasInputMonitoring = Permissions.hasInputMonitoring
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?

    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !hasAccessibility || !hasInputMonitoring {
                PermissionBanner(hasAccessibility: hasAccessibility, hasInputMonitoring: hasInputMonitoring)
            }
            Form {
                Section("Gestures over the title bar") {
                    ForEach(Gesture.allCases) { gesture in
                        GestureRow(gesture: gesture)
                    }
                }
                Section("Safeguards") {
                    Picker("Required modifier", selection: $modifier) {
                        ForEach(ModifierRequirement.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Toggle("Close requires a modifier (⌥ if none selected)", isOn: $closeNeedsModifier)
                    LabeledContent("Sensitivity") {
                        Slider(value: $sensitivity, in: 0...1) {
                            EmptyView()
                        } minimumValueLabel: { Text("Low") } maximumValueLabel: { Text("High") }
                    }
                    Stepper(value: $titleBarHeight, in: 16...64, step: 2) {
                        LabeledContent("Title bar height", value: "\(Int(titleBarHeight)) pt")
                    }
                }
                Section("General") {
                    Toggle("Show on-screen feedback", isOn: $showFeedback)
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, newValue in
                            guard newValue != LaunchAtLogin.isEnabled else { return }
                            loginError = LaunchAtLogin.set(newValue)
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    if let loginError {
                        Text(loginError).font(.caption).foregroundStyle(.red)
                    }
                }
                Section {
                    HStack {
                        Text("TitlebarGestures is free and open source.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Support / Donate ❤️") { Links.openDonation() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 480, height: 640)
        .onReceive(refresh) { _ in
            hasAccessibility = Permissions.hasAccessibility
            hasInputMonitoring = Permissions.hasInputMonitoring
        }
    }
}

/// One gesture → action picker row, persisted under the gesture's storage key.
private struct GestureRow: View {
    let gesture: Gesture
    @AppStorage private var action: String

    init(gesture: Gesture) {
        self.gesture = gesture
        _action = AppStorage(wrappedValue: gesture.defaultAction.rawValue, gesture.storageKey)
    }

    var body: some View {
        Picker(selection: $action) {
            ForEach(WindowAction.allCases) { Text($0.title).tag($0.rawValue) }
        } label: {
            Label(gesture.title, systemImage: gesture.symbol)
        }
    }
}

/// Banner shown when Accessibility or Input Monitoring permission is missing.
private struct PermissionBanner: View {
    let hasAccessibility: Bool
    let hasInputMonitoring: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Permissions needed", systemImage: "lock.shield")
                .font(.headline)
            Text("TitlebarGestures needs Accessibility to move windows and Input Monitoring to read trackpad gestures. After granting, gestures start automatically within a few seconds.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(hasAccessibility ? "Accessibility ✓" : "Grant Accessibility") {
                    Permissions.requestAccessibility()
                }
                .disabled(hasAccessibility)
                Button(hasInputMonitoring ? "Input Monitoring ✓" : "Grant Input Monitoring") {
                    Permissions.requestInputMonitoring()
                }
                .disabled(hasInputMonitoring)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.15))
    }
}
