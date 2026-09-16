import SwiftUI

struct RecordBarView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var settings: AppSettings
    @State private var widthText = ""
    @State private var heightText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                leftColumn
                rightColumn
            }
            .padding(.horizontal, 14)
            Spacer(minLength: 6)
            folderRow
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
        .onAppear(perform: syncSizeFields)
        .onChange(of: state.captureSize) { _, _ in syncSizeFields() }
    }

    // MARK: - Left column

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 7) {
            sizeRow
            microphoneRow
            systemAudioRow
            toggleRow(icon: "cursorarrow.motionlines",
                      title: settings.t("mouseCursor"),
                      isOn: Binding(get: { settings.showsCursor }, set: { settings.showsCursor = $0 }))
            toggleRow(icon: "keyboard",
                      title: settings.t("keyEvents"),
                      isOn: Binding(get: { settings.showsKeystrokes }, set: { settings.showsKeystrokes = $0 }))
        }
        .frame(width: 300)
    }

    private var sizeRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.inset.filled")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 18)
            DarkField {
                HStack(spacing: 4) {
                    Text("W:").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    TextField("", text: $widthText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textPrimary)
                        .disabled(state.mode != .area || state.isRecording)
                        .onSubmit(applySizeFields)
                }
            }
            .frame(width: 108)
            Text("x").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            DarkField {
                HStack(spacing: 4) {
                    Text("H:").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    TextField("", text: $heightText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textPrimary)
                        .disabled(state.mode != .area || state.isRecording)
                        .onSubmit(applySizeFields)
                }
            }
            .frame(width: 108)
        }
    }

    private var microphoneRow: some View {
        HStack(spacing: 6) {
            Image(systemName: settings.microphoneEnabled ? "mic" : "mic.slash")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 18)
            DarkField {
                Menu {
                    ForEach(state.microphones) { device in
                        Button(device.name) { settings.microphoneDeviceID = device.id }
                    }
                } label: {
                    Text(selectedMicrophoneName)
                        .font(.system(size: 11))
                        .foregroundStyle(settings.microphoneEnabled ? Theme.textPrimary : Theme.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(state.microphones.isEmpty)
            }
            .frame(maxWidth: .infinity)
            AccentToggle(isOn: Binding(get: { settings.microphoneEnabled },
                                       set: { state.setMicrophoneEnabled($0) }))
            .disabled(state.isRecording || state.microphones.isEmpty)
            .opacity(state.microphones.isEmpty ? 0.35 : 1)
        }
    }

    private var systemAudioRow: some View {
        HStack(spacing: 6) {
            Image(systemName: settings.systemAudioEnabled ? "speaker.wave.2" : "speaker.slash")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 18)
            DarkField {
                Text(settings.t("systemAudio"))
                    .font(.system(size: 11))
                    .foregroundStyle(settings.systemAudioEnabled ? Theme.textPrimary : Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            AccentToggle(isOn: Binding(get: { settings.systemAudioEnabled },
                                       set: { settings.systemAudioEnabled = $0 }))
            .disabled(state.isRecording)
        }
    }

    private func toggleRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 18)
            DarkField {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(isOn.wrappedValue ? Theme.textPrimary : Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            AccentToggle(isOn: isOn)
                .disabled(state.isRecording)
        }
    }

    // MARK: - Right column

    private var rightColumn: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if state.isRecording {
                    Button { state.togglePause() } label: {
                        Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Theme.rowBackground))
                    }
                    .buttonStyle(.plain)
                    .help(settings.t(state.isPaused ? "resume" : "pause"))
                }
                recordButton
                if !state.isRecording {
                    countdownMenu
                }
            }
            HStack(spacing: 8) {
                pickerField(title: settings.resolution.title(settings.language)) {
                    ForEach(ResolutionPreset.allCases) { preset in
                        Button(preset.title(settings.language)) { settings.resolution = preset }
                    }
                }
                pickerField(title: settings.frameRate.title) {
                    ForEach(FrameRate.allCases) { rate in
                        Button(rate.title) { settings.frameRate = rate }
                    }
                }
            }
            .disabled(state.isRecording)
        }
        .frame(width: 182)
    }

    private var recordButton: some View {
        Button {
            if state.isRecording {
                Task { await state.stopRecording() }
            } else {
                state.startRecording()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Theme.recRed.opacity(state.isRecording ? 0.9 : 1))
                    .frame(width: 62, height: 62)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 3).padding(2))
                if state.isRecording {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                } else {
                    Text(settings.t("rec"))
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Color.white)
                }
            }
            .overlay(alignment: .bottom) {
                if state.isRecording {
                    Text(timeString)
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                        .offset(y: 16)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(state.isCountingDown)
    }

    private var countdownMenu: some View {
        DarkField {
            Menu {
                Button(settings.t("noDelay")) { settings.countdown = 0 }
                ForEach([3, 5, 10], id: \.self) { seconds in
                    Button("\(seconds) \(settings.t("seconds"))") { settings.countdown = seconds }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "timer").font(.system(size: 11))
                    Text(settings.countdown == 0 ? "—" : "\(settings.countdown)")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Theme.textPrimary)
                .fixedSize()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .frame(width: 56)
        .help(settings.t("delay"))
    }

    private func pickerField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        let menuContent = content()
        return DarkField {
            Menu {
                menuContent
            } label: {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
        }
        .frame(width: 87)
    }

    // MARK: - Footer

    private var folderRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            Text(settings.outputFolder.path.replacingOccurrences(
                of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Button(settings.t("chooseFolder")) { state.chooseOutputFolder() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent)
            Button(settings.t("back")) { state.goHome() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .opacity(state.isRecording ? 0.3 : 1)
                .disabled(state.isRecording)
        }
    }

    // MARK: - Helpers

    private var selectedMicrophoneName: String {
        guard !state.microphones.isEmpty else { return settings.t("noDevice") }
        return state.microphones.first { $0.id == settings.microphoneDeviceID }?.name
            ?? state.microphones[0].name
    }

    private var timeString: String {
        let total = Int(state.elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func syncSizeFields() {
        widthText = String(Int(state.captureSize.width.rounded()))
        heightText = String(Int(state.captureSize.height.rounded()))
    }

    private func applySizeFields() {
        guard let width = Double(widthText), let height = Double(heightText) else {
            syncSizeFields()
            return
        }
        state.setSelectionSize(width: CGFloat(max(40, width)), height: CGFloat(max(40, height)))
        syncSizeFields()
    }
}
