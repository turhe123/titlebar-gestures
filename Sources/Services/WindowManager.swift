import AppKit
import ApplicationServices

/// Finds windows under the pointer via the Accessibility API and performs window actions on them.
final class WindowManager {
    static let shared = WindowManager()

    private let systemWide = AXUIElementCreateSystemWide()
    /// Frame each window had before we last moved it, used by `.restore`.
    private var savedFrames: [AXUIElement: CGRect] = [:]

    /// Roles of controls that live inside the title bar area and must keep their own gestures.
    private let blockedRoles: Set<String> = [
        kAXButtonRole, kAXTextFieldRole, kAXRadioButtonRole, kAXCheckBoxRole,
        kAXPopUpButtonRole, kAXMenuButtonRole, kAXComboBoxRole, kAXSliderRole,
        kAXTextAreaRole, kAXTabGroupRole, kAXIncrementorRole, "AXSegmentedControl", "AXSearchField",
    ]

    /// Returns the window whose title-bar band contains `point` (global, top-left origin), if any.
    func titleBarWindow(at point: CGPoint, bandHeight: CGFloat) -> AXUIElement? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success,
              let element = hit else { return nil }

        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        if pid == ProcessInfo.processInfo.processIdentifier { return nil }

        if let role = string(element, kAXRoleAttribute), blockedRoles.contains(role) { return nil }
        if let subrole = string(element, kAXSubroleAttribute), subrole == "AXSearchField" || subrole == "AXTabButton" {
            return nil
        }

        guard let window = enclosingWindow(of: element) else { return nil }
        if bool(window, "AXFullScreen") == true { return nil }
        guard let frame = frame(of: window) else { return nil }

        let offset = point.y - frame.minY
        guard offset >= 0, offset <= bandHeight, point.x >= frame.minX, point.x <= frame.maxX else { return nil }
        return window
    }

    /// Performs `action` on `window`. Returns `false` if the action could not be applied.
    @discardableResult
    func perform(_ action: WindowAction, on window: AXUIElement) -> Bool {
        switch action {
        case .none:
            return false
        case .minimize:
            if AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success {
                return true
            }
            return press(window, button: kAXMinimizeButtonAttribute)
        case .close:
            savedFrames[window] = nil
            return press(window, button: kAXCloseButtonAttribute)
        case .restore:
            guard let previous = savedFrames.removeValue(forKey: window) else { return false }
            return setFrame(previous, of: window)
        case .leftHalf, .rightHalf, .maximize, .center, .nextDisplay:
            guard let current = frame(of: window), let target = targetFrame(for: action, current: current) else {
                return false
            }
            if savedFrames[window] == nil || action != .nextDisplay { savedFrames[window] = current }
            return setFrame(target, of: window)
        }
    }

    // MARK: - Geometry

    private func targetFrame(for action: WindowAction, current: CGRect) -> CGRect? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let center = CGPoint(x: current.midX, y: current.midY)
        let index = screens.firstIndex { axRect($0.frame).contains(center) } ?? 0
        let area = axRect(screens[index].visibleFrame)

        switch action {
        case .leftHalf:
            return CGRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height)
        case .rightHalf:
            return CGRect(x: area.midX, y: area.minY, width: area.width / 2, height: area.height)
        case .maximize:
            return area
        case .center:
            let size = CGSize(width: min(current.width, area.width), height: min(current.height, area.height))
            return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                          width: size.width, height: size.height)
        case .nextDisplay:
            guard screens.count > 1 else { return nil }
            let next = axRect(screens[(index + 1) % screens.count].visibleFrame)
            let relX = (current.minX - area.minX) / max(area.width, 1)
            let relY = (current.minY - area.minY) / max(area.height, 1)
            let size = CGSize(width: min(current.width, next.width), height: min(current.height, next.height))
            let x = min(next.minX + relX * next.width, next.maxX - size.width)
            let y = min(next.minY + relY * next.height, next.maxY - size.height)
            return CGRect(x: x, y: y, width: size.width, height: size.height)
        default:
            return nil
        }
    }

    /// Converts an AppKit (bottom-left origin) rect to Accessibility (top-left origin) coordinates.
    private func axRect(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? rect.maxY
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: - AX helpers

    private func enclosingWindow(of element: AXUIElement) -> AXUIElement? {
        if string(element, kAXRoleAttribute) == kAXWindowRole { return element }
        if let window: AXUIElement = value(element, kAXWindowAttribute) { return window }
        var current = element
        for _ in 0..<20 {
            guard let parent: AXUIElement = value(current, kAXParentAttribute) else { return nil }
            if string(parent, kAXRoleAttribute) == kAXWindowRole { return parent }
            current = parent
        }
        return nil
    }

    func frame(of window: AXUIElement) -> CGRect? {
        guard let posValue: AXValue = value(window, kAXPositionAttribute),
              let sizeValue: AXValue = value(window, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posValue, .cgPoint, &origin), AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private func setFrame(_ rect: CGRect, of window: AXUIElement) -> Bool {
        var origin = rect.origin
        var size = rect.size
        guard let pos = AXValueCreate(.cgPoint, &origin), let sz = AXValueCreate(.cgSize, &size) else { return false }
        // Position, size, position again: some apps clamp size against the old position.
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pos)
        let sized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sz)
        let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pos)
        return sized == .success || moved == .success
    }

    private func press(_ window: AXUIElement, button attribute: String) -> Bool {
        guard let button: AXUIElement = value(window, attribute) else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    private func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success, let raw else { return nil }
        // CF types cannot be conditionally cast, so verify the type ID first.
        if T.self == AXUIElement.self, CFGetTypeID(raw) != AXUIElementGetTypeID() { return nil }
        if T.self == AXValue.self, CFGetTypeID(raw) != AXValueGetTypeID() { return nil }
        return raw as? T
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as String?
    }

    private func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        (value(element, attribute) as NSNumber?)?.boolValue
    }
}
