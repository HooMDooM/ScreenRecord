import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Carbon.HIToolbox

@MainActor
final class MarkupModel: ObservableObject {
    @Published var tool: AnnotationTool = .arrow
    @Published var colorIndex = 0
    @Published var widthIndex = 1
    @Published var canUndo = false

    static let palette: [NSColor] = [
        .systemRed, .systemYellow, NSColor(Theme.accent), .systemBlue, .white, .black
    ]
    static let widths: [CGFloat] = [2, 4, 8]

    var color: NSColor { MarkupModel.palette[colorIndex] }
    var lineWidth: CGFloat { MarkupModel.widths[widthIndex] }

    var onSettingsChanged: () -> Void = {}
    var onUndo: () -> Void = {}
    var onClear: () -> Void = {}
    var onCopy: () -> Void = {}
    var onSave: () -> Void = {}
    var onSaveAs: () -> Void = {}
    var onCancel: () -> Void = {}
}

private final class CanvasWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Toolbar must be able to become key so the first click on Copy/Save is not
/// spent activating the window.
private final class ToolbarWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !isKeyWindow {
            makeKey()
        }
        super.sendEvent(event)
    }
}

/// Lets the user draw straight on top of the chosen region; the screenshot is
/// only taken when they save, so what they see is what lands in the file.
@MainActor
final class MarkupSession: NSObject {
    private var area: CGRect
    private let allowsResize: Bool
    private let capture: (CGRect) async throws -> CGImage
    private let onFinish: (URL?, CGRect) -> Void

    private let model = MarkupModel()
    private let canvas = AnnotationCanvasView(image: nil)
    private var canvasWindow: NSPanel?
    private var toolbarWindow: NSPanel?
    private var snapshot: CGImage?
    private var textField: NSTextField?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var finished = false

    private let settings = AppSettings.shared

    init(area: CGRect,
         allowsResize: Bool,
         capture: @escaping (CGRect) async throws -> CGImage,
         onFinish: @escaping (URL?, CGRect) -> Void) {
        self.area = area
        self.allowsResize = allowsResize
        self.capture = capture
        self.onFinish = onFinish
        super.init()
    }

    // MARK: - Presentation

    /// Freezes the region first, then shows the markup layer on top of the still.
    func begin() {
        Task {
            // Give the selection overlay a moment to leave the screen.
            try? await Task.sleep(nanoseconds: 80_000_000)
            snapshot = try? await capture(area)
            // The session may have been cancelled while the capture was in flight.
            guard !finished else { return }
            canvas.image = snapshot.map { NSImage(cgImage: $0, size: area.size) }
            canvas.imageRect = nil
            present()
        }
    }

