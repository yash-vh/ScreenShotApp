import AVFoundation
import CoreMedia
import Foundation

/// Video codec for MP4 export
public enum RecordingCodec: String, Codable, Sendable, CaseIterable, Identifiable {
    case h264
    case hevc

    public var id: String { rawValue }
    public var displayName: String { self == .h264 ? "H.264 (most compatible)" : "HEVC (smaller files)" }
    public var avCodec: AVVideoCodecType { self == .h264 ? .h264 : .hevc }
}

/// What a finished recording is saved as
public enum RecordingOutputFormat: String, Codable, Sendable, CaseIterable, Identifiable {
    case mp4
    case gif

    public var id: String { rawValue }
    public var displayName: String { self == .mp4 ? "MP4 Video" : "Animated GIF" }
}

/// User preferences for screen recording
public struct RecordingSettings: Codable, Sendable, Equatable {
    public var codec: RecordingCodec
    public var frameRate: Int
    public var outputFormat: RecordingOutputFormat
    public var recordMicrophone: Bool
    public var recordSystemAudio: Bool
    public var showCursor: Bool
    public var showClicks: Bool
    public var gifFrameRate: Int
    /// Longest edge of exported GIF frames in pixels; 0 keeps the recorded size
    public var gifMaxPixelSize: Int
    /// Recording stops automatically when free space on the output volume drops below this
    public var minimumFreeSpaceMB: Int

    public static let `default` = RecordingSettings(
        codec: .h264,
        frameRate: 30,
        outputFormat: .mp4,
        recordMicrophone: false,
        recordSystemAudio: false,
        showCursor: true,
        showClicks: false,
        gifFrameRate: 15,
        gifMaxPixelSize: 800,
        minimumFreeSpaceMB: 1024
    )

    public init(codec: RecordingCodec, frameRate: Int, outputFormat: RecordingOutputFormat, recordMicrophone: Bool, recordSystemAudio: Bool, showCursor: Bool, showClicks: Bool, gifFrameRate: Int, gifMaxPixelSize: Int, minimumFreeSpaceMB: Int) {
        self.codec = codec
        self.frameRate = frameRate
        self.outputFormat = outputFormat
        self.recordMicrophone = recordMicrophone
        self.recordSystemAudio = recordSystemAudio
        self.showCursor = showCursor
        self.showClicks = showClicks
        self.gifFrameRate = gifFrameRate
        self.gifMaxPixelSize = gifMaxPixelSize
        self.minimumFreeSpaceMB = minimumFreeSpaceMB
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RecordingSettings.default
        codec = try c.decodeIfPresent(RecordingCodec.self, forKey: .codec) ?? d.codec
        frameRate = try c.decodeIfPresent(Int.self, forKey: .frameRate) ?? d.frameRate
        outputFormat = try c.decodeIfPresent(RecordingOutputFormat.self, forKey: .outputFormat) ?? d.outputFormat
        recordMicrophone = try c.decodeIfPresent(Bool.self, forKey: .recordMicrophone) ?? d.recordMicrophone
        recordSystemAudio = try c.decodeIfPresent(Bool.self, forKey: .recordSystemAudio) ?? d.recordSystemAudio
        showCursor = try c.decodeIfPresent(Bool.self, forKey: .showCursor) ?? d.showCursor
        showClicks = try c.decodeIfPresent(Bool.self, forKey: .showClicks) ?? d.showClicks
        gifFrameRate = try c.decodeIfPresent(Int.self, forKey: .gifFrameRate) ?? d.gifFrameRate
        gifMaxPixelSize = try c.decodeIfPresent(Int.self, forKey: .gifMaxPixelSize) ?? d.gifMaxPixelSize
        minimumFreeSpaceMB = try c.decodeIfPresent(Int.self, forKey: .minimumFreeSpaceMB) ?? d.minimumFreeSpaceMB
    }
}

/// Shifts sample timestamps so paused stretches are cut out of the recording.
/// All times are on the host clock that ScreenCaptureKit stamps samples with.
public struct PauseClock: Sendable, Equatable {
    public private(set) var offset: CMTime = .zero
    public private(set) var pausedAt: CMTime?

    public init() {}

    public var isPaused: Bool { pausedAt != nil }

    public mutating func pause(at time: CMTime) {
        guard pausedAt == nil else { return }
        pausedAt = time
    }

    public mutating func resume(at time: CMTime) {
        guard let start = pausedAt else { return }
        offset = offset + (time - start)
        pausedAt = nil
    }

    /// The timestamp to write, or nil when the sample falls inside a pause and must be dropped
    public func adjust(_ time: CMTime) -> CMTime? {
        if let start = pausedAt, time >= start { return nil }
        return time - offset
    }
}

/// Free-space checks so a long recording can't fill the disk
public enum DiskSpaceGuard {
    /// Extra headroom required before a recording may start
    public static let startHeadroomBytes: Int64 = 512 * 1_048_576

    public static func availableBytes(at url: URL) -> Int64? {
        let probe = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let important = values?.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
        return values?.volumeAvailableCapacity.map(Int64.init)
    }

    public static func canStart(available: Int64, minimumFreeMB: Int) -> Bool {
        available >= Int64(minimumFreeMB) * 1_048_576 + startHeadroomBytes
    }

    public static func mustStop(available: Int64, minimumFreeMB: Int) -> Bool {
        available < Int64(minimumFreeMB) * 1_048_576
    }
}

/// Video sizes must be even for H.264 / HEVC
public func evenDimension(_ value: CGFloat) -> Int {
    max(2, Int(value.rounded()) & ~1)
}
