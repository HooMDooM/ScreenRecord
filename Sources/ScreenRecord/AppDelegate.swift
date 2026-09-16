import AppKit
import Combine
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    /// Shown next to the timer only while a recording is in progress.
    private var pauseItem: NSStatusItem?
    private let state = AppState.shared
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.panel = PanelController(state: state)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenRecord")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        state.$elapsed
            .combineLatest(state.$isRecording, state.$isPaused)
            .sink { [weak self] elapsed, isRecording, isPaused in
                self?.updateStatusItem(elapsed: elapsed, isRecording: isRecording, isPaused: isPaused)
            }
            .store(in: &cancellables)

        state.refreshMicrophones()
        registerHotKeys()
        state.showPanel()
    }

    private func updateStatusItem(elapsed: TimeInterval, isRecording: Bool, isPaused: Bool) {
        guard let button = statusItem.button else { return }
        if isRecording {
            let total = Int(elapsed)
            button.title = String(format: " %02d:%02d", total / 60, total % 60)
            button.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Stop")
            button.toolTip = state.settings.t("stopRecording")
            showPauseItem(isPaused: isPaused)
        } else {
            button.title = ""
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenRecord")
            button.toolTip = nil
            hidePauseItem()
        }
        button.image?.isTemplate = true
    }

    private func showPauseItem(isPaused: Bool) {
        let item = pauseItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        pauseItem = item
        guard let button = item.button else { return }
        button.image = NSImage(systemSymbolName: isPaused ? "play.fill" : "pause.fill",
                               accessibilityDescription: "Pause")
        button.image?.isTemplate = true
        button.toolTip = state.settings.t(isPaused ? "resume" : "pause")
        button.target = self
        button.action = #selector(togglePause)
    }

    private func hidePauseItem() {
        guard let pauseItem else { return }
        NSStatusBar.system.removeStatusItem(pauseItem)
        self.pauseItem = nil
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else if state.isRecording || state.isCountingDown {
            Task { await state.stopRecording() }
        } else {
            state.togglePanel()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let settings = state.settings

        menu.addItem(withTitle: settings.t("show"), action: #selector(showPanel), keyEquivalent: "")
        if state.isRecording {
            menu.addItem(withTitle: settings.t(state.isPaused ? "resume" : "pause"),
                         action: #selector(togglePause), keyEquivalent: "")
            menu.addItem(withTitle: settings.t("stopRecording"), action: #selector(stopRecording), keyEquivalent: "")
        }
        menu.addItem(.separator())
        addShortcutItem(to: menu, title: settings.t("screenshotArea"), action: #selector(screenshotArea),
                        shortcut: settings.screenshotShortcut)
        menu.addItem(withTitle: settings.t("screenshotWindow"), action: #selector(screenshotWindow), keyEquivalent: "")
        menu.addItem(withTitle: settings.t("screenshotScreen"), action: #selector(screenshotDisplay), keyEquivalent: "")
        if !state.isRecording {
            menu.addItem(.separator())
            addShortcutItem(to: menu, title: settings.t("recordArea"), action: #selector(recordArea),
                            shortcut: settings.recordShortcut)
            menu.addItem(withTitle: settings.t("recordWindow"), action: #selector(recordWindow), keyEquivalent: "")
            menu.addItem(withTitle: settings.t("recordScreen"), action: #selector(recordDisplay), keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: settings.t("openFolder"), action: #selector(openFolder), keyEquivalent: "")
        addItem(to: menu, title: settings.t("settings") + "…", action: #selector(openSettings),
                key: ",", modifiers: [.command])
        menu.addItem(.separator())
        menu.addItem(withTitle: settings.t("quit"), action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func addShortcutItem(to menu: NSMenu, title: String, action: Selector, shortcut: Shortcut) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: "\(title)   \(shortcut.display)")
        menu.addItem(item)
    }

    private func addItem(to menu: NSMenu, title: String, action: Selector,
                         key: String, modifiers: NSEvent.ModifierFlags) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        menu.addItem(item)
    }

    @objc private func showPanel() { state.showPanel() }
    @objc private func togglePause() { state.togglePause() }
    @objc private func stopRecording() { Task { await state.stopRecording() } }
    @objc private func screenshotArea() { state.screenshotArea() }
    @objc private func screenshotWindow() { state.screenshotWindow() }
    @objc private func screenshotDisplay() { state.screenshotDisplay() }
    @objc private func recordArea() { state.chooseArea() }
    @objc private func recordWindow() { state.chooseWindow() }
    @objc private func recordDisplay() { state.chooseFullScreen() }
    @objc private func openFolder() { state.revealLastRecording() }
    @objc private func openSettings() { SettingsWindowController.shared.show(state: state) }
    @objc private func quit() {
        Task {
            await state.stopRecording()
            NSApp.terminate(nil)
        }
    }

    // MARK: - Global hotkeys

    private func registerHotKeys() {
        let manager = HotKeyManager.shared
        manager.onTrigger = { action in
            let state = AppState.shared
            switch action {
            case .record:
                if state.isRecording || state.isCountingDown {
                    Task { await state.stopRecording() }
                } else if state.route == .recordBar {
                    state.startRecording()
                } else {
                    state.chooseArea()
                }
            case .screenshot:
                state.screenshotArea()
            }
        }
        manager.apply(state.settings.recordShortcut, to: .record)
        manager.apply(state.settings.screenshotShortcut, to: .screenshot)

        state.settings.$recordShortcut
            .dropFirst()
            .sink { manager.apply($0, to: .record) }
            .store(in: &cancellables)
        state.settings.$screenshotShortcut
            .dropFirst()
            .sink { manager.apply($0, to: .screenshot) }
            .store(in: &cancellables)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard state.isRecording else { return .terminateNow }
        Task {
            await state.stopRecording()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

