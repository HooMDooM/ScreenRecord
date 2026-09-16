import Foundation
import SwiftUI
import AppKit
import Carbon.HIToolbox
import ServiceManagement

enum ResolutionPreset: Int, CaseIterable, Identifiable {
    case original = 0
    case p720 = 720
    case p1080 = 1080
    case p1440 = 1440
    case p2160 = 2160

    var id: Int { rawValue }

    func title(_ lang: Language) -> String {
        switch self {
        case .original: return L.t("original", lang)
        case .p720: return "720P"
        case .p1080: return "1080P"
        case .p1440: return "1440P"
        case .p2160: return "4K"
        }
    }
}

enum FrameRate: Int, CaseIterable, Identifiable {
    case fps15 = 15, fps24 = 24, fps30 = 30, fps60 = 60
    var id: Int { rawValue }
    var title: String { "\(rawValue)FPS" }
}

enum VideoQuality: Int, CaseIterable, Identifiable {
    case low = 0, medium = 1, high = 2

    var id: Int { rawValue }
    /// Bits per pixel per frame used to derive the encoder bitrate.
    var bitsPerPixel: Double {
        switch self {
        case .low: return 0.06
        case .medium: return 0.11
        case .high: return 0.20
        }
    }

    func title(_ lang: Language) -> String {
        switch self {
        case .low: return lang == .ru ? "Низкое" : "Low"
        case .medium: return lang == .ru ? "Среднее" : "Medium"
        case .high: return lang == .ru ? "Высокое" : "High"
        }
    }
}

enum VideoCodec: Int, CaseIterable, Identifiable {
    case h264 = 0, hevc = 1
    var id: Int { rawValue }
    var title: String { self == .h264 ? "H.264" : "HEVC" }
}

enum ScreenshotFormat: Int, CaseIterable, Identifiable {
    case png = 0, jpeg = 1
    var id: Int { rawValue }
    var title: String { self == .png ? "PNG" : "JPEG" }
    var fileExtension: String { self == .png ? "png" : "jpg" }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let d = UserDefaults.standard

    @Published var language: Language { didSet { d.set(language.rawValue, forKey: "language") } }
    @Published var frameRate: FrameRate { didSet { d.set(frameRate.rawValue, forKey: "fps") } }
    @Published var resolution: ResolutionPreset { didSet { d.set(resolution.rawValue, forKey: "resolution") } }
    @Published var microphoneEnabled: Bool { didSet { d.set(microphoneEnabled, forKey: "micEnabled") } }
    @Published var microphoneDeviceID: String? { didSet { d.set(microphoneDeviceID, forKey: "micDevice") } }
    @Published var systemAudioEnabled: Bool { didSet { d.set(systemAudioEnabled, forKey: "sysAudio") } }
    @Published var showsCursor: Bool { didSet { d.set(showsCursor, forKey: "showsCursor") } }
    @Published var highlightClicks: Bool { didSet { d.set(highlightClicks, forKey: "highlightClicks") } }
    @Published var showsKeystrokes: Bool { didSet { d.set(showsKeystrokes, forKey: "keystrokes") } }
    @Published var countdown: Int { didSet { d.set(countdown, forKey: "countdown") } }
    @Published var outputFolder: URL { didSet { d.set(outputFolder.path, forKey: "outputFolder") } }
    @Published var quality: VideoQuality { didSet { d.set(quality.rawValue, forKey: "quality") } }
    @Published var codec: VideoCodec { didSet { d.set(codec.rawValue, forKey: "codec") } }
    @Published var screenshotFormat: ScreenshotFormat { didSet { d.set(screenshotFormat.rawValue, forKey: "shotFormat") } }
    @Published var revealAfterRecording: Bool { didSet { d.set(revealAfterRecording, forKey: "revealVideo") } }
    @Published var revealAfterScreenshot: Bool { didSet { d.set(revealAfterScreenshot, forKey: "revealShot") } }

