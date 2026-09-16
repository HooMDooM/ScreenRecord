import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI

struct MicrophoneDevice: Identifiable, Hashable {
    let id: String
    let name: String
}

enum CaptureMode {
    case fullDisplay, area, window
}

enum CaptureIntent {
    case screenshot, video
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Route {
        case home, displayPicker, recordBar
    }

    let settings = AppSettings.shared
    let recorder = Recorder()

    private let selectionOverlay = SelectionOverlayController()
    private let windowPicker = WindowPickerController()
    private let keystrokes = KeystrokeOverlayController()
    private let countdown = CountdownController()

    @Published var route: Route = .home
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var isCountingDown = false
    @Published var elapsed: TimeInterval = 0
    @Published var captureSize: CGSize = .zero
    @Published var mode: CaptureMode = .fullDisplay
    @Published var intent: CaptureIntent = .screenshot
    @Published var displays: [SCDisplay] = []
    @Published var microphones: [MicrophoneDevice] = []
    @Published var lastRecordingURL: URL?

    private var target: CaptureTarget?
    private var targetScreenFrame: CGRect?
    private var timer: Timer?
    private var markupSession: MarkupSession?

    var panel: PanelController?

    private init() {
        recorder.onError = { [weak self] error in
            self?.presentError(error)
            Task { await self?.stopRecording() }
        }
    }

    // MARK: - Panel routing

    func showPanel() {
        refreshMicrophones()
        panel?.present(route: route, anchor: anchorRect())
    }

    func togglePanel() {
        if panel?.isVisible == true, !isRecording {
            panel?.hide()
        } else {
            showPanel()
        }
    }

    func goHome() {
        guard !isRecording else { return }
        resetTransientUI()
        target = nil
        route = .home
        panel?.present(route: .home, anchor: nil)
    }

    /// Closes any overlay from a previous action so flows never stack up
    /// (e.g. pressing the screenshot hotkey twice).
    private func resetTransientUI() {
        selectionOverlay.dismiss()
        windowPicker.dismiss()
        markupSession?.cancel()
        markupSession = nil
    }

