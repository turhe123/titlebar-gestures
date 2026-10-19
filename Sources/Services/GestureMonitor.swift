import AppKit
import CoreGraphics

/// Watches scroll, middle-click and magnify events and turns title-bar gestures into window actions.
///
/// Scroll and middle-click events come from an active `CGEventTap` so they can be swallowed;
/// magnification arrives through a listen-only `NSEvent` global monitor.
final class GestureMonitor {
    static let shared = GestureMonitor()

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var magnifyMonitor: Any?
    private var retryTimer: Timer?

    /// State of the scroll gesture currently being tracked over a title bar.
    private struct SwipeSession {
        let window: AXUIElement
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        var fired = false
    }
    private var swipe: SwipeSession?
    /// Momentum events are swallowed until this time after a gesture we consumed.
    private var swallowMomentumUntil = Date.distantPast

    private struct PinchSession {
        let window: AXUIElement
        var total: CGFloat = 0
        var fired = false
    }
    private var pinch: PinchSession?

    var isTapActive: Bool { tap != nil }

    /// Starts monitoring, retrying periodically until permissions allow the tap to be created.
    func start() {
        installTapIfPossible()
        installMagnifyMonitor()
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let tap = self.tap {
                if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            } else {
                self.installTapIfPossible()
            }
        }
    }

    // MARK: - Installation

    private func installTapIfPossible() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let mask = (1 << CGEventType.scrollWheel.rawValue) | (1 << CGEventType.otherMouseDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<GestureMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask), callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        runLoopSource = source
    }

    private func installMagnifyMonitor() {
        guard magnifyMonitor == nil else { return }
        magnifyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .magnify) { [weak self] event in
            self?.handleMagnify(event)
        }
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case .scrollWheel:
            return handleScroll(event) ? nil : pass
        case .otherMouseDown:
            return handleMiddleClick(event) ? nil : pass
        default:
            return pass
        }
    }

    /// Returns `true` when the event was consumed.
    private func handleScroll(_ cgEvent: CGEvent) -> Bool {
        guard let event = NSEvent(cgEvent: cgEvent) else { return false }

        if event.momentumPhase != [] {
            swipe = nil
            return Date() < swallowMomentumUntil
        }
        guard event.hasPreciseScrollingDeltas else { return false }

        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            swipe = nil
            guard Prefs.isEnabled, Prefs.requiredModifier.isSatisfied(by: cgEvent.flags),
                  let window = WindowManager.shared.titleBarWindow(at: cgEvent.location, bandHeight: Prefs.bandHeight)
            else { return false }
            swipe = SwipeSession(window: window)
            return true
        }

        guard var session = swipe else { return false }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            swipe = nil
            swallowMomentumUntil = Date().addingTimeInterval(0.6)
            return true
        }

        // Convert content deltas to finger movement, honouring natural scrolling.
        let inverted = event.isDirectionInvertedFromDevice
        session.dx += inverted ? event.scrollingDeltaX : -event.scrollingDeltaX
        session.dy += inverted ? -event.scrollingDeltaY : event.scrollingDeltaY

        if !session.fired {
            let threshold = Prefs.swipeThreshold
            var gesture: Gesture?
            if abs(session.dx) >= threshold, abs(session.dx) > abs(session.dy) {
                gesture = session.dx > 0 ? .swipeRight : .swipeLeft
            } else if abs(session.dy) >= threshold {
                gesture = session.dy > 0 ? .swipeUp : .swipeDown
            }
            if let gesture {
                session.fired = true // debounce: one action per gesture
                trigger(gesture, window: session.window, flags: cgEvent.flags, at: cgEvent.location)
            }
        }
        swipe = session
        return true
    }

    private func handleMiddleClick(_ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.mouseEventButtonNumber) == 2,
              Prefs.isEnabled, Prefs.action(for: .middleClick) != .none,
              Prefs.requiredModifier.isSatisfied(by: event.flags),
              let window = WindowManager.shared.titleBarWindow(at: event.location, bandHeight: Prefs.bandHeight)
        else { return false }
        return trigger(.middleClick, window: window, flags: event.flags, at: event.location)
    }

    private func handleMagnify(_ event: NSEvent) {
        let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        if event.phase.contains(.began) {
            pinch = nil
            let point = Self.topLeftMouseLocation()
            guard Prefs.isEnabled, Prefs.requiredModifier.isSatisfied(by: flags),
                  let window = WindowManager.shared.titleBarWindow(at: point, bandHeight: Prefs.bandHeight)
            else { return }
            pinch = PinchSession(window: window)
            return
        }
        guard var session = pinch else { return }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            pinch = nil
            return
        }
        session.total += event.magnification
        if !session.fired, abs(session.total) >= Prefs.pinchThreshold {
            session.fired = true
            let gesture: Gesture = session.total < 0 ? .pinchIn : .pinchOut
            trigger(gesture, window: session.window, flags: flags, at: Self.topLeftMouseLocation())
        }
        pinch = session
    }

    // MARK: - Dispatch

    /// Runs the action mapped to `gesture`. Returns `true` if something was (or will be) done.
    @discardableResult
    private func trigger(_ gesture: Gesture, window: AXUIElement, flags: CGEventFlags, at point: CGPoint) -> Bool {
        let action = Prefs.action(for: gesture)
        guard action != .none else { return false }

        if action == .close, Prefs.closeRequiresModifier {
            let needed = Prefs.requiredModifier == .none ? ModifierRequirement.option : Prefs.requiredModifier
            guard needed.isSatisfied(by: flags) else {
                feedback("Hold \(needed.title) to Close", symbol: "exclamationmark.triangle", at: point)
                return gesture != .middleClick
            }
        }

        if action == .close {
            // Show a confirmation tick first, then close.
            feedback("Close", symbol: "checkmark.circle.fill", at: point)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                WindowManager.shared.perform(.close, on: window)
            }
            return true
        }

        let done = WindowManager.shared.perform(action, on: window)
        feedback(done ? action.title : "\(action.title) unavailable", symbol: gesture.symbol, at: point)
        return true
    }

    private func feedback(_ text: String, symbol: String, at point: CGPoint) {
        guard Prefs.showsFeedback else { return }
        DispatchQueue.main.async { FeedbackHUD.shared.show(text, symbol: symbol, nearTopLeftPoint: point) }
    }

    private static func topLeftMouseLocation() -> CGPoint {
        let location = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: location.x, y: primaryHeight - location.y)
    }
}
