import AppKit
import SwiftUI

/// Shows a brief, non-activating floating label confirming the action that was performed.
final class FeedbackHUD {
    static let shared = FeedbackHUD()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    /// Displays `text` just below `point`, given in global top-left (Quartz) coordinates.
    func show(_ text: String, symbol: String, nearTopLeftPoint point: CGPoint) {
        let host = NSHostingView(rootView: HUDLabel(text: text, symbol: symbol))
        let size = host.fittingSize
        let panel = self.panel ?? makePanel()
        panel.contentView = host

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var origin = CGPoint(x: point.x - size.width / 2, y: primaryHeight - point.y - size.height - 24)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: point.x, y: primaryHeight - point.y)) }) {
            let area = screen.visibleFrame
            origin.x = min(max(origin.x, area.minX + 8), area.maxX - size.width - 8)
            origin.y = min(max(origin.y, area.minY + 8), area.maxY - size.height - 8)
        }
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak panel] in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                panel?.animator().alphaValue = 0
            }, completionHandler: { panel?.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.panel = panel
        return panel
    }
}

/// The pill-shaped label rendered inside the feedback HUD.
private struct HUDLabel: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .fixedSize()
    }
}
