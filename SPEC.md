# TitlebarGestures — specification

**Tagline:** Resize, close, and snap windows with scroll and pinch gestures over the title bar.

**Category:** Window Management

**Inspired by (paid):** Swish ($15.99 one-time)

**Frameworks:** SwiftUI, AppKit, ApplicationServices, CoreGraphics, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

(1) What the paid app does. Swish costs about 16 dollars one-time and lets people control windows with trackpad gestures: pinch to close, swipe to snap and so on. It gets regular mention in the best window manager lists and in Apple news coverage, which shows people pay to avoid reaching for keyboard shortcuts. Our clean-room version supports the gestures macOS delivers through public event APIs, scoped to when the pointer sits over a window title bar.

(2) Feature set. When the pointer is within the top 28 points of a window, the app interprets scroll and magnification events on that zone instead of passing them on. Mappings are configurable. Defaults: a horizontal two-finger swipe left snaps the window to the left half, swipe right snaps to the right half, swipe up maximizes, swipe down restores the previous size, a pinch in minimizes, and a middle-click on the title bar closes the window after a confirmation tick. A short on-screen label confirms the action. Gesture sensitivity and a modifier requirement such as holding Option are available as safeguards.

(3) UI spec. MenuBarExtra with a hand icon. The menu has an Enabled toggle, Settings and Quit. The Settings window contains a table of gesture to action pickers for swipe left, swipe right, swipe up, swipe down, pinch in, pinch out and middle click, with actions drawn from None, Left Half, Right Half, Maximize, Restore, Center, Minimize, Close and Next Display. Additional fields: required modifier picker, sensitivity slider, title bar height stepper, show feedback toggle, launch at login toggle. Empty state: if permissions are missing, the Settings window shows a banner with two grant buttons for Accessibility and Input Monitoring.

(4) Technical approach. Install a CGEventTap listening for scroll wheel events and gesture events, using the NSEvent global monitor as the listen-only alternative. Magnification events arrive as NSEvent type magnify through a global monitor, while swipes can be derived by accumulating scroll wheel deltas during a gesture phase from begin to end and acting when the accumulated delta passes a threshold. Find the window under the pointer with AXUIElementCopyElementAtPosition on the system-wide element and walk up the parent chain to the window role, then verify that the pointer is within the title bar band using the window's position attribute. Perform actions by setting position and size attributes, pressing the minimize or close buttons through the AXPress action, or setting AXMinimized. Store the last frame per window for restore. Request Accessibility trust via AXIsProcessTrustedWithOptions and Input Monitoring via CGRequestListenEventAccess. Persist mappings in AppStorage using raw string values. Launch at login via SMAppService.

(5) Edge cases. Do not trigger when the pointer is over a toolbar control that shares the title bar area, such as tabs, by checking that the element at the position has role window or toolbar group and not a button or text field. Debounce so one swipe produces one action. Respect the system natural scrolling setting by reading the isDirectionInvertedFromDevice flag. Ignore momentum-phase events. Full-screen windows are skipped. Closing requires an explicit modifier by default to prevent accidents.
