import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Converts a recorded video into a looping animated GIF at a chosen frame rate and size
public enum GIFEncoder {
    public struct Result: Sendable {
        public let url: URL
        public let frameCount: Int
        public let pixelSize: CGSize
    }

    /// - Parameters:
    ///   - frameRate: GIF frames per second (GIF delays are in 1/100 s, so 10–25 fps work best)
    ///   - maxPixelSize: longest edge of output frames; 0 keeps the video size
    public static func convert(videoURL: URL, to outputURL: URL, frameRate: Int, maxPixelSize: Int, progress: (@Sendable (Double) -> Void)? = nil) async throws -> Result {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            throw AppError.gifConversionFailed(reason: "The recording has no duration.")
        }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw AppError.gifConversionFailed(reason: "The recording has no video track.")
        }
        let naturalSize = try await track.load(.naturalSize)

        let fps = Double(min(max(frameRate, 1), 50))
        let frameCount = max(1, Int((duration * fps).rounded(.down)))
        let times = (0..<frameCount).map { CMTime(seconds: Double($0) / fps, preferredTimescale: 600) }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let tolerance = CMTime(seconds: 0.5 / fps, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        let size = scaledSize(naturalSize, maxPixelSize: maxPixelSize)
        generator.maximumSize = size

        try? FileManager.default.removeItem(at: outputURL)
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
            throw AppError.gifConversionFailed(reason: "Could not create the GIF file.")
        }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: 1.0 / fps,
                kCGImagePropertyGIFUnclampedDelayTime: 1.0 / fps
            ]
        ] as CFDictionary

        var written = 0
        for await result in generator.images(for: times) {
            guard let image = try? result.image else { continue }
            CGImageDestinationAddImage(destination, image, frameProperties)
            written += 1
            progress?(Double(written) / Double(frameCount))
        }
        guard written > 0, CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: outputURL)
            throw AppError.gifConversionFailed(reason: "No frames could be decoded.")
        }
        return Result(url: outputURL, frameCount: written, pixelSize: size)
    }

    static func scaledSize(_ size: CGSize, maxPixelSize: Int) -> CGSize {
        let longest = max(size.width, size.height)
        guard maxPixelSize > 0, longest > CGFloat(maxPixelSize) else { return size }
        let ratio = CGFloat(maxPixelSize) / longest
        return CGSize(width: (size.width * ratio).rounded(), height: (size.height * ratio).rounded())
    }
}
