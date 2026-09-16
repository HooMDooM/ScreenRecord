import AppKit
import Carbon.HIToolbox

private let specialKeys: [Int: String] = [
    kVK_Return: "⏎", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
    kVK_Escape: "esc", kVK_LeftArrow: "←", kVK_RightArrow: "→",
    kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_ForwardDelete: "⌦",
    kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟"
]

private final class KeycapsView: NSView {
    var keys: [String] = [] { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, !keys.isEmpty else { return }
        let font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]

        var widths: [CGFloat] = []
        for key in keys {
            widths.append(max(44, (key as NSString).size(withAttributes: attributes).width + 26))
        }
        let spacing: CGFloat = 8
        let total = widths.reduce(0, +) + spacing * CGFloat(max(0, keys.count - 1))
        var x = bounds.midX - total / 2

        for (index, key) in keys.enumerated() {
            let box = CGRect(x: x, y: bounds.midY - 22, width: widths[index], height: 44)
            context.setFillColor(NSColor.black.withAlphaComponent(0.72).cgColor)
            context.addPath(CGPath(roundedRect: box, cornerWidth: 10, cornerHeight: 10, transform: nil))
            context.fillPath()
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
            context.setLineWidth(1)
            context.addPath(CGPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 10, cornerHeight: 10, transform: nil))
            context.strokePath()

            let size = (key as NSString).size(withAttributes: attributes)
            (key as NSString).draw(at: CGPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2),
                                   withAttributes: attributes)
            x += widths[index] + spacing
        }
    }
}

/// Draws the keys the user presses on top of the recorded area.
@MainActor
final class KeystrokeOverlayController {
    private var window: NSWindow?
    private var view = KeycapsView()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hideWorkItem: DispatchWorkItem?

    static func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func start(in area: CGRect) {
        stop()
        let width = min(max(320, area.width), 900)
        let frame = CGRect(x: area.midX - width / 2,
                           y: area.minY + 24,
                           width: width, height: 60)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        view.frame = NSRect(origin: .zero, size: frame.size)
        window.contentView = view
        window.alphaValue = 0
        window.orderFrontRegardless()
        self.window = window
        installTap()
    }

    private func installTap() {
        let mask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon, type == .keyDown else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<KeystrokeOverlayController>.fromOpaque(refcon).takeUnretainedValue()
            let description = KeystrokeOverlayController.describe(event: event)
            DispatchQueue.main.async { controller.show(description) }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .listenOnly,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
    }

    nonisolated static func describe(event: CGEvent) -> [String] {
        let flags = event.flags
        var parts: [String] = []
        if flags.contains(.maskCommand) { parts.append("⌘") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskShift) { parts.append("⇧") }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        if let named = specialKeys[keyCode] {
            parts.append(named)
        } else if let nsEvent = NSEvent(cgEvent: event),
                  let characters = nsEvent.charactersIgnoringModifiers, !characters.isEmpty {
            parts.append(characters.uppercased())
        }
        return parts
    }

    private func show(_ keys: [String]) {
        guard let window, !keys.isEmpty else { return }
        view.keys = keys
        hideWorkItem?.cancel()
        window.animator().alphaValue = 1
        let item = DispatchWorkItem { [weak self] in
            self?.window?.animator().alphaValue = 0
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: item)
    }

    func stop() {
        hideWorkItem?.cancel()
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        window?.orderOut(nil)
        window = nil
        view.keys = []
    }

    var windowNumber: Int? { window?.windowNumber }
}