    private func present() {
        let canvasPanel = CanvasWindow(contentRect: area, styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
        // A fully transparent window lets clicks fall through to the apps below,
        // so the canvas keeps a barely visible backing to capture the mouse.
        canvasPanel.backgroundColor = NSColor.white.withAlphaComponent(0.01)
        canvasPanel.isOpaque = false
        canvasPanel.hasShadow = false
        canvasPanel.acceptsMouseMovedEvents = true
        canvasPanel.level = .screenSaver
        canvasPanel.isMovableByWindowBackground = false
        canvasPanel.isMovable = false
        canvasPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        canvasPanel.isReleasedWhenClosed = false

        canvas.frame = NSRect(origin: .zero, size: area.size)
        canvas.autoresizingMask = [.width, .height]
        canvas.tool = model.tool
        canvas.color = model.color
        canvas.lineWidth = model.lineWidth
        canvas.showsBorder = true
        canvas.allowsRegionEditing = allowsResize
        canvas.onChange = { [weak self] in
            self?.model.canUndo = self?.canvas.hasAnnotations ?? false
        }
        canvas.onRegionResize = { [weak self] handle, point in
            self?.resizeRegion(handle: handle, to: point)
        }
        canvas.onRegionResizeEnded = { [weak self] in self?.refreshSnapshot() }
        canvas.onTextRequested = { [weak self] point in self?.beginTextEditing(at: point) }
        canvasPanel.contentView = canvas
        canvasPanel.orderFrontRegardless()
        canvasWindow = canvasPanel

        model.onSettingsChanged = { [weak self] in
            guard let self else { return }
            canvas.tool = model.tool
            canvas.color = model.color
            canvas.lineWidth = model.lineWidth
            canvasWindow?.invalidateCursorRects(for: canvas)
        }
        model.onUndo = { [weak self] in self?.canvas.undo() }
        model.onClear = { [weak self] in self?.canvas.clear() }
        model.onCopy = { [weak self] in self?.finish(mode: .copy) }
        model.onSave = { [weak self] in self?.finish(mode: .save) }
        model.onSaveAs = { [weak self] in self?.finish(mode: .saveAs) }
        model.onCancel = { [weak self] in self?.cancel() }

        presentToolbar()
        installKeyMonitors()
        NSApp.activate(ignoringOtherApps: true)
        toolbarWindow?.makeKeyAndOrderFront(nil)
    }

    private func installKeyMonitors() {
        let handle: (NSEvent) -> Bool = { [weak self] event in
            guard let self, self.textField == nil || event.keyCode == 53 else { return false }
            let command = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control)
            switch (Int(event.keyCode), command) {
            case (53, _): self.cancel(); return true
            case (36, _), (76, _): self.finish(mode: .save); return true
            case (kVK_ANSI_C, true): self.finish(mode: .copy); return true
            case (kVK_ANSI_S, true):
                self.finish(mode: event.modifierFlags.contains(.shift) ? .saveAs : .save)
                return true
            case (kVK_ANSI_Z, true): self.canvas.undo(); return true
            default: return false
            }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handle(event) ? nil : event
        }
        // Local monitors only fire while this app is key. After a selection the
        // previously focused app often keeps keyboard focus, so ⌘C must also
        // be observed globally.
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { event in
            _ = handle(event)
        }
    }

    // MARK: - Region editing

    private func resizeRegion(handle: Int, to point: CGPoint) {
        var minX = area.minX, maxX = area.maxX, minY = area.minY, maxY = area.maxY
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
        let minimum: CGFloat = 60
        let rect = CGRect(x: min(minX, maxX), y: min(minY, maxY),
                          width: max(minimum, abs(maxX - minX)),
                          height: max(minimum, abs(maxY - minY))).integral
        apply(area: rect)
    }

    private func apply(area rect: CGRect) {
        guard rect != area, let window = canvasWindow else { return }
        let offset = CGPoint(x: area.minX - rect.minX, y: area.minY - rect.minY)
        canvas.shiftAnnotations(by: offset)
        let previousImageRect = canvas.imageRect ?? CGRect(origin: .zero, size: area.size)
        canvas.imageRect = previousImageRect.offsetBy(dx: offset.x, dy: offset.y)
        area = rect
        window.setFrame(rect, display: true)
        canvas.frame = NSRect(origin: .zero, size: rect.size)
        window.invalidateCursorRects(for: canvas)
        canvas.needsDisplay = true
        repositionToolbar()
    }

    /// Re-freezes the newly sized region so the preview matches it exactly.
    private func refreshSnapshot() {
        let rect = area
        Task {
            guard let image = try? await capture(rect), rect == area else { return }
            snapshot = image
            canvas.image = NSImage(cgImage: image, size: rect.size)
            canvas.imageRect = nil
        }
    }

