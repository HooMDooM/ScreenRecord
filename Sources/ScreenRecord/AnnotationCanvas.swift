import AppKit

enum AnnotationTool: String, CaseIterable, Identifiable {
    case arrow, line, rectangle, ellipse, pen, highlighter, text, number

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .text: return "textformat"
        case .number: return "1.circle"
        }
    }

    func title(_ lang: Language) -> String {
        switch self {
        case .arrow: return lang == .ru ? "Стрелка" : "Arrow"
        case .line: return lang == .ru ? "Линия" : "Line"
        case .rectangle: return lang == .ru ? "Прямоугольник" : "Rectangle"
        case .ellipse: return lang == .ru ? "Овал" : "Ellipse"
        case .pen: return lang == .ru ? "Карандаш" : "Pen"
        case .highlighter: return lang == .ru ? "Маркер" : "Highlighter"
        case .text: return lang == .ru ? "Текст" : "Text"
        case .number: return lang == .ru ? "Нумерация" : "Numbered step"
        }
    }
}

struct Annotation {
    var tool: AnnotationTool
    var color: NSColor
    var lineWidth: CGFloat
    var start: CGPoint = .zero
    var end: CGPoint = .zero
    var points: [CGPoint] = []
    var text: String = ""
    var number: Int = 1
}

