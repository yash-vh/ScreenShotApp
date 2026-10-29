import AVFoundation
import CoreMedia
import ImageIO
import XCTest
@testable import ScreenMint

final class PauseClockTests: XCTestCase {
    private func t(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600) }

    func testSamplesDuringPauseAreDroppedAndLaterOnesShifted() {
        var clock = PauseClock()
        XCTAssertEqual(clock.adjust(t(1)), t(1))

        clock.pause(at: t(2))
        XCTAssertTrue(clock.isPaused)
        XCTAssertNil(clock.adjust(t(2.5)))
        XCTAssertEqual(clock.adjust(t(1.9)), t(1.9), "samples captured before the pause still count")

        clock.resume(at: t(5))
        XCTAssertEqual(clock.adjust(t(6)), t(3))

        clock.pause(at: t(7))
        clock.pause(at: t(8)) // repeated pause is ignored
        clock.resume(at: t(9))
        XCTAssertEqual(clock.offset, t(5))
        XCTAssertEqual(clock.adjust(t(10)), t(5))
    }

    func testResumeWithoutPauseIsNoOp() {
        var clock = PauseClock()
        clock.resume(at: t(3))
        XCTAssertEqual(clock.offset, .zero)
    }
}

final class RecordingSupportTests: XCTestCase {
    func testDiskSpaceGuardThresholds() {
        let mb: Int64 = 1_048_576
        XCTAssertFalse(DiskSpaceGuard.canStart(available: 1200 * mb, minimumFreeMB: 1024))
        XCTAssertTrue(DiskSpaceGuard.canStart(available: 1600 * mb, minimumFreeMB: 1024))
        XCTAssertTrue(DiskSpaceGuard.mustStop(available: 1000 * mb, minimumFreeMB: 1024))
        XCTAssertFalse(DiskSpaceGuard.mustStop(available: 1100 * mb, minimumFreeMB: 1024))
        XCTAssertNotNil(DiskSpaceGuard.availableBytes(at: FileManager.default.temporaryDirectory))
    }

    func testEvenDimensions() {
        XCTAssertEqual(evenDimension(1001), 1000)
        XCTAssertEqual(evenDimension(1000.6), 1000)
        XCTAssertEqual(evenDimension(1), 2)
    }

    func testDurationFormatting() {
        XCTAssertEqual(RecordingCoordinator.format(42), "0:42")
        XCTAssertEqual(RecordingCoordinator.format(723), "12:03")
        XCTAssertEqual(RecordingCoordinator.format(3723), "1:02:03")
    }

    func testSettingsDecodeMissingKeysWithDefaults() throws {
        let decoded = try JSONDecoder().decode(RecordingSettings.self, from: Data(#"{"frameRate":60,"outputFormat":"gif"}"#.utf8))
        XCTAssertEqual(decoded.frameRate, 60)
        XCTAssertEqual(decoded.outputFormat, .gif)
        XCTAssertEqual(decoded.codec, .h264)
        XCTAssertEqual(decoded.minimumFreeSpaceMB, RecordingSettings.default.minimumFreeSpaceMB)
    }

    func testGIFScaling() {
        XCTAssertEqual(GIFEncoder.scaledSize(CGSize(width: 1600, height: 900), maxPixelSize: 800), CGSize(width: 800, height: 450))
        XCTAssertEqual(GIFEncoder.scaledSize(CGSize(width: 400, height: 300), maxPixelSize: 800), CGSize(width: 400, height: 300))
        XCTAssertEqual(GIFEncoder.scaledSize(CGSize(width: 1600, height: 900), maxPixelSize: 0), CGSize(width: 1600, height: 900))
    }
}

final class RecordingWriterTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("RecordingWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func frame(at seconds: Double, width: Int = 64, height: Int = 48, shade: UInt8) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixelBuffer)
        let buffer = try XCTUnwrap(pixelBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), Int32(shade), CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])

        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 600), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: try XCTUnwrap(format), sampleTiming: &timing, sampleBufferOut: &sample)
        return try XCTUnwrap(sample)
    }

    /// Writes 4 s of frames at 10 fps with seconds 1.5–3.5 paused; the file should be ~2 s long
    private func writeSample(codec: RecordingCodec = .h264) async throws -> URL {
        let url = directory.appendingPathComponent("test-\(codec.rawValue).mp4")
        let writer = try RecordingWriter(outputURL: url, width: 64, height: 48, frameRate: 10, codec: codec, systemAudio: false, microphone: false)
        let base = 1000.0 // host-clock style timestamps never start at zero
        for i in 0..<40 {
            let time = base + Double(i) / 10
            if i == 15 { writer.pause(at: CMTime(seconds: time, preferredTimescale: 600)) }
            if i == 35 { writer.resume(at: CMTime(seconds: time, preferredTimescale: 600)) }
            writer.append(try frame(at: time, shade: UInt8(i * 6)), to: .video)
            // Give the real-time input a moment, as a live stream would
            try await Task.sleep(nanoseconds: 15_000_000)
        }
        // 20 frames fall outside the pause; a busy real-time encoder may drop a few, as with a live stream
        XCTAssertTrue((15...20).contains(writer.framesWritten), "wrote \(writer.framesWritten) frames")
        try await writer.finish()
        return url
    }

    func testWriterProducesPlayableMP4WithPausesRemoved() async throws {
        let url = try await writeSample()
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 1.9, accuracy: 0.25)
        let track = try await XCTUnwrapAsync(await asset.loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 64, height: 48))
    }

    func testFinishWithoutFramesFailsAndRemovesFile() async throws {
        let url = directory.appendingPathComponent("empty.mp4")
        let writer = try RecordingWriter(outputURL: url, width: 64, height: 48, frameRate: 30, codec: .h264, systemAudio: false, microphone: false)
        do {
            try await writer.finish()
            XCTFail("expected failure")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testGIFConversionLoopsAtRequestedRate() async throws {
        let video = try await writeSample()
        let gifURL = directory.appendingPathComponent("out.gif")
        let result = try await GIFEncoder.convert(videoURL: video, to: gifURL, frameRate: 10, maxPixelSize: 32)

        XCTAssertGreaterThanOrEqual(result.frameCount, 12)
        XCTAssertEqual(result.pixelSize, CGSize(width: 32, height: 24))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(gifURL as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), result.frameCount)
        let props = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        XCTAssertEqual(gif?[kCGImagePropertyGIFLoopCount] as? Int, 0)
        let frameProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let delay = (frameProps?[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFDelayTime] as? Double
        XCTAssertEqual(delay ?? 0, 0.1, accuracy: 0.01)
    }
}

private func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    try XCTUnwrap(value, file: file, line: line)
}