    private func repositionToolbar() {
        guard let toolbar = toolbarWindow else { return }
        let size = toolbar.frame.size
        let screen = NSScreen.screens.first { $0.frame.intersects(area) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? area
        var origin = CGPoint(x: area.midX - size.width / 2, y: area.minY - size.height - 12)
        if origin.y < visible.minY + 8 { origin.y = min(area.maxY + 12, visible.maxY - size.height - 8) }
        origin.x = min(max(visible.minX + 8, origin.x), visible.maxX - size.width - 8)
        toolbar.setFrameOrigin(origin)
    }

    private func presentToolbar() {
        let size = CGSize(width: 680, height: 44)
        let screen = NSScreen.screens.first { $0.frame.intersects(area) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? area

        var origin = CGPoint(x: area.midX - size.width / 2, y: area.minY - size.height - 12)
        if origin.y < visible.minY + 8 { origin.y = min(area.maxY + 12, visible.maxY - size.height - 8) }
        origin.x = min(max(visible.minX + 8, origin.x), visible.maxX - size.width - 8)

        let panel = ToolbarWindow(contentRect: NSRect(origin: origin, size: size),
                                  styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .screenSaver
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false

        let hosting = FirstMouseHostingView(rootView: MarkupToolbar(model: model).environmentObject(settings))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.orderFrontRegardless()
        toolbarWindow = panel
    }

    // MARK: - Text tool

    private func beginTextEditing(at point: CGPoint) {
        commitText()
        let field = NSTextField(frame: NSRect(x: point.x, y: point.y - 8, width: 240, height: 26))
        field.font = .systemFont(ofSize: model.lineWidth * 4, weight: .semibold)
        field.textColor = model.color
        field.backgroundColor = NSColor.black.withAlphaComponent(0.35)
        field.drawsBackground = true
        field.isBordered = false
        field.focusRingType = .none
        field.placeholderString = settings.language == .ru ? "Текст…" : "Text…"
        field.target = self
        field.action = #selector(commitTextAction)
        canvas.addSubview(field)
        canvasWindow?.makeFirstResponder(field)
        textField = field
    }

    @objc private func commitTextAction() { commitText() }

    private func commitText() {
        guard let field = textField else { return }
        canvas.addText(field.stringValue, at: CGPoint(x: field.frame.minX, y: field.frame.minY + 8))
        field.removeFromSuperview()
        textField = nil
        canvasWindow?.makeFirstResponder(canvas)
    }

    // MARK: - Finishing

    private enum FinishMode { case copy, save, saveAs }

    private func finish(mode: FinishMode) {
        guard !finished else { return }
        finished = true
        commitText()
        Task {
            do {
                // The preview is already frozen, so save exactly what is shown.
                let shot: CGImage
                if let snapshot, snapshot.width > 0, canvas.imageRect == nil {
                    shot = snapshot
                } else {
                    canvasWindow?.orderOut(nil)
                    toolbarWindow?.orderOut(nil)
                    try? await Task.sleep(nanoseconds: 90_000_000)
                    shot = try await capture(area)
                }
                let image = canvas.render(over: shot)
                let isPNG = settings.screenshotFormat == .png
                guard let tiff = image.tiffRepresentation,
                      let representation = NSBitmapImageRep(data: tiff),
                      let data = representation.representation(
                        using: isPNG ? .png : .jpeg,
                        properties: isPNG ? [:] : [.compressionFactor: 0.9]) else {
                    teardown(); onFinish(nil, area); return
                }

                copyToPasteboard(image: image, data: data, isPNG: isPNG)

                var savedURL: URL?
                switch mode {
                case .copy:
                    break
                case .save:
                    let url = settings.makeScreenshotURL()
                    try data.write(to: url)
                    savedURL = url
                case .saveAs:
                    guard let url = runSavePanel() else {
                        // Dismissing the dialog should not throw the drawing away.
                        finished = false
                        canvasWindow?.orderFrontRegardless()
                        toolbarWindow?.orderFrontRegardless()
                        return
                    }
                    try data.write(to: url)
                    savedURL = url
                }
                teardown()
                onFinish(savedURL, area)
            } catch {
                teardown()
                onFinish(nil, area)
            }
        }
    }

    private func copyToPasteboard(image: NSImage, data: Data, isPNG: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([isPNG ? .png : .tiff, .tiff], owner: nil)
        pasteboard.setData(data, forType: isPNG ? .png : .tiff)
        if let tiff = image.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        pasteboard.writeObjects([image])
    }

    private func runSavePanel() -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [settings.screenshotFormat == .png ? .png : .jpeg]
        panel.directoryURL = settings.outputFolder
        panel.nameFieldStringValue = settings.makeScreenshotURL().lastPathComponent
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    func cancel() {
        guard !finished else { return }
        finished = true
        teardown()
        onFinish(nil, area)
    }

    private func teardown() {
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
        localKeyMonitor = nil
        globalKeyMonitor = nil
        textField?.removeFromSuperview()
        textField = nil
        canvasWindow?.orderOut(nil)
        toolbarWindow?.orderOut(nil)
        canvasWindow = nil
        toolbarWindow = nil
    }

    var windowNumbers: [Int] {
        [canvasWindow?.windowNumber, toolbarWindow?.windowNumber].compactMap { $0 }
    }
}

// MARK: - Toolbar

private struct MarkupToolbar: View {
    @ObservedObject var model: MarkupModel
    @EnvironmentObject var settings: AppSettings

    private var isRussian: Bool { settings.language == .ru }

    /// Tap, not Button: SwiftUI buttons in a floating panel swallow the first click.
    private func iconTap(_ symbol: String, enabled: Bool = true, help: String, action: @escaping () -> Void) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13))
            .foregroundStyle(enabled ? Theme.textSecondary : Theme.textSecondary.opacity(0.35))
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .onTapGesture { if enabled { action() } }
            .help(help)
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 1) {
                ForEach(AnnotationTool.allCases) { tool in
                    Button {
                        model.tool = tool
                        model.onSettingsChanged()
                    } label: {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 13))
                            .frame(width: 26, height: 26)
                            .background(RoundedRectangle(cornerRadius: 5)
                                .fill(model.tool == tool ? Theme.accent.opacity(0.25) : .clear))
                            .foregroundStyle(model.tool == tool ? Theme.accent : Theme.textSecondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(tool.title(settings.language))
                }
            }

