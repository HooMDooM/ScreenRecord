import AVFoundation
import ScreenCaptureKit
import AppKit

enum CaptureTarget {
    /// `rect` is in display-local points with a top-left origin. `nil` means the whole display.
    case display(SCDisplay, rect: CGRect?)
    case window(SCWindow)
}

struct RecorderOptions {
    var frameRate: Int
    var resolution: ResolutionPreset
    var quality: VideoQuality = .medium
    var codec: VideoCodec = .h264
    var showsCursor: Bool
    var systemAudio: Bool
    var microphone: Bool
    var microphoneDeviceID: String?
    var excludedWindowIDs: Set<CGWindowID>
    var outputURL: URL
}

enum RecorderError: LocalizedError {
    case noPermission
    case writerFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPermission: return "Screen recording permission denied"
        case .writerFailed(let message): return message
        }
    }
}

final class Recorder: NSObject, SCStreamDelegate, SCStreamOutput, @unchecked Sendable {
    private let queue = DispatchQueue(label: "screenrecord.capture", qos: .userInitiated)
    private let mixer = AudioMixer()

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var audioInput: AVAssetWriterInput?

    /// ScreenCaptureKit stops sending pixels while the screen is static, so we
    /// keep the last frame and repeat it to keep the timeline moving.
    private var lastPixelBuffer: CVPixelBuffer?
    private var lastVideoTime: CMTime = .invalid

    private var options: RecorderOptions?
    private var sessionStarted = false
    private var isPaused = false
    private var pausedAt: CMTime = .zero
    private var pauseOffset: CMTime = .zero
    private var startHostTime: CMTime = .zero
    private var mixesMicrophoneIntoSystem = false
    private var finished = false

    private(set) var outputURL: URL?
    var onError: ((Error) -> Void)?

    var isRecording: Bool { stream != nil }
    var isPausedNow: Bool { isPaused }

    /// Wall-clock length of the recording, excluding paused time.
    var elapsed: TimeInterval {
        guard sessionStarted else { return 0 }
        let now = isPaused ? pausedAt : CMClockGetTime(CMClockGetHostTimeClock())
        return max(0, (now - startHostTime - pauseOffset).seconds)
    }

    // MARK: - Start

