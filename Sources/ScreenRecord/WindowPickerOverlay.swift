import AppKit
import ScreenCaptureKit

enum ScreenGeometry {
    /// Converts a CoreGraphics rect (top-left origin, primary display) to Cocoa global coordinates.
    static func cocoaRect(fromCG rect: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return rect }
        return CGRect(x: rect.minX,
                      y: primary.frame.maxY - rect.maxY,
                      width: rect.width, height: rect.height)
    }
}

private final class WindowHighlightView: NSView {
    var highlight: CGRect = .zero { didSet { needsDisplay = true } }
    var title: String = ""
    var hint: String?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(NSColor.black.withAlphaComponent(0.25).cgColor)
        context.fill(bounds)

        if let hint, highlight.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let size = (hint as NSString).size(withAttributes: attributes)
            let box = CGRect(x: bounds.midX - size.width / 2 - 16, y: bounds.midY - size.height / 2 - 10,
                             width: size.width + 32, height: size.height + 20)
            context.setFillColor(NSColor.black.withAlphaComponent(0.6).cgColor)
            context.addPath(CGPath(roundedRect: box, cornerWidth: 10, cornerHeight: 10, transform: nil))
            context.fillPath()
            (hint as NSString).draw(at: CGPoint(x: box.minX + 16, y: box.minY + 10), withAttributes: attributes)
        }

        guard !highlight.isEmpty else { return }
        context.setBlendMode(.clear)
        context.fill(highlight)
        context.setBlendMode(.normal)
        context.setStrokeColor(Theme.selectionGreen.cgColor)
        context.setLineWidth(2)
        context.setLineDash(phase: 0, lengths: [6, 4])
        context.stroke(highlight.insetBy(dx: -1, dy: -1))

        guard !title.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        let box = CGRect(x: highlight.midX - size.width / 2 - 8,
                         y: max(4, highlight.minY - size.height - 12),
                         width: size.width + 16, height: size.height + 8)
        context.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        context.addPath(CGPath(roundedRect: box, cornerWidth: 6, cornerHeight: 6, transform: nil))
        context.fillPath()
        (title as NSString).draw(at: CGPoint(x: box.minX + 8, y: box.minY + 4), withAttributes: attributes)
    }
}

@MainActor
final class WindowPickerController {
    private var windows: [OverlayWindow] = []
    private var views: [WindowHighlightView] = []
    private var monitors: [Any] = []
    private var candidates: [SCWindow] = []
    private var hovered: SCWindow?

    var onPick: ((SCWindow) -> Void)?
    var onCancel: (() -> Void)?

    func present(windows candidates: [SCWindow], hint: String) {
        dismiss()
        let ownNumbers = Set(NSApp.windows.compactMap { CGWindowID(exactly: $0.windowNumber) })
        self.candidates = candidates.filter {
            $0.isOnScreen && $0.frame.width > 60 && $0.frame.height > 60 && !ownNumbers.contains($0.windowID)
        }

        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen)
            let view = WindowHighlightView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.hint = screen == NSScreen.main ? hint : nil
            window.contentView = view
            window.orderFrontRegardless()
            self.windows.append(window)
            views.append(view)
        }
        windows.first?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.updateHover()
            return event
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            if let hovered = self.hovered { self.onPick?(hovered) } else { self.onCancel?() }
            return nil
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { self?.onCancel?(); return nil }
            return event
        } as Any)
        updateHover()
    }

    private func updateHover() {
        let mouse = NSEvent.mouseLocation
        let match = candidates.first { ScreenGeometry.cocoaRect(fromCG: $0.frame).contains(mouse) }
        hovered = match
        for (screen, view) in zip(NSScreen.screens, views) {
            if let match {
                let global = ScreenGeometry.cocoaRect(fromCG: match.frame)
                let local = global.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
                view.highlight = local.intersection(view.bounds)
                view.title = [match.owningApplication?.applicationName, match.title]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
                view.hint = nil
            } else {
                view.highlight = .zero
                view.title = ""
            }
        }
    }

    func dismiss() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        candidates.removeAll()
        hovered = nil
    }
}