            Divider().frame(height: 18)

            HStack(spacing: 4) {
                ForEach(Array(MarkupModel.palette.enumerated()), id: \.offset) { index, color in
                    Button {
                        model.colorIndex = index
                        model.onSettingsChanged()
                    } label: {
                        Circle()
                            .fill(Color(color))
                            .overlay(Circle().strokeBorder(.white.opacity(model.colorIndex == index ? 0.95 : 0.25),
                                                           lineWidth: model.colorIndex == index ? 2 : 1))
                            .frame(width: 16, height: 16)
                            .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 2) {
                ForEach(Array(MarkupModel.widths.enumerated()), id: \.offset) { index, width in
                    Button {
                        model.widthIndex = index
                        model.onSettingsChanged()
                    } label: {
                        Circle()
                            .fill(model.widthIndex == index ? Theme.accent : Theme.textSecondary)
                            .frame(width: width + 3, height: width + 3)
                            .fixedSize()
                            .frame(width: 18, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            iconTap("arrow.uturn.backward", enabled: model.canUndo, help: isRussian ? "Отменить (⌘Z)" : "Undo (⌘Z)") {
                model.onUndo()
            }

            Spacer(minLength: 2)

            iconTap("xmark", help: isRussian ? "Отмена (Esc)" : "Cancel (Esc)") { model.onCancel() }
            iconTap("doc.on.doc", help: isRussian ? "Копировать (⌘C)" : "Copy (⌘C)") { model.onCopy() }
            iconTap("folder.badge.plus", help: isRussian ? "Сохранить в… (⇧⌘S)" : "Save as… (⇧⌘S)") { model.onSaveAs() }

            Text(isRussian ? "Сохранить" : "Save")
                .font(.system(size: 11, weight: .semibold))
                .fixedSize()
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 5).fill(Theme.accent))
                .foregroundStyle(Color.black.opacity(0.85))
                .contentShape(Rectangle())
                .onTapGesture { model.onSave() }
                .help(isRussian ? "Сохранить (⌘S)" : "Save (⌘S)")
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panelBackground))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke))
        .environment(\.colorScheme, .dark)
    }
}
