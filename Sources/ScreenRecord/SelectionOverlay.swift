import AppKit

/// Full-screen transparent window used for the green dashed area selector.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen, level: NSWindow.Level = .screenSaver) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        self.level = level
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.setFrame(screen.frame, display: false)
        self.isReleasedWhenClosed = false
    }
}

final class SelectionView: NSView {
    enum DragMode {
        case none, creating, moving, resizing(Int)
    }

    var selection: CGRect = .zero { didSet { needsDisplay = true } }
    var dimsBackground = true { didSet { needsDisplay = true } }
    var showsHandles = true { didSet { needsDisplay = true } }
    var hintText: String? { didSet { needsDisplay = true } }
    /// When true only the frame edges and handles catch the mouse, so clicks
    /// inside and outside the selection reach the apps underneath.
    var passesClicksThrough = false

    var onChange: ((CGRect) -> Void)?
    var onCommit: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var dragMode: DragMode = .none
    private var dragOrigin: CGPoint = .zero
    private var initialSelection: CGRect = .zero
    private let handleRadius: CGFloat = 4.5
    private let minimumSize: CGFloat = 40

    override var acceptsFirstResponder: Bool { true }

    /// Without this the very first click on an inactive app only activates the
    /// window and never reaches `mouseDown`, so the first drag was lost.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Handle order: 0 tl, 1 t, 2 tr, 3 r, 4 br, 5 b, 6 bl, 7 l
    private func handlePoints(_ rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.midY)
        ]
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        if dimsBackground {
            context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            context.fill(bounds)
            if !selection.isEmpty {
                context.setBlendMode(.clear)
                context.fill(selection)
                context.setBlendMode(.normal)
            }
        }

        guard !selection.isEmpty else {
            if let hintText { drawHint(hintText, in: context) }
            return
        }
        if let hintText { drawHint(hintText, in: context, below: selection) }

        context.setStrokeColor(Theme.selectionGreen.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [6, 4])
        context.stroke(selection.insetBy(dx: -0.75, dy: -0.75))
        context.setLineDash(phase: 0, lengths: [])

        if showsHandles {
            context.setFillColor(Theme.selectionGreen.cgColor)
            for point in handlePoints(selection) {
                context.fillEllipse(in: CGRect(x: point.x - handleRadius, y: point.y - handleRadius,
                                               width: handleRadius * 2, height: handleRadius * 2))
            }
        }

        drawSizeBadge(context: context)
    }

    private func drawSizeBadge(context: CGContext) {
        let text = "\(Int(selection.width)) × \(Int(selection.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        var origin = CGPoint(x: selection.minX, y: selection.maxY + 8)
        if origin.y + size.height + 8 > bounds.maxY { origin.y = selection.maxY - size.height - 14 }
        let box = CGRect(x: origin.x, y: origin.y, width: size.width + 12, height: size.height + 6)
        context.setFillColor(NSColor.black.withAlphaComponent(0.65).cgColor)
        context.addPath(CGPath(roundedRect: box, cornerWidth: 5, cornerHeight: 5, transform: nil))
        context.fillPath()
        (text as NSString).draw(at: CGPoint(x: box.minX + 6, y: box.minY + 3), withAttributes: attributes)
    }

    private func drawHint(_ text: String, in context: CGContext, below rect: CGRect? = nil) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        var center = CGPoint(x: bounds.midX, y: bounds.midY)
        if let rect {
            center.x = rect.midX
            center.y = rect.minY - size.height - 24
            if center.y < bounds.minY + 20 { center.y = min(rect.maxY + 30, bounds.maxY - 30) }
        }
        let box = CGRect(x: center.x - size.width / 2 - 16,
                         y: center.y - size.height / 2 - 10,
                         width: size.width + 32, height: size.height + 20)
        context.setFillColor(NSColor.black.withAlphaComponent(0.6).cgColor)
        context.addPath(CGPath(roundedRect: box, cornerWidth: 10, cornerHeight: 10, transform: nil))
        context.fillPath()
        (text as NSString).draw(at: CGPoint(x: box.minX + 16, y: box.minY + 10), withAttributes: attributes)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragOrigin = point
        initialSelection = selection
        hintText = nil

        if !selection.isEmpty {
            if event.clickCount == 2, selection.contains(point) {
                onCommit?(selection)
                return
            }
            for (index, handle) in handlePoints(selection).enumerated()
            where hypot(handle.x - point.x, handle.y - point.y) < 12 {
                dragMode = .resizing(index)
                return
            }
            if selection.contains(point) {
                dragMode = .moving
                return
            }
        }
        dragMode = .creating
        selection = CGRect(origin: point, size: .zero)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch dragMode {
        case .none:
            return
        case .creating:
            selection = CGRect(x: min(dragOrigin.x, point.x), y: min(dragOrigin.y, point.y),
                               width: abs(point.x - dragOrigin.x), height: abs(point.y - dragOrigin.y))
        case .moving:
            var rect = initialSelection.offsetBy(dx: point.x - dragOrigin.x, dy: point.y - dragOrigin.y)
            rect.origin.x = min(max(0, rect.origin.x), bounds.width - rect.width)
            rect.origin.y = min(max(0, rect.origin.y), bounds.height - rect.height)
            selection = rect
        case .resizing(let index):
            selection = resized(initialSelection, handle: index, to: point)
        }
        onChange?(selection)
    }

    override func mouseUp(with event: NSEvent) {
        // A double-click already committed in mouseDown; don't commit twice.
        guard !isIdle(dragMode) else { return }
        dragMode = .none
        if selection.width < minimumSize || selection.height < minimumSize {
            // A plain click or a tiny drag: keep the previous region (if any)
            // but wait for an explicit confirmation instead of committing it.
            selection = initialSelection.isEmpty ? .zero : initialSelection
            onChange?(selection)
            return
        }
        selection = selection.integral
        onChange?(selection)
        onCommit?(selection)
    }

    private func isIdle(_ mode: DragMode) -> Bool {
        if case .none = mode { return true }
        return false
    }

    private func resized(_ rect: CGRect, handle: Int, to point: CGPoint) -> CGRect {
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        switch handle {
        case 0: minX = point.x; maxY = point.y
        case 1: maxY = point.y
        case 2: maxX = point.x; maxY = point.y
        case 3: maxX = point.x
        case 4: maxX = point.x; minY = point.y
        case 5: minY = point.y
        case 6: minX = point.x; minY = point.y
        default: minX = point.x
        }
        let result = CGRect(x: min(minX, maxX), y: min(minY, maxY),
                            width: max(minimumSize, abs(maxX - minX)),
                            height: max(minimumSize, abs(maxY - minY)))
        return result.intersection(bounds).isNull ? rect : result
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onCancel?()
        case 36, 76: if !selection.isEmpty { onCommit?(selection) }
        default: super.keyDown(with: event)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard passesClicksThrough else { return super.hitTest(point) }
        guard !selection.isEmpty else { return nil }
        let local = convert(point, from: superview)
        if handlePoints(selection).contains(where: { hypot($0.x - local.x, $0.y - local.y) < 12 }) {
            return self
        }
        let outer = selection.insetBy(dx: -5, dy: -5)
        let inner = selection.insetBy(dx: 5, dy: 5)
        return outer.contains(local) && !inner.contains(local) ? self : nil
    }

    override func resetCursorRects() {
        if passesClicksThrough {
            guard !selection.isEmpty else { return }
            addCursorRect(selection.insetBy(dx: -6, dy: -6), cursor: .openHand)
        } else {
            addCursorRect(bounds, cursor: selection.isEmpty ? .crosshair : .arrow)
        }
    }
}

