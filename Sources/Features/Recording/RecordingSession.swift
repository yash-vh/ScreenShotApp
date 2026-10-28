import AppKit
import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// What to record
public enum RecordingTarget: Sendable, Equatable {
    case display(CGDirectDisplayID)
    /// `rect` is in display points with a top-left origin
    case region(CGDirectDisplayID, rect: CGRect)
    case window(CGWindowID)
}

/// One live recording: a ScreenCaptureKit stream (video + system audio) and an optional microphone capture,
/// both feeding a `RecordingWriter`.
public final class RecordingSession: NSObject, SCStreamOutput, SCStreamDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    public let writer: RecordingWriter
    public let pixelSize: CGSize
    private var stream: SCStream!
    private var microphone: AVCaptureSession?
    private let hostClock = CMClockGetHostTimeClock()
    /// Called on the main actor if the stream stops on its own (display unplugged, window closed, permission revoked)
    public var onStreamError: (@MainActor (Error) -> Void)?

    public static func make(target: RecordingTarget, settings: RecordingSettings, outputURL: URL) async throws -> RecordingSession {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownApp = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let configuration = SCStreamConfiguration()
        let filter: SCContentFilter

        switch target {
        case .display(let displayID), .region(let displayID, _):
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                throw AppError.displayNotFound(displayId: displayID)
            }
            // Keep our own HUDs and the recording frame out of the video
            filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
            let scale = CGFloat(filter.pointPixelScale)
            if case .region(_, let rect) = target {
                let bounded = rect.intersection(CGRect(x: 0, y: 0, width: display.width, height: display.height))
                guard bounded.width >= 2, bounded.height >= 2 else { throw AppError.invalidRegion(width: rect.width, height: rect.height) }
                configuration.sourceRect = bounded
                configuration.width = evenDimension(bounded.width * scale)
                configuration.height = evenDimension(bounded.height * scale)
            } else {
                configuration.width = evenDimension(CGFloat(display.width) * scale)
                configuration.height = evenDimension(CGFloat(display.height) * scale)
            }
        case .window(let windowID):
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw AppError.windowNotFound(windowId: windowID)
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = CGFloat(filter.pointPixelScale)
            configuration.width = evenDimension(window.frame.width * scale)
            configuration.height = evenDimension(window.frame.height * scale)
        }

        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, settings.frameRate)))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = settings.showCursor
        configuration.queueDepth = 6
        configuration.scalesToFit = true
        if #available(macOS 15.0, *) {
            configuration.showMouseClicks = settings.showClicks
        }
        if settings.recordSystemAudio {
            configuration.capturesAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            configuration.excludesCurrentProcessAudio = true
        }

        let writer = try RecordingWriter(
            outputURL: outputURL,
            width: configuration.width,
            height: configuration.height,
            frameRate: settings.frameRate,
            codec: settings.codec,
            systemAudio: settings.recordSystemAudio,
            microphone: settings.recordMicrophone
        )
        return try RecordingSession(filter: filter, configuration: configuration, writer: writer, microphone: settings.recordMicrophone)
    }

    private init(filter: SCContentFilter, configuration: SCStreamConfiguration, writer: RecordingWriter, microphone: Bool) throws {
        self.writer = writer
        self.pixelSize = CGSize(width: configuration.width, height: configuration.height)
        super.init()
        stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: writer.queue)
        if configuration.capturesAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: writer.queue)
        }
        if microphone {
            self.microphone = try makeMicrophoneSession()
        }
    }

    private func makeMicrophoneSession() throws -> AVCaptureSession {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw AppError.audioDeviceUnavailable(name: "Microphone")
        }
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioDataOutput()
        // Deliver 48 kHz mono float so the AAC encoder never has to guess the source format
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false
        ]
        output.setSampleBufferDelegate(self, queue: writer.queue)
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw AppError.audioDeviceUnavailable(name: device.localizedName)
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        return session
    }

    // MARK: - Control

    public func start() async throws {
        microphone?.startRunning()
        do {
            try await stream.startCapture()
        } catch {
            microphone?.stopRunning()
            writer.queue.sync { writer.cancel() }
            throw error
        }
    }

    public func pause() {
        let now = CMClockGetTime(hostClock)
        writer.queue.async { self.writer.pause(at: now) }
    }

    public func resume() {
        let now = CMClockGetTime(hostClock)
        writer.queue.async { self.writer.resume(at: now) }
    }

    /// Stops capturing and finalizes the MP4
    public func stop() async throws -> URL {
        try? await stream.stopCapture()
        microphone?.stopRunning()
        // Let any samples already queued land before finishing
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.queue.async { continuation.resume() }
        }
        try await writer.finish()
        return writer.outputURL
    }

    public func cancel() async {
        try? await stream.stopCapture()
        microphone?.stopRunning()
        writer.queue.sync { writer.cancel() }
    }

    // MARK: - SCStreamOutput

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            // Skip idle / blank frames; only complete frames carry new pixels
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let rawStatus = attachments.first?[.status] as? Int,
                  SCFrameStatus(rawValue: rawStatus) == .complete else { return }
            writer.append(sampleBuffer, to: .video)
        case .audio:
            writer.append(sampleBuffer, to: .systemAudio)
        default:
            break
        }
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        AppLogger.shared.recording.error("Recording stream stopped: \(error.localizedDescription, privacy: .public)")
        Task { @MainActor in self.onStreamError?(error) }
    }

    // MARK: - Microphone

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Bring microphone timestamps onto the host clock the screen samples use
        guard let sessionClock = microphone?.synchronizationClock else {
            writer.append(sampleBuffer, to: .microphone)
            return
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let hostPTS = CMSyncConvertTime(pts, from: sessionClock, to: hostClock)
        let delta = hostPTS - pts
        if delta == .zero {
            writer.append(sampleBuffer, to: .microphone)
        } else if let shifted = RecordingWriter.retime(sampleBuffer, by: CMTime.zero - delta) {
            writer.append(shifted, to: .microphone)
        }
    }
}
