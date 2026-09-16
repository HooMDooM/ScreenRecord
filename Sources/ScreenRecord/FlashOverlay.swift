import AppKit

/// Brief white flash over the captured area, the usual "shot taken" feedback.
@MainActor
enum FlashOverlay {
    static func show(in area: CGRect) {
        guard !area.isEmpty else { return }
        let window = NSWindow(contentRect: area, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.backgroundColor = .white
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.alphaValue = 0.75
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            window.animator().alphaValue = 0
        } completionHandler: {
            window.orderOut(nil)
        }
    }
}
