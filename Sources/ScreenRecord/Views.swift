import SwiftUI
import ScreenCaptureKit

struct RootView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        ZStack {
            Theme.panelBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                TopBar()
                Group {
                    switch state.route {
                    case .home: HomeView()
                    case .displayPicker: DisplayPickerView()
                    case .recordBar: RecordBarView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: state.route)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Top bar

private struct TopBar: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 2) {
            Spacer()
            Button {
                state.chooseOutputFolder()
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(IconButtonStyle())
            .help(settings.t("chooseFolder"))

            Menu {
                ForEach(Language.allCases, id: \.self) { language in
                    Button {
                        settings.language = language
                    } label: {
                        Text(language.title + (settings.language == language ? "  ✓" : ""))
                    }
                }
            } label: {
                Image(systemName: "globe")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26)
            .foregroundStyle(Theme.textSecondary)

            Button {
                SettingsWindowController.shared.show(state: state)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(IconButtonStyle())
            .help(settings.t("settings"))
        }
        .padding(.trailing, 8)
        .frame(height: 28)
    }
}

// MARK: - Home

private struct HomeView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 4) {
            IntentSwitch()
            HStack(spacing: 0) {
                ModeButton(icon: "display", title: settings.t("screen")) {
                    state.intent == .screenshot ? state.screenshotDisplay() : state.chooseFullScreen()
                }
                ModeButton(icon: "rectangle.dashed", title: settings.t("area")) {
                    state.intent == .screenshot ? state.screenshotArea() : state.chooseArea()
                }
                ModeButton(icon: "macwindow", title: settings.t("window")) {
                    state.intent == .screenshot ? state.screenshotWindow() : state.chooseWindow()
                }
            }
        }
        .padding(.bottom, 12)
    }
}

/// Segmented switch that decides whether the buttons below record or capture.
private struct IntentSwitch: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 3) {
            item(.screenshot, symbol: "camera", title: settings.t("screenshotMode"),
                 shortcut: settings.screenshotShortcut.display)
            item(.video, symbol: "video", title: settings.t("video"),
                 shortcut: settings.recordShortcut.display)
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.fieldBackground))
    }

    private func item(_ intent: CaptureIntent, symbol: String, title: String, shortcut: String) -> some View {
        Button {
            state.intent = intent
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11))
                Text(title).font(.system(size: 11, weight: .medium))
                Text(shortcut).font(.system(size: 9)).foregroundStyle(Theme.textSecondary)
            }
            .foregroundStyle(state.intent == intent ? Theme.accent : Theme.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(state.intent == intent ? Color.white.opacity(0.08) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ModeButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .light))
                Text(title)
                    .font(.system(size: 11))
            }
            .foregroundStyle(hovering ? Theme.accent : Theme.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hovering ? Color.white.opacity(0.06) : .clear)
                    .padding(6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct DisplayPickerView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ForEach(Array(state.displays.enumerated()), id: \.offset) { index, display in
                    Button {
                        state.select(display: display)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "display")
                                .font(.system(size: 20, weight: .light))
                            Text("\(settings.t("displayN")) \(index + 1)")
                                .font(.system(size: 11))
                            Text("\(display.width)×\(display.height)")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 110, height: 78)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.rowBackground))
                    }
                    .buttonStyle(.plain)
                }
            }
            Button(settings.t("back")) { state.goHome() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.bottom, 10)
    }
}
