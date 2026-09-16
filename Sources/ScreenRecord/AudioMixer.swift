import AVFoundation

/// Converts incoming CMSampleBuffers to a common format (48 kHz, stereo, float32)
/// and mixes the microphone into the system-audio timeline so the movie ends up
/// with a single, universally playable audio track.
final class AudioMixer {
    static let targetFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!

    private var converters: [String: AVAudioConverter] = [:]
    private let lock = NSLock()
    private var micQueue: [[Float]] = [[], []]
    private let maxQueuedFrames = 48_000 // 1 second of jitter buffer

    // MARK: - Conversion

    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc),
              let format = AVAudioFormat(streamDescription: asbd) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }

    func convertToTarget(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let format = buffer.format
        if format == AudioMixer.targetFormat { return buffer }

        let key = "\(format.sampleRate)-\(format.channelCount)-\(format.commonFormat.rawValue)-\(format.isInterleaved)"
        let converter: AVAudioConverter
        if let cached = converters[key] {
            converter = cached
        } else {
            guard let created = AVAudioConverter(from: format, to: AudioMixer.targetFormat) else { return nil }
            created.downmix = true
            converters[key] = created
            converter = created
        }

        let ratio = AudioMixer.targetFormat.sampleRate / format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: AudioMixer.targetFormat, frameCapacity: capacity) else { return nil }

        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, output.frameLength > 0 else { return nil }
        return output
    }

    // MARK: - Mixing

    func enqueueMicrophone(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        lock.lock()
        for ch in 0..<2 {
            let source = channels[min(ch, Int(buffer.format.channelCount) - 1)]
            micQueue[ch].append(contentsOf: UnsafeBufferPointer(start: source, count: frames))
            if micQueue[ch].count > maxQueuedFrames {
                micQueue[ch].removeFirst(micQueue[ch].count - maxQueuedFrames)
            }
        }
        lock.unlock()
    }

    /// Adds queued microphone samples into the system-audio buffer in place.
    func mixQueuedMicrophone(into buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        lock.lock()
        let available = min(frames, micQueue[0].count)
        guard available > 0 else { lock.unlock(); return }
        var mic: [[Float]] = []
        for ch in 0..<2 {
            mic.append(Array(micQueue[ch].prefix(available)))
            micQueue[ch].removeFirst(available)
        }
        lock.unlock()

        for ch in 0..<2 {
            let destination = channels[ch]
            for i in 0..<available {
                destination[i] = max(-1.0, min(1.0, destination[i] + mic[ch][i]))
            }
        }
    }

    func reset() {
        lock.lock()
        micQueue = [[], []]
        lock.unlock()
        converters.removeAll()
    }

    // MARK: - Output

    static func sampleBuffer(from pcm: AVAudioPCMBuffer, presentationTime: CMTime) -> CMSampleBuffer? {
        var asbd = pcm.format.streamDescription.pointee
        var formatDescription: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                             asbd: &asbd,
                                             layoutSize: 0, layout: nil,
                                             magicCookieSize: 0, magicCookie: nil,
                                             extensions: nil,
                                             formatDescriptionOut: &formatDescription) == noErr,
              let formatDescription else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: Int32(pcm.format.sampleRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid)

        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreate(allocator: kCFAllocatorDefault,
                                   dataBuffer: nil, dataReady: false,
                                   makeDataReadyCallback: nil, refcon: nil,
                                   formatDescription: formatDescription,
                                   sampleCount: CMItemCount(pcm.frameLength),
                                   sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                   sampleSizeEntryCount: 0, sampleSizeArray: nil,
                                   sampleBufferOut: &sampleBuffer) == noErr,
              let sampleBuffer else { return nil }

        guard CMSampleBufferSetDataBufferFromAudioBufferList(sampleBuffer,
                                                             blockBufferAllocator: kCFAllocatorDefault,
                                                             blockBufferMemoryAllocator: kCFAllocatorDefault,
                                                             flags: 0,
                                                             bufferList: pcm.audioBufferList) == noErr else { return nil }
        return sampleBuffer
    }
}