    func start(target: CaptureTarget, options: RecorderOptions) async throws {
        let (filter, size) = try makeFilter(for: target, options: options)
        let configuration = SCStreamConfiguration()
        configuration.width = size.width
        configuration.height = size.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.frameRate))
        configuration.queueDepth = 8
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = options.showsCursor
        configuration.scalesToFit = true
        configuration.capturesAudio = options.systemAudio
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.captureMicrophone = options.microphone
        if options.microphone, let deviceID = options.microphoneDeviceID {
            configuration.microphoneCaptureDeviceID = deviceID
        }
        if case .display(_, let rect?) = target {
            configuration.sourceRect = rect
        }

        try setupWriter(options: options, size: size)

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if options.systemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        }
        if options.microphone {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
        }

        self.options = options
        self.stream = stream
        self.mixesMicrophoneIntoSystem = options.systemAudio && options.microphone
        self.outputURL = options.outputURL
        do {
            try await stream.startCapture()
        } catch {
            // Don't leave an empty .mp4 behind when the stream refuses to start.
            self.stream = nil
            discardWriter()
            try? FileManager.default.removeItem(at: options.outputURL)
            throw error
        }
    }

    private func discardWriter() {
        queue.sync {
            if let writer, writer.status == .writing { writer.cancelWriting() }
            writer = nil
            videoInput = nil
            pixelAdaptor = nil
            audioInput = nil
            lastPixelBuffer = nil
            lastVideoTime = .invalid
            sessionStarted = false
        }
    }

    /// Single frame of the same target the recorder would capture.
    func captureImage(target: CaptureTarget, options: RecorderOptions) async throws -> CGImage {
        let (filter, size) = try makeFilter(for: target, options: options)
        let configuration = SCStreamConfiguration()
        configuration.width = size.width
        configuration.height = size.height
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = options.showsCursor
        configuration.scalesToFit = true
        if case .display(_, let rect?) = target {
            configuration.sourceRect = rect
        }
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    private func makeFilter(for target: CaptureTarget, options: RecorderOptions) throws -> (SCContentFilter, (width: Int, height: Int)) {
        switch target {
        case .display(let display, let rect):
            let scale = Recorder.scaleFactor(for: display.displayID)
            let excluded = try excludedWindows(on: display, ids: options.excludedWindowIDs)
            let filter = SCContentFilter(display: display, excludingWindows: excluded)
            let pointSize = rect?.size ?? CGSize(width: display.width, height: display.height)
            return (filter, outputSize(points: pointSize, scale: scale, preset: options.resolution))
        case .window(let window):
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = Recorder.scaleFactor(for: nil)
            return (filter, outputSize(points: window.frame.size, scale: scale, preset: options.resolution))
        }
    }

    private func excludedWindows(on display: SCDisplay, ids: Set<CGWindowID>) throws -> [SCWindow] {
        guard !ids.isEmpty, let content = Recorder.cachedContent else { return [] }
        return content.windows.filter { ids.contains($0.windowID) }
    }

    /// Content snapshot refreshed by the UI layer; used to resolve excluded windows.
    static var cachedContent: SCShareableContent?

    private func outputSize(points: CGSize, scale: CGFloat, preset: ResolutionPreset) -> (width: Int, height: Int) {
        var width = points.width * scale
        var height = points.height * scale
        if preset != .original {
            let limit = CGFloat(preset.rawValue)
            if height > limit {
                width *= limit / height
                height = limit
            }
        }
        let evenWidth = max(2, Int(width.rounded()) & ~1)
        let evenHeight = max(2, Int(height.rounded()) & ~1)
        return (evenWidth, evenHeight)
    }

    static func scaleFactor(for displayID: CGDirectDisplayID?) -> CGFloat {
        if let displayID,
           let screen = NSScreen.screens.first(where: {
               ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
           }) {
            return screen.backingScaleFactor
        }
        return NSScreen.main?.backingScaleFactor ?? 2
    }

    // MARK: - Writer

    private func setupWriter(options: RecorderOptions, size: (width: Int, height: Int)) throws {
        try? FileManager.default.removeItem(at: options.outputURL)
        let writer = try AVAssetWriter(outputURL: options.outputURL, fileType: .mp4)

        let pixels = Double(size.width * size.height)
        let bitRate = Int(min(120_000_000, max(1_500_000,
                                               pixels * Double(options.frameRate) * options.quality.bitsPerPixel)))
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitRate,
            AVVideoMaxKeyFrameIntervalKey: options.frameRate * 2,
            AVVideoAllowFrameReorderingKey: false
        ]
        if options.codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: options.codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: compression
        ])
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else { throw RecorderError.writerFailed("Cannot add video input") }
        writer.add(videoInput)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput,
                                                           sourcePixelBufferAttributes: nil)

        var audioInput: AVAssetWriterInput?
        if options.systemAudio || options.microphone {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000
            ])
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        guard writer.startWriting() else {
            throw RecorderError.writerFailed(writer.error?.localizedDescription ?? "Cannot start writing")
        }

        self.writer = writer
        self.videoInput = videoInput
        self.pixelAdaptor = adaptor
        self.audioInput = audioInput
        self.sessionStarted = false
        self.finished = false
        self.isPaused = false
        self.pauseOffset = .zero
        self.lastPixelBuffer = nil
        self.lastVideoTime = .invalid
        self.mixer.reset()
    }

    // MARK: - Pause / stop

    func setPaused(_ paused: Bool) {
        queue.async {
            guard self.isPaused != paused, self.sessionStarted else { return }
            let now = CMClockGetTime(CMClockGetHostTimeClock())
            if paused {
                self.pausedAt = now
            } else {
                self.pauseOffset = self.pauseOffset + (now - self.pausedAt)
            }
            self.isPaused = paused
        }
    }

    @discardableResult
    func stop() async -> URL? {
        guard let stream else { return nil }
        self.stream = nil
        try? await stream.stopCapture()

        return await withCheckedContinuation { continuation in
            queue.async {
                guard let writer = self.writer, !self.finished else {
                    continuation.resume(returning: nil)
                    return
                }
                self.finished = true

                // Close the timeline at the real end time, otherwise a static
                // screen would produce a clip that lasts a single frame.
                if self.sessionStarted, let last = self.lastPixelBuffer {
                    let now = self.isPaused ? self.pausedAt : CMClockGetTime(CMClockGetHostTimeClock())
                    self.appendVideo(last, at: now, force: true)
                }

                self.videoInput?.markAsFinished()
                self.audioInput?.markAsFinished()
                let url = self.outputURL
                let hadFrames = self.sessionStarted
                writer.finishWriting {
                    if writer.status != .completed {
                        NSLog("Recorder: finishWriting failed (frames=\(hadFrames)): \(writer.error?.localizedDescription ?? "unknown")")
                        if let url { try? FileManager.default.removeItem(at: url) }
                    }
                    self.writer = nil
                    self.videoInput = nil
                    self.pixelAdaptor = nil
                    self.audioInput = nil
                    self.lastPixelBuffer = nil
                    self.mixer.reset()
                    continuation.resume(returning: writer.status == .completed ? url : nil)
                }
            }
        }
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferDataIsReady(sampleBuffer), !finished, writer?.status == .writing else { return }

        switch type {
        case .screen:
            handleVideo(sampleBuffer)
        case .audio:
            handleSystemAudio(sampleBuffer)
        case .microphone:
            handleMicrophone(sampleBuffer)
        @unknown default:
            break
        }
    }

    private func handleVideo(_ sampleBuffer: CMSampleBuffer) {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]]
        let status = (attachments?.first?[.status] as? Int).flatMap(SCFrameStatus.init(rawValue:)) ?? .complete
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if status == .complete, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            if !sessionStarted {
                sessionStarted = true
                startHostTime = pts
                writer?.startSession(atSourceTime: pts)
            }
            lastPixelBuffer = pixelBuffer
            appendVideo(pixelBuffer, at: pts, force: false)
        } else if sessionStarted, let last = lastPixelBuffer {
            // Idle frame: nothing changed on screen, repeat the previous image.
            appendVideo(last, at: pts, force: false)
        }
    }

    /// Appends a frame on the writer timeline (host time minus paused time).
    private func appendVideo(_ pixelBuffer: CVPixelBuffer, at hostTime: CMTime, force: Bool) {
        guard !isPaused || force,
              let adaptor = pixelAdaptor,
              let input = videoInput,
              input.isReadyForMoreMediaData else { return }
        let time = hostTime - pauseOffset
        // ScreenCaptureKit already paces delivery to `minimumFrameInterval`, but on
        // 120/144 Hz displays the gaps are uneven, so only monotonic time is enforced.
        if lastVideoTime.isValid, time <= lastVideoTime { return }
        if adaptor.append(pixelBuffer, withPresentationTime: time) {
            lastVideoTime = time
        }
    }

    private func handleSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        guard sessionStarted, !isPaused, let input = audioInput, input.isReadyForMoreMediaData else { return }
        guard let pcm = AudioMixer.pcmBuffer(from: sampleBuffer),
              let converted = mixer.convertToTarget(pcm) else { return }
        if mixesMicrophoneIntoSystem {
            mixer.mixQueuedMicrophone(into: converted)
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard let out = AudioMixer.sampleBuffer(from: converted, presentationTime: pts - pauseOffset) else { return }
        input.append(out)
    }

    private func handleMicrophone(_ sampleBuffer: CMSampleBuffer) {
        guard sessionStarted, !isPaused else { return }
        guard let pcm = AudioMixer.pcmBuffer(from: sampleBuffer),
              let converted = mixer.convertToTarget(pcm) else { return }

        if mixesMicrophoneIntoSystem {
            mixer.enqueueMicrophone(converted)
        } else if let input = audioInput, input.isReadyForMoreMediaData {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if let out = AudioMixer.sampleBuffer(from: converted, presentationTime: pts - pauseOffset) {
                input.append(out)
            }
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { self.onError?(error) }
    }
}
