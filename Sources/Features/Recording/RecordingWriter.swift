import AVFoundation
import CoreMedia
import Foundation

/// Writes screen frames plus optional system-audio and microphone tracks to an MP4.
/// Every method must be called on `queue`; the stream and microphone outputs deliver there.
public final class RecordingWriter: @unchecked Sendable {
    public let queue = DispatchQueue(label: "com.screenmint.recording-writer", qos: .userInitiated)
    public let outputURL: URL

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let systemAudioInput: AVAssetWriterInput?
    private let microphoneInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var clock = PauseClock()
    private var lastVideoTime: CMTime = .invalid
    public private(set) var framesWritten = 0

    public enum Track { case video, systemAudio, microphone }

    public init(outputURL: URL, width: Int, height: Int, frameRate: Int, codec: RecordingCodec, systemAudio: Bool, microphone: Bool) throws {
        self.outputURL = outputURL
        try? FileManager.default.removeItem(at: outputURL)
        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        // ~0.15 bits per pixel per frame keeps text crisp without huge files
        let bitrate = max(2_000_000, Int(Double(width * height * frameRate) * (codec == .hevc ? 0.1 : 0.15)))
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: frameRate,
            AVVideoMaxKeyFrameIntervalKey: frameRate * 2
        ]
        if codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec.avCodec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression
        ])
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else { throw AppError.recordingExportFailed(reason: "Video track rejected (\(width)×\(height)).") }
        writer.add(videoInput)

        func audioInput(channels: Int) -> AVAssetWriterInput {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: channels == 1 ? 96_000 : 160_000
            ])
            input.expectsMediaDataInRealTime = true
            return input
        }
        systemAudioInput = systemAudio ? audioInput(channels: 2) : nil
        microphoneInput = microphone ? audioInput(channels: 1) : nil
        for input in [systemAudioInput, microphoneInput].compactMap({ $0 }) where writer.canAdd(input) {
            writer.add(input)
        }

        guard writer.startWriting() else {
            throw AppError.recordingExportFailed(reason: writer.error?.localizedDescription ?? "Writer failed to start.")
        }
    }

    public func pause(at time: CMTime) { clock.pause(at: time) }
    public func resume(at time: CMTime) { clock.resume(at: time) }

    /// Appends a sample; drops it while paused, before the first frame, or if the input is busy
    public func append(_ sampleBuffer: CMSampleBuffer, to track: Track) {
        guard writer.status == .writing, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard let adjusted = clock.adjust(pts) else { return }

        let input: AVAssetWriterInput?
        switch track {
        case .video:
            if !sessionStarted {
                writer.startSession(atSourceTime: adjusted)
                sessionStarted = true
            }
            // Never write a frame that isn't strictly after the previous one (can happen right after resume)
            if lastVideoTime.isValid, adjusted <= lastVideoTime { return }
            input = videoInput
        case .systemAudio:
            input = systemAudioInput
        case .microphone:
            input = microphoneInput
        }
        guard sessionStarted, let input, input.isReadyForMoreMediaData else { return }

        let buffer: CMSampleBuffer
        if clock.offset == .zero {
            buffer = sampleBuffer
        } else {
            guard let retimed = Self.retime(sampleBuffer, by: clock.offset) else { return }
            buffer = retimed
        }
        if input.append(buffer), track == .video {
            lastVideoTime = adjusted
            framesWritten += 1
        }
    }

    /// Finishes the file; throws when nothing was captured
    public func finish() async throws {
        guard sessionStarted, framesWritten > 0 else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw AppError.recordingExportFailed(reason: "No frames were captured.")
        }
        if lastVideoTime.isValid {
            writer.endSession(atSourceTime: lastVideoTime)
        }
        videoInput.markAsFinished()
        systemAudioInput?.markAsFinished()
        microphoneInput?.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            throw AppError.recordingExportFailed(reason: writer.error?.localizedDescription ?? "Unknown writer error.")
        }
    }

    public func cancel() {
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: outputURL)
    }

    static func retime(_ buffer: CMSampleBuffer, by offset: CMTime) -> CMSampleBuffer? {
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: max(count, 1))
        CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: timings.count, arrayToFill: &timings, entriesNeededOut: &count)
        for i in timings.indices {
            if timings[i].presentationTimeStamp.isValid { timings[i].presentationTimeStamp = timings[i].presentationTimeStamp - offset }
            if timings[i].decodeTimeStamp.isValid { timings[i].decodeTimeStamp = timings[i].decodeTimeStamp - offset }
        }
        var out: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: buffer, sampleTimingEntryCount: timings.count, sampleTimingArray: &timings, sampleBufferOut: &out)
        return out
    }
}