    /// Fast synchronous check so overlays can appear immediately; the slow
    /// `SCShareableContent` query runs afterwards in the background.
    private func ensureScreenAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        CGRequestScreenCaptureAccess()
        if CGPreflightScreenCaptureAccess() { return true }
        presentPermissionAlert()
        return false
    }

    private func display(for screen: NSScreen) async -> SCDisplay? {
        if displays.isEmpty { _ = await fetchContent() }
        return displayMatching(screen: screen)
    }

    private func anchorRect() -> CGRect? {
        if mode == .area, !selectionOverlay.globalSelection.isEmpty {
            return selectionOverlay.globalSelection
        }
        return nil
    }

    // MARK: - Mode selection

    func chooseFullScreen() {
        resetTransientUI()
        Task {
            guard let content = await fetchContent() else { return }
            displays = content.displays
            if content.displays.count == 1, let display = content.displays.first {
                select(display: display)
            } else {
                route = .displayPicker
                panel?.present(route: .displayPicker, anchor: nil)
            }
        }
    }

    func select(display: SCDisplay) {
        selectionOverlay.dismiss()
        mode = .fullDisplay
        target = .display(display, rect: nil)
        captureSize = CGSize(width: display.width, height: display.height)
        targetScreenFrame = screenFrame(for: display)
        route = .recordBar
        panel?.present(route: .recordBar, anchor: nil)
    }

    func chooseArea() {
        guard ensureScreenAccess() else { return }
        resetTransientUI()
        mode = .area
        intent = .video
        panel?.hide()
        selectionOverlay.onChange = { [weak self] rect in
            guard let self else { return }
            self.captureSize = rect.size
        }
        selectionOverlay.onCommit = { [weak self] _, rect in
            guard let self else { return }
            self.captureSize = rect.size
            self.settings.lastArea = rect
            self.selectionOverlay.enterAdjustMode()
            self.route = .recordBar
            self.panel?.present(route: .recordBar, anchor: rect)
        }
        selectionOverlay.onCancel = { [weak self] in
            self?.selectionOverlay.dismiss()
            self?.goHome()
            self?.showPanel()
        }
        selectionOverlay.present(hint: settings.t("selectArea"), initial: settings.lastArea)
        Task { _ = await fetchContent() }
    }

    func chooseWindow() {
        resetTransientUI()
        Task {
            guard let content = await fetchContent() else { return }
            mode = .window
            panel?.hide()
            windowPicker.onPick = { [weak self] window in
                guard let self else { return }
                self.windowPicker.dismiss()
                self.target = .window(window)
                self.captureSize = window.frame.size
                self.targetScreenFrame = ScreenGeometry.cocoaRect(fromCG: window.frame)
                self.route = .recordBar
                self.panel?.present(route: .recordBar, anchor: nil)
            }
            windowPicker.onCancel = { [weak self] in
                self?.windowPicker.dismiss()
                self?.goHome()
                self?.showPanel()
            }
            windowPicker.present(windows: content.windows, hint: settings.t("selectWindow"))
        }
    }

    // MARK: - Screenshots

    /// Area screenshot: drag a region, the shot is taken as soon as it is released.
    func screenshotArea() {
        guard ensureScreenAccess() else { return }
        resetTransientUI()
        mode = .area
        intent = .screenshot
        panel?.hide()
        selectionOverlay.onChange = { _ in }
        selectionOverlay.onCommit = { [weak self] screen, rect in
            guard let self else { return }
            self.selectionOverlay.dismiss()
            Task {
                guard let display = await self.display(for: screen) else { return }
                self.beginMarkup(source: .display(display, screen), area: rect)
            }
        }
        selectionOverlay.onCancel = { [weak self] in
            self?.selectionOverlay.dismiss()
            self?.goHome()
        }
        // Screenshots always start from a blank selection; only video reuses the last area.
        selectionOverlay.present(hint: settings.t("selectAreaShot"), initial: nil)
        Task { _ = await fetchContent() }
    }

    func screenshotWindow() {
        resetTransientUI()
        Task {
            guard let content = await fetchContent() else { return }
            mode = .window
            panel?.hide()
            windowPicker.onPick = { [weak self] window in
                guard let self else { return }
                self.windowPicker.dismiss()
                self.beginMarkup(source: .window(window),
                                 area: ScreenGeometry.cocoaRect(fromCG: window.frame))
            }
            windowPicker.onCancel = { [weak self] in
                self?.windowPicker.dismiss()
                self?.goHome()
            }
            windowPicker.present(windows: content.windows, hint: settings.t("selectWindowShot"))
        }
    }

    func screenshotDisplay() {
        resetTransientUI()
        Task {
            guard let content = await fetchContent() else { return }
            let display = content.displays.first { $0.displayID == mainDisplayID } ?? content.displays.first
            guard let display else { return }
            mode = .fullDisplay
            panel?.hide()
            guard let frame = screenFrame(for: display),
                  let screen = NSScreen.screens.first(where: { $0.frame == frame }) else { return }
            beginMarkup(source: .display(display, screen), area: frame)
        }
    }

    func setSelectionSize(width: CGFloat, height: CGFloat) {
        guard mode == .area else { return }
        selectionOverlay.setSize(width: width, height: height)
        captureSize = selectionOverlay.globalSelection.size
    }

    // MARK: - Recording

    func startRecording() {
        guard !isRecording, !isCountingDown else { return }
        Task {
            if mode == .area {
                if displays.isEmpty { _ = await fetchContent() }
                guard let areaTarget = areaTarget() else {
                    presentError(RecorderError.writerFailed(settings.t("noAreaSelected")))
                    return
                }
                target = areaTarget
                selectionOverlay.enterRecordingMode()
            }
            guard target != nil else { return }

            if settings.showsKeystrokes, !KeystrokeOverlayController.hasAccessibilityPermission(prompt: true) {
                presentAccessibilityAlert()
            }

            isCountingDown = settings.countdown > 0
            panel?.hide()
            countdown.run(seconds: settings.countdown, near: targetScreenFrame) { [weak self] in
                self?.isCountingDown = false
                self?.beginCapture()
            }
        }
    }

    /// Stops a pending countdown and returns the UI to the setup state.
    func cancelCountdown() {
        guard isCountingDown else { return }
        countdown.cancel()
        isCountingDown = false
        if mode == .area { selectionOverlay.enterAdjustMode() }
        showPanel()
    }

    /// Microphone capture needs an explicit grant; fall back to no mic instead
    /// of letting the stream fail to start.
    private func microphoneAllowed() async -> Bool {
        guard settings.microphoneEnabled else { return false }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    private func areaTarget() -> CaptureTarget? {
        let selection = selectionOverlay.globalSelection
        guard !selection.isEmpty,
              let screen = selectionOverlay.activeScreen,
              let display = displayMatching(screen: screen) else { return nil }
        targetScreenFrame = selection
        let localRect = CGRect(x: selection.minX - screen.frame.minX,
                               y: screen.frame.maxY - selection.maxY,
                               width: selection.width, height: selection.height)
        return .display(display, rect: localRect)
    }

    private func beginCapture() {
        guard let target else { return }
        Task {
            if settings.showsKeystrokes, KeystrokeOverlayController.hasAccessibilityPermission(prompt: false) {
                keystrokes.start(in: targetScreenFrame ?? NSScreen.main?.frame ?? .zero)
            }
            let useMicrophone = await microphoneAllowed()
            guard let content = await fetchContent() else {
                keystrokes.stop()
                showPanel()
                return
            }
            Recorder.cachedContent = content

            // Window numbers can be negative or out of range for internal
            // AppKit windows, while CGWindowID is a UInt32.
            var excluded = Set(NSApp.windows.compactMap { CGWindowID(exactly: $0.windowNumber) })
            if let keystrokeWindow = keystrokes.windowNumber {
                excluded.remove(CGWindowID(keystrokeWindow))
            }

            let options = RecorderOptions(
                frameRate: settings.frameRate.rawValue,
                resolution: settings.resolution,
                quality: settings.quality,
                codec: settings.codec,
                showsCursor: settings.showsCursor,
                systemAudio: settings.systemAudioEnabled,
                microphone: useMicrophone,
                microphoneDeviceID: settings.microphoneDeviceID,
                excludedWindowIDs: excluded,
                outputURL: settings.makeOutputURL())

            do {
                try await recorder.start(target: target, options: options)
                isRecording = true
                isPaused = false
                startTimer()
            } catch {
                keystrokes.stop()
                if mode == .area { selectionOverlay.enterAdjustMode() }
                presentError(error)
                showPanel()
            }
        }
    }

    enum MarkupSource {
        /// Resizable: the region is re-derived from the screen on every capture.
        case display(SCDisplay, NSScreen)
        case window(SCWindow)
    }

    /// Opens the markup layer over the chosen region. The capture itself only
    /// happens when the user saves or copies, using whatever region is current.
    private func beginMarkup(source: MarkupSource, area: CGRect) {
        let resizable: Bool
        if case .display = source { resizable = true } else { resizable = false }

        let session = MarkupSession(area: area, allowsResize: resizable) { [weak self] rect in
            guard let self else { throw RecorderError.writerFailed("Session gone") }
            switch source {
            case .display(let display, let screen):
                let localRect = CGRect(x: rect.minX - screen.frame.minX,
                                       y: screen.frame.maxY - rect.maxY,
                                       width: rect.width, height: rect.height)
                return try await self.captureImage(of: .display(display, rect: localRect))
            case .window(let window):
                return try await self.captureImage(of: .window(window))
            }
        } onFinish: { [weak self] url, finalArea in
            guard let self else { return }
            self.markupSession = nil
            self.route = .home
            if let url {
                self.lastRecordingURL = url
                FlashOverlay.show(in: finalArea)
                if self.settings.revealAfterScreenshot {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
        markupSession = session
        session.begin()
    }

    private func captureImage(of target: CaptureTarget) async throws -> CGImage {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
            throw RecorderError.noPermission
        }
        Recorder.cachedContent = content
        let options = RecorderOptions(
            frameRate: settings.frameRate.rawValue,
            resolution: .original,
            showsCursor: false,
            systemAudio: false,
            microphone: false,
            microphoneDeviceID: nil,
            excludedWindowIDs: Set(NSApp.windows.compactMap { CGWindowID(exactly: $0.windowNumber) }),
            outputURL: settings.makeScreenshotURL())
        return try await recorder.captureImage(target: target, options: options)
    }

    private var mainDisplayID: CGDirectDisplayID? {
        (NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    func togglePause() {
        guard isRecording else { return }
        isPaused.toggle()
        recorder.setPaused(isPaused)
    }

    func stopRecording() async {
        if isCountingDown {
            cancelCountdown()
            return
        }
        guard isRecording else { return }
        isRecording = false
        isPaused = false
        stopTimer()
        keystrokes.stop()
        let url = await recorder.stop()
        selectionOverlay.dismiss()
        elapsed = 0
        target = nil
        route = .home

        guard let url else {
            // Never let a recording vanish silently.
            presentError(RecorderError.writerFailed(settings.t("recordingFailed")))
            showPanel()
            return
        }
        lastRecordingURL = url
        if settings.revealAfterRecording {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            showPanel()
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.elapsed = self.recorder.elapsed
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Helpers

    func revealLastRecording() {
        guard let url = lastRecordingURL else {
            NSWorkspace.shared.open(settings.outputFolder)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func chooseOutputFolder() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.canCreateDirectories = true
        openPanel.directoryURL = settings.outputFolder
        openPanel.prompt = settings.t("chooseFolder")
        NSApp.activate(ignoringOtherApps: true)
        if openPanel.runModal() == .OK, let url = openPanel.url {
            settings.outputFolder = url
        }
    }

    func setMicrophoneEnabled(_ enabled: Bool) {
        settings.microphoneEnabled = enabled
        guard enabled else { return }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in self?.refreshMicrophones() }
        }
    }

    func refreshMicrophones() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio, position: .unspecified)
        microphones = session.devices.map { MicrophoneDevice(id: $0.uniqueID, name: $0.localizedName) }
        if settings.microphoneDeviceID == nil || !microphones.contains(where: { $0.id == settings.microphoneDeviceID }) {
            settings.microphoneDeviceID = microphones.first?.id
        }
    }

    private func displayMatching(screen: NSScreen) -> SCDisplay? {
        let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        return displays.first { $0.displayID == number } ?? displays.first
    }

    private func screenFrame(for display: SCDisplay) -> CGRect? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID
        }?.frame
    }

    private func fetchContent() async -> SCShareableContent? {
        // Triggers the system prompt on first launch instead of failing silently.
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            guard CGPreflightScreenCaptureAccess() else {
                presentPermissionAlert()
                return nil
            }
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            displays = content.displays
            return content
        } catch {
            presentPermissionAlert()
            return nil
        }
    }

    // MARK: - Alerts

    private func presentPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = settings.t("permissionTitle")
        alert.informativeText = settings.t("permissionBody")
        alert.addButton(withTitle: settings.t("openSettings"))
        alert.addButton(withTitle: settings.t("cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func presentAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = settings.t("accessibilityTitle")
        alert.informativeText = settings.t("accessibilityBody")
        alert.addButton(withTitle: settings.t("openSettings"))
        alert.addButton(withTitle: settings.t("cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func presentError(_ error: Error) {
        NSLog("ScreenRecord error: \(error)")
        let alert = NSAlert()
        alert.messageText = settings.t("error")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: settings.t("ok"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
