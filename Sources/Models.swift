import CoreGraphics
import Foundation

/// A gesture the app recognises while the pointer is over a title bar.
enum Gesture: String, CaseIterable, Identifiable {
    case swipeLeft, swipeRight, swipeUp, swipeDown, pinchIn, pinchOut, middleClick

    var id: String { rawValue }

    var title: String {
        switch self {
        case .swipeLeft: return "Swipe Left"
        case .swipeRight: return "Swipe Right"
        case .swipeUp: return "Swipe Up"
        case .swipeDown: return "Swipe Down"
        case .pinchIn: return "Pinch In"
        case .pinchOut: return "Pinch Out"
        case .middleClick: return "Middle Click"
        }
    }

    var symbol: String {
        switch self {
        case .swipeLeft: return "arrow.left"
        case .swipeRight: return "arrow.right"
        case .swipeUp: return "arrow.up"
        case .swipeDown: return "arrow.down"
        case .pinchIn: return "arrow.down.right.and.arrow.up.left"
        case .pinchOut: return "arrow.up.left.and.arrow.down.right"
        case .middleClick: return "computermouse"
        }
    }

    /// UserDefaults key holding the mapped action's raw value.
    var storageKey: String { "map.\(rawValue)" }

    var defaultAction: WindowAction {
        switch self {
        case .swipeLeft: return .leftHalf
        case .swipeRight: return .rightHalf
        case .swipeUp: return .maximize
        case .swipeDown: return .restore
        case .pinchIn: return .minimize
        case .pinchOut: return .none
        case .middleClick: return .close
        }
    }
}

/// An operation that can be performed on a window.
enum WindowAction: String, CaseIterable, Identifiable {
    case none, leftHalf, rightHalf, maximize, restore, center, minimize, close, nextDisplay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .maximize: return "Maximize"
        case .restore: return "Restore"
        case .center: return "Center"
        case .minimize: return "Minimize"
        case .close: return "Close"
        case .nextDisplay: return "Next Display"
        }
    }
}

/// A modifier key that must be held for gestures to be intercepted.
enum ModifierRequirement: String, CaseIterable, Identifiable {
    case none, option, command, control, shift

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .option: return "⌥ Option"
        case .command: return "⌘ Command"
        case .control: return "⌃ Control"
        case .shift: return "⇧ Shift"
        }
    }

    var flag: CGEventFlags? {
        switch self {
        case .none: return nil
        case .option: return .maskAlternate
        case .command: return .maskCommand
        case .control: return .maskControl
        case .shift: return .maskShift
        }
    }

    /// Whether the given event flags satisfy this requirement.
    func isSatisfied(by flags: CGEventFlags) -> Bool {
        guard let flag else { return true }
        return flags.contains(flag)
    }
}

/// Central list of persisted setting keys and typed accessors used outside SwiftUI.
enum Prefs {
    static let enabled = "enabled"
    static let modifier = "requiredModifier"
    static let sensitivity = "sensitivity"
    static let titleBarHeight = "titleBarHeight"
    static let showFeedback = "showFeedback"
    static let closeNeedsModifier = "closeNeedsModifier"

    static func registerDefaults() {
        var defaults: [String: Any] = [
            enabled: true,
            modifier: ModifierRequirement.none.rawValue,
            sensitivity: 0.5,
            titleBarHeight: 28.0,
            showFeedback: true,
            closeNeedsModifier: true,
        ]
        for gesture in Gesture.allCases {
            defaults[gesture.storageKey] = gesture.defaultAction.rawValue
        }
        UserDefaults.standard.register(defaults: defaults)
    }

    private static var store: UserDefaults { .standard }

    static var isEnabled: Bool { store.bool(forKey: enabled) }
    static var showsFeedback: Bool { store.bool(forKey: showFeedback) }
    static var closeRequiresModifier: Bool { store.bool(forKey: closeNeedsModifier) }
    static var bandHeight: CGFloat { CGFloat(max(10, min(80, store.double(forKey: titleBarHeight)))) }

    static var requiredModifier: ModifierRequirement {
        ModifierRequirement(rawValue: store.string(forKey: modifier) ?? "") ?? .none
    }

    /// 0 (least sensitive) … 1 (most sensitive).
    static var sensitivityValue: Double { max(0, min(1, store.double(forKey: sensitivity))) }

    /// Accumulated scroll distance (points) needed to fire a swipe.
    static var swipeThreshold: CGFloat { CGFloat(30 + (1 - sensitivityValue) * 170) }

    /// Accumulated magnification needed to fire a pinch.
    static var pinchThreshold: CGFloat { CGFloat(0.08 + (1 - sensitivityValue) * 0.32) }

    static func action(for gesture: Gesture) -> WindowAction {
        WindowAction(rawValue: store.string(forKey: gesture.storageKey) ?? "") ?? gesture.defaultAction
    }
}