    /// Last region the user selected, offered again on the next capture.
    @Published var lastArea: CGRect? {
        didSet {
            guard let lastArea else { return }
            d.set([lastArea.minX, lastArea.minY, lastArea.width, lastArea.height], forKey: "lastArea")
        }
    }
    @Published var recordShortcut: Shortcut { didSet { store(recordShortcut, as: "record") } }
    @Published var screenshotShortcut: Shortcut { didSet { store(screenshotShortcut, as: "shot") } }

    private init() {
        let defaultFolder = FileManager.default
            .urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser

        language = Language(rawValue: d.string(forKey: "language") ?? "") ?? .ru
        frameRate = FrameRate(rawValue: d.object(forKey: "fps") as? Int ?? 30) ?? .fps30
        resolution = ResolutionPreset(rawValue: d.object(forKey: "resolution") as? Int ?? 1080) ?? .p1080
        microphoneEnabled = d.object(forKey: "micEnabled") as? Bool ?? false
        microphoneDeviceID = d.string(forKey: "micDevice")
        systemAudioEnabled = d.object(forKey: "sysAudio") as? Bool ?? true
        showsCursor = d.object(forKey: "showsCursor") as? Bool ?? true
        highlightClicks = d.object(forKey: "highlightClicks") as? Bool ?? false
        showsKeystrokes = d.object(forKey: "keystrokes") as? Bool ?? false
        countdown = d.object(forKey: "countdown") as? Int ?? 3
        quality = VideoQuality(rawValue: d.object(forKey: "quality") as? Int ?? 1) ?? .medium
        codec = VideoCodec(rawValue: d.object(forKey: "codec") as? Int ?? 0) ?? .h264
        screenshotFormat = ScreenshotFormat(rawValue: d.object(forKey: "shotFormat") as? Int ?? 0) ?? .png
        revealAfterRecording = d.object(forKey: "revealVideo") as? Bool ?? true
        revealAfterScreenshot = d.object(forKey: "revealShot") as? Bool ?? false
        if let values = d.array(forKey: "lastArea") as? [CGFloat], values.count == 4 {
            lastArea = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        } else {
            lastArea = nil
        }
        recordShortcut = AppSettings.loadShortcut("record",
                                                 default: Shortcut(keyCode: kVK_ANSI_S, modifiers: [.command, .shift]))
        screenshotShortcut = AppSettings.loadShortcut("shot",
                                                     default: Shortcut(keyCode: kVK_ANSI_A, modifiers: [.command, .shift]))
        if let path = d.string(forKey: "outputFolder") {
            outputFolder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            outputFolder = defaultFolder
        }
    }

    func t(_ key: String) -> String { L.t(key, language) }

    // MARK: - Shortcuts

    private static func loadShortcut(_ name: String, default fallback: Shortcut) -> Shortcut {
        let defaults = UserDefaults.standard
        guard let code = defaults.object(forKey: "shortcut.\(name).key") as? Int,
              let flags = defaults.object(forKey: "shortcut.\(name).mods") as? UInt else { return fallback }
        return Shortcut(keyCode: code, modifiers: NSEvent.ModifierFlags(rawValue: flags))
    }

    private func store(_ shortcut: Shortcut, as name: String) {
        d.set(shortcut.keyCode, forKey: "shortcut.\(name).key")
        d.set(shortcut.modifiers.rawValue, forKey: "shortcut.\(name).mods")
    }

    // MARK: - Launch at login

    var launchesAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Login item error: \(error)")
            }
            objectWillChange.send()
        }
    }

    func makeOutputURL() -> URL {
        outputURL(prefix: "Screen Recording", fileExtension: "mp4")
    }

    func makeScreenshotURL() -> URL {
        outputURL(prefix: "Screenshot", fileExtension: screenshotFormat.fileExtension)
    }

    private func outputURL(prefix: String, fileExtension: String) -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: outputFolder.path) {
            try? fm.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return outputFolder.appendingPathComponent("\(prefix) \(formatter.string(from: Date())).\(fileExtension)")
    }
}
