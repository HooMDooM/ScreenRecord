import AppKit
import SwiftUI

@MainActor
final class PanelController {
    private let panel: NSPanel
    private var lastAnchor: CGRect?

    init(state: AppState) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 490, height: 132),
                        styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
                        backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isFloatingPanel = true
        // Above the selection frame overlay, still below pop-up menus.
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = NSColor(Theme.panelBackground)
        panel.isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: RootView()
            .environmentObject(state)
            .environmentObject(state.settings))
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    var isVisible: Bool { panel.isVisible }

    static func size(for route: AppState.Route) -> CGSize {
        switch route {
        case .home: return CGSize(width: 490, height: 176)
        case .displayPicker: return CGSize(width: 490, height: 150)
        case .recordBar: return CGSize(width: 528, height: 216)
        }
    }

    func present(route: AppState.Route, anchor: CGRect?) {
        let size = PanelController.size(for: route)
        if let anchor { lastAnchor = anchor }
        let origin = position(for: size, anchor: anchor ?? lastAnchor)
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: panel.isVisible)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func position(for size: CGSize, anchor: CGRect?) -> CGPoint {
        guard let screen = (anchor.flatMap { rect in NSScreen.screens.first { $0.frame.intersects(rect) } }
                            ?? NSScreen.main) else { return .zero }
        let visible = screen.visibleFrame

        if let anchor {
            var x = anchor.midX - size.width / 2
            var y = anchor.minY - size.height - 14
            if y < visible.minY { y = min(anchor.maxY + 14, visible.maxY - size.height) }
            x = min(max(visible.minX + 8, x), visible.maxX - size.width - 8)
            return CGPoint(x: x, y: y)
        }
        return CGPoint(x: visible.midX - size.width / 2, y: visible.minY + 90)
    }

    func hide() {
        panel.orderOut(nil)
    }

    var windowNumber: Int { panel.windowNumber }
}