@MainActor
final class SelectionOverlayController {
    private var windows: [OverlayWindow] = []
    private var views: [SelectionView] = []
    private(set) var activeScreen: NSScreen?

    var onCommit: ((NSScreen, CGRect) -> Void)?
    var onCancel: (() -> Void)?
    var onChange: ((CGRect) -> Void)?

    /// Selection in global (bottom-left origin) screen coordinates.
    private(set) var globalSelection: CGRect = .zero

    var isVisible: Bool { !windows.isEmpty }

    func present(hint: String, initial: CGRect? = nil) {
        dismiss()
        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen)
            let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.hintText = screen == NSScreen.main ? hint : nil
            view.onChange = { [weak self, weak window] rect in
                guard let self, let window, self.windows.contains(where: { $0 === window }) else { return }
                self.activeScreen = screen
                self.globalSelection = rect.isEmpty ? .zero : rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
                self.clearOtherSelections(except: view)
                self.onChange?(self.globalSelection)
            }
            view.onCommit = { [weak self, weak window] rect in
                // Ignore late callbacks from an overlay that was already dismissed.
                guard let self, let window, rect.width > 0,
                      self.windows.contains(where: { $0 === window }) else { return }
                self.activeScreen = screen
                self.globalSelection = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
                self.onCommit?(screen, self.globalSelection)
            }
            view.onCancel = { [weak self] in self?.onCancel?() }
            window.contentView = view
            window.orderFrontRegardless()
            windows.append(window)
            views.append(view)

            if let initial, screen.frame.contains(initial.origin) {
                view.selection = initial.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
                view.hintText = L.t("confirmArea", AppSettings.shared.language)
                activeScreen = screen
                globalSelection = initial
            }
        }
        windows.first?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func clearOtherSelections(except view: SelectionView) {
        for other in views where other !== view {
            other.selection = .zero
            other.hintText = nil
            other.needsDisplay = true
        }
    }

    /// After the area is chosen the frame stays on screen but stops swallowing
    /// clicks, so the settings panel and the apps below remain usable.
    func enterAdjustMode() {
        for (window, view) in zip(windows, views) {
            view.dimsBackground = false
            view.showsHandles = true
            view.hintText = nil
            view.passesClicksThrough = true
            window.ignoresMouseEvents = false
            window.level = .floating
            window.invalidateCursorRects(for: view)
        }
    }

    /// Locks the frame in place for the duration of a recording.
    func enterRecordingMode() {
        for (window, view) in zip(windows, views) {
            view.dimsBackground = false
            view.showsHandles = false
            view.hintText = nil
            window.ignoresMouseEvents = true
            window.level = .floating
        }
    }

    func setSize(width: CGFloat, height: CGFloat) {
        guard let screen = activeScreen, let index = NSScreen.screens.firstIndex(of: screen),
              index < views.count, !globalSelection.isEmpty else { return }
        let view = views[index]
        var rect = view.selection
        rect.origin.y = rect.maxY - height
        rect.size = CGSize(width: width, height: height)
        rect.origin.x = min(rect.origin.x, view.bounds.width - width)
        rect.origin.y = max(0, min(rect.origin.y, view.bounds.height - height))
        view.selection = rect
        globalSelection = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        onChange?(globalSelection)
    }

    func dismiss() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        globalSelection = .zero
        activeScreen = nil
    }

    var windowNumbers: [Int] { windows.map(\.windowNumber) }
}
