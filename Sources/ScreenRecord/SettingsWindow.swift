import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(state: AppState) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingView(rootView: SettingsView()
            .environmentObject(state)
            .environmentObject(state.settings))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = state.settings.t("settings")
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Theme.panelBackground)
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

private struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var settings: AppSettings
    @State private var section = 0

    private var sections: [(String, String)] {
        [(settings.t("tabGeneral"), "gearshape"),
         (settings.t("tabVideo"), "video"),
         (settings.t("tabScreenshot"), "camera"),
         (settings.t("tabShortcuts"), "keyboard")]
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(sections.enumerated()), id: \.offset) { index, item in
                    Button {
                        section = index
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: item.1).font(.system(size: 12)).frame(width: 16)
                            Text(item.0).font(.system(size: 12))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(section == index ? Color.white.opacity(0.1) : .clear))
                        .foregroundStyle(section == index ? Theme.accent : Theme.textPrimary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(8)
            .frame(width: 168)
            .background(Theme.fieldBackground)

            Divider()

            Group {
                switch section {
                case 1: VideoTab()
                case 2: ScreenshotTab()
                case 3: ShortcutsTab()
                default: GeneralTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 560, height: 440)
        .background(Theme.panelBackground)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var settings: AppSettings
    @State private var launchesAtLogin = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(settings.t("folder"))
                    Spacer()
                    Text(shortPath).foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.middle)
                    Button(settings.t("change")) { state.chooseOutputFolder() }
                }
                Toggle(settings.t("revealVideo"), isOn: Binding(
                    get: { settings.revealAfterRecording },
                    set: { settings.revealAfterRecording = $0 }))
                Toggle(settings.t("revealShot"), isOn: Binding(
                    get: { settings.revealAfterScreenshot },
                    set: { settings.revealAfterScreenshot = $0 }))
            }
            Section {
                Picker(settings.t("language"), selection: Binding(
                    get: { settings.language },
                    set: { settings.language = $0 })) {
                    ForEach(Language.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle(settings.t("launchAtLogin"), isOn: $launchesAtLogin)
                    .onChange(of: launchesAtLogin) { _, value in settings.launchesAtLogin = value }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchesAtLogin = settings.launchesAtLogin }
    }

    private var shortPath: String {
        settings.outputFolder.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}

// MARK: - Video

private struct VideoTab: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker(settings.t("resolutionTitle"), selection: Binding(
                    get: { settings.resolution }, set: { settings.resolution = $0 })) {
                    ForEach(ResolutionPreset.allCases) { Text($0.title(settings.language)).tag($0) }
                }
                Picker(settings.t("fpsTitle"), selection: Binding(
                    get: { settings.frameRate }, set: { settings.frameRate = $0 })) {
                    ForEach(FrameRate.allCases) { Text($0.title).tag($0) }
                }
                Picker(settings.t("quality"), selection: Binding(
                    get: { settings.quality }, set: { settings.quality = $0 })) {
                    ForEach(VideoQuality.allCases) { Text($0.title(settings.language)).tag($0) }
                }
                Picker(settings.t("codec"), selection: Binding(
                    get: { settings.codec }, set: { settings.codec = $0 })) {
                    ForEach(VideoCodec.allCases) { Text($0.title).tag($0) }
                }
            }
            Section {
                Toggle(settings.t("systemAudio"), isOn: Binding(
                    get: { settings.systemAudioEnabled }, set: { settings.systemAudioEnabled = $0 }))
                Toggle(settings.t("microphone"), isOn: Binding(
                    get: { settings.microphoneEnabled }, set: { state.setMicrophoneEnabled($0) }))
                    .disabled(state.microphones.isEmpty)
                Picker(settings.t("micDevice"), selection: Binding(
                    get: { settings.microphoneDeviceID ?? "" },
                    set: { settings.microphoneDeviceID = $0 })) {
                    ForEach(state.microphones) { Text($0.name).tag($0.id) }
                }
                .disabled(state.microphones.isEmpty)
            }
            Section {
                Toggle(settings.t("mouseCursor"), isOn: Binding(
                    get: { settings.showsCursor }, set: { settings.showsCursor = $0 }))
                Toggle(settings.t("keyEvents"), isOn: Binding(
                    get: { settings.showsKeystrokes }, set: { settings.showsKeystrokes = $0 }))
                Picker(settings.t("delay"), selection: Binding(
                    get: { settings.countdown }, set: { settings.countdown = $0 })) {
                    Text(settings.t("noDelay")).tag(0)
                    ForEach([3, 5, 10], id: \.self) { Text("\($0) \(settings.t("seconds"))").tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Screenshot

private struct ScreenshotTab: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker(settings.t("format"), selection: Binding(
                    get: { settings.screenshotFormat }, set: { settings.screenshotFormat = $0 })) {
                    ForEach(ScreenshotFormat.allCases) { Text($0.title).tag($0) }
                }
            }
            Section {
                Text(settings.t("markupHint"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcuts

private struct ShortcutsTab: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                ShortcutRow(title: settings.t("hotkeyRecord"), shortcut: Binding(
                    get: { settings.recordShortcut }, set: { settings.recordShortcut = $0 }))
                ShortcutRow(title: settings.t("hotkeyScreenshot"), shortcut: Binding(
                    get: { settings.screenshotShortcut }, set: { settings.screenshotShortcut = $0 }))
            }
            Section {
                Text(settings.t("shortcutHint"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Click to record, then press the desired combination.
private struct ShortcutRow: View {
    let title: String
    @Binding var shortcut: Shortcut
    @EnvironmentObject var settings: AppSettings
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button {
                recording ? stopRecording() : startRecording()
            } label: {
                Text(recording ? settings.t("pressKeys") : shortcut.display)
                    .font(.system(size: 12, weight: .medium))
                    .frame(minWidth: 96)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 5)
                        .fill(recording ? Theme.accent.opacity(0.25) : Theme.fieldBackground))
                    .foregroundStyle(recording ? Theme.accent : Theme.textPrimary)
            }
            .buttonStyle(.plain)
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            let candidate = Shortcut(keyCode: Int(event.keyCode),
                                     modifiers: event.modifierFlags.intersection([.command, .shift, .option, .control]))
            guard candidate.isValid else { return nil }
            shortcut = candidate
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}