/// Draws annotations, either over a captured image or straight over the screen.
final class AnnotationCanvasView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    /// Where the frozen snapshot sits in view coordinates. While the region is
    /// being resized it stays pinned to the screen instead of stretching.
    var imageRect: CGRect? { didSet { needsDisplay = true } }
    private(set) var annotations: [Annotation] = [] { didSet { needsDisplay = true } }
    var tool: AnnotationTool = .arrow
    var color: NSColor = .systemRed
    var lineWidth: CGFloat = 4
    /// Dashed outline marking the captured region while drawing on screen.
    var showsBorder = false { didSet { needsDisplay = true } }
    /// Green handles that let the user resize the region after selecting it.
    var allowsRegionEditing = false { didSet { needsDisplay = true } }
    var onRegionResize: ((Int, CGPoint) -> Void)?
    var onRegionResizeEnded: (() -> Void)?
    private var activeHandle: Int?
    var onTextRequested: ((CGPoint) -> Void)?
    var onChange: (() -> Void)?

    private var current: Annotation?

    init(image: NSImage?) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: image?.size ?? .zero))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        image?.draw(in: imageRect ?? bounds)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if showsBorder {
            context.setStrokeColor(Theme.selectionGreen.cgColor)
            context.setLineWidth(1.5)
            context.setLineDash(phase: 0, lengths: [6, 4])
            context.stroke(bounds.insetBy(dx: 0.75, dy: 0.75))
            context.setLineDash(phase: 0, lengths: [])
        }
        for annotation in annotations {
            draw(annotation, in: context)
        }
        if let current {
            draw(current, in: context)
        }
        if allowsRegionEditing {
            context.setFillColor(Theme.selectionGreen.cgColor)
            for point in regionHandles() {
                context.fillEllipse(in: CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9))
            }
        }
    }

    /// Handle order: 0 tl, 1 t, 2 tr, 3 r, 4 br, 5 b, 6 bl, 7 l
    private func regionHandles() -> [CGPoint] {
        let rect = bounds.insetBy(dx: 2, dy: 2)
        return [
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.minX, y: rect.midY)
        ]
    }

    private func draw(_ annotation: Annotation, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }

        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(annotation.lineWidth)
        context.setStrokeColor(annotation.color.cgColor)

        switch annotation.tool {
        case .rectangle:
            context.stroke(CGRect(point: annotation.start, to: annotation.end))
        case .ellipse:
            context.strokeEllipse(in: CGRect(point: annotation.start, to: annotation.end))
        case .pen:
            strokePath(annotation.points, in: context)
        case .highlighter:
            context.setStrokeColor(annotation.color.withAlphaComponent(0.35).cgColor)
            context.setLineWidth(annotation.lineWidth * 4)
            context.setLineCap(.square)
            strokePath(annotation.points, in: context)
        case .arrow:
            drawArrow(annotation, in: context)
        case .line:
            context.move(to: annotation.start)
            context.addLine(to: annotation.end)
            context.strokePath()
        case .text:
            drawText(annotation)
        case .number:
            drawNumber(annotation, in: context)
        }
    }

    private func drawNumber(_ annotation: Annotation, in context: CGContext) {
        let radius = max(13, annotation.lineWidth * 4)
        let box = CGRect(x: annotation.start.x - radius, y: annotation.start.y - radius,
                         width: radius * 2, height: radius * 2)
        context.setFillColor(annotation.color.cgColor)
        context.fillEllipse(in: box)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(max(1.5, annotation.lineWidth / 2))
        context.strokeEllipse(in: box)

        let text = "\(annotation.number)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: radius * 1.2, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2),
                  withAttributes: attributes)
    }

    private func strokePath(_ points: [CGPoint], in context: CGContext) {
        guard let first = points.first else { return }
        context.move(to: first)
        for point in points.dropFirst() { context.addLine(to: point) }
        context.strokePath()
    }

    private func drawArrow(_ annotation: Annotation, in context: CGContext) {
        let start = annotation.start
        let end = annotation.end
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(12, annotation.lineWidth * 4)
        let shaftEnd = CGPoint(x: end.x - cos(angle) * headLength * 0.8,
                               y: end.y - sin(angle) * headLength * 0.8)
        context.move(to: start)
        context.addLine(to: shaftEnd)
        context.strokePath()

        let spread = CGFloat.pi / 7
        context.move(to: end)
        context.addLine(to: CGPoint(x: end.x - cos(angle - spread) * headLength,
                                    y: end.y - sin(angle - spread) * headLength))
        context.addLine(to: CGPoint(x: end.x - cos(angle + spread) * headLength,
                                    y: end.y - sin(angle + spread) * headLength))
        context.closePath()
        context.setFillColor(annotation.color.cgColor)
        context.fillPath()
    }

    private func drawText(_ annotation: Annotation) {
        guard !annotation.text.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: annotation.lineWidth * 5, weight: .semibold),
            .foregroundColor: annotation.color
        ]
        (annotation.text as NSString).draw(at: annotation.start, withAttributes: attributes)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if allowsRegionEditing,
           let handle = regionHandles().firstIndex(where: { hypot($0.x - point.x, $0.y - point.y) < 13 }) {
            activeHandle = handle
            return
        }
        if tool == .text {
            onTextRequested?(point)
            return
        }
        if tool == .number {
            var stamp = Annotation(tool: .number, color: color, lineWidth: lineWidth)
            stamp.start = point
            stamp.number = annotations.filter { $0.tool == .number }.count + 1
            annotations.append(stamp)
            onChange?()
            return
        }
        var annotation = Annotation(tool: tool, color: color, lineWidth: lineWidth)
        annotation.start = point
        annotation.end = point
        annotation.points = [point]
        current = annotation
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if let activeHandle {
            onRegionResize?(activeHandle, NSEvent.mouseLocation)
            return
        }
        guard current != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        current?.end = point
        current?.points.append(point)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if activeHandle != nil {
            activeHandle = nil
            onRegionResizeEnded?()
            return
        }
        guard let annotation = current else { return }
        current = nil
        let moved = hypot(annotation.end.x - annotation.start.x, annotation.end.y - annotation.start.y)
        if moved > 3 || annotation.points.count > 3 {
            annotations.append(annotation)
            onChange?()
        } else {
            needsDisplay = true
        }
    }

    // MARK: - Editing

    func addText(_ text: String, at point: CGPoint) {
        guard !text.isEmpty else { return }
        var annotation = Annotation(tool: .text, color: color, lineWidth: lineWidth)
        annotation.start = point
        annotation.text = text
        annotations.append(annotation)
        onChange?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: tool == .text ? .iBeam : .crosshair)
    }

    /// Keeps drawings visually in place when the region origin moves.
    func shiftAnnotations(by offset: CGPoint) {
        guard offset != .zero else { return }
        for index in annotations.indices {
            annotations[index].start.x += offset.x
            annotations[index].start.y += offset.y
            annotations[index].end.x += offset.x
            annotations[index].end.y += offset.y
            for pointIndex in annotations[index].points.indices {
                annotations[index].points[pointIndex].x += offset.x
                annotations[index].points[pointIndex].y += offset.y
            }
        }
    }

    func undo() {
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        onChange?()
    }

    func clear() {
        annotations.removeAll()
        onChange?()
    }

    var hasAnnotations: Bool { !annotations.isEmpty }

    /// Bakes the on-screen annotations into a capture of the same region,
    /// scaling from view points to capture pixels.
    func render(over capture: CGImage) -> NSImage {
        let pixelSize = CGSize(width: capture.width, height: capture.height)
        let result = NSImage(size: pixelSize)
        result.lockFocus()
        defer { result.unlockFocus() }

        guard let context = NSGraphicsContext.current?.cgContext else { return result }
        context.draw(capture, in: CGRect(origin: .zero, size: pixelSize))
        guard bounds.width > 0, bounds.height > 0 else { return result }
        context.scaleBy(x: pixelSize.width / bounds.width, y: pixelSize.height / bounds.height)
        for annotation in annotations {
            draw(annotation, in: context)
        }
        return result
    }
}

private extension CGRect {
    init(point a: CGPoint, to b: CGPoint) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}
