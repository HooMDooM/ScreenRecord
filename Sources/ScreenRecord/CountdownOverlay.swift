import AppKit

private final class CountdownView: NSView {
    var value: Int = 3 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let circle = bounds.insetBy(dx: 6, dy: 6)
        context.setFillColor(NSColor.black.withAlphaComponent(0.7).cgColor)
        context.fillEllipse(in: circle)
        context.setStrokeColor(Theme.selectionGreen.cgColor)
        context.setLineWidth(4)
        context.strokeEllipse(in: circle.insetBy(dx: 2, dy: 2))

        let text = "\(value)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 68, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
                  withAttributes: attributes)
    }
}

@MainActor
final class CountdownController {
    private var window: NSWindow?
    private let view = CountdownView()
    private var timer: Timer?

    /// Counts down over `seconds`, then calls `completion`. Returns immediately.
    func run(seconds: Int, near area: CGRect?, completion: @escaping () -> Void) {
        cancel()
        guard seconds > 0 else { completion(); return }

        let screenFrame = area ?? NSScreen.main?.frame ?? .zero
        let side: CGFloat = 160
        let frame = CGRect(x: screenFrame.midX - side / 2, y: screenFrame.midY - side / 2, width: side, height: side)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        view.frame = NSRect(origin: .zero, size: frame.size)
        view.value = seconds
        window.contentView = view
        window.orderFrontRegardless()
        self.window = window

        var remaining = seconds
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                remaining -= 1
                if remaining <= 0 {
                    timer.invalidate()
                    self?.cancel()
                    completion()
                } else {
                    self?.view.value = remaining
                }
            }
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window = nil
    }

    var windowNumber: Int? { window?.windowNumber }
}
