import CoreGraphics
import Foundation

/// Stitches successive captures of the same screen region into one tall image while the user scrolls.
///
/// Each frame is compared with the last accepted frame row by row: rows are hashed, distinctive rows
/// that appear once in both frames vote for a vertical shift, and the winning shift tells how many new
/// rows scrolled into view. Rows that stay put (sticky headers and footers) vote for "no shift", so they
/// are kept once instead of being repeated down the image.
public struct ScrollStitcher {
    public enum AppendResult: Equatable {
        /// New content scrolled into view and was added
        case appended(rows: Int)
        /// Nothing moved since the last frame
        case unchanged
        /// The frame couldn't be matched (scrolled too far between frames, or the content changed)
        case lostTrack
        /// The image reached `maxHeight`
        case full
    }

    public let width: Int
    public let frameHeight: Int
    public let maxHeight: Int
    /// Columns at the trailing edge ignored when matching (overlay scroll bars move while scrolling)
    public let ignoredTrailingColumns: Int

    private let colorSpace: CGColorSpace
    private let bytesPerRow: Int

    /// Accumulated image rows above the fixed footer
    private var body: [UInt8]
    private var bodyRows: Int
    /// Pixels and row hashes of the last accepted frame
    private var lastPixels: [UInt8]
    private var lastHashes: [UInt64]
    /// Rows at the bottom that don't scroll (status bars, sticky footers); fixed after the first match
    private var footerRows: Int?

    public private(set) var acceptedFrames = 1

    public init?(firstFrame: CGImage, maxHeight: Int = 40_000, ignoredTrailingColumns: Int = 0) {
        width = firstFrame.width
        frameHeight = firstFrame.height
        guard width > 0, frameHeight > 8 else { return nil }
        self.maxHeight = maxHeight
        self.ignoredTrailingColumns = min(max(ignoredTrailingColumns, 0), width / 4)
        let space = firstFrame.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        colorSpace = space.model == .rgb ? space : CGColorSpace(name: CGColorSpace.sRGB)!
        bytesPerRow = width * 4

        guard let pixels = Self.pixels(of: firstFrame, width: width, height: frameHeight, bytesPerRow: bytesPerRow, colorSpace: colorSpace) else { return nil }
        lastPixels = pixels
        lastHashes = Self.rowHashes(pixels, width: width, height: frameHeight, bytesPerRow: bytesPerRow, ignoredTrailingColumns: self.ignoredTrailingColumns)
        body = pixels
        bodyRows = frameHeight
    }

    /// Total height of the stitched image in pixels
    public var height: Int { bodyRows }

    public mutating func append(_ frame: CGImage) -> AppendResult {
        guard frame.width == width, frame.height == frameHeight else { return .lostTrack }
        guard bodyRows < maxHeight else { return .full }
        guard let pixels = Self.pixels(of: frame, width: width, height: frameHeight, bytesPerRow: bytesPerRow, colorSpace: colorSpace) else { return .lostTrack }
        let hashes = Self.rowHashes(pixels, width: width, height: frameHeight, bytesPerRow: bytesPerRow, ignoredTrailingColumns: ignoredTrailingColumns)

        if hashes == lastHashes { return .unchanged }
        guard let shift = Self.scrollShift(previous: lastHashes, current: hashes) else {
            // Without any vote for a shift, content may simply have changed in place (hover, caret)
            return Self.staticRowCount(lastHashes, hashes) > frameHeight / 2 ? .unchanged : .lostTrack
        }

        // The first real scroll tells how much of the bottom never moves
        if footerRows == nil {
            var footer = 0
            while footer < frameHeight / 3, lastHashes[frameHeight - 1 - footer] == hashes[frameHeight - 1 - footer] {
                footer += 1
            }
            footerRows = footer
            // Drop the first frame's footer from the body; it is re-added from the latest frame at the end
            bodyRows -= footer
            body.removeLast(footer * bytesPerRow)
        }
        let footer = footerRows ?? 0
        let scrollable = frameHeight - footer
        guard shift < scrollable else { return .lostTrack }

        // New rows are the bottom `shift` rows of the scrollable part of this frame
        let rows = min(shift, maxHeight - bodyRows)
        let start = (scrollable - shift) * bytesPerRow
        body.append(contentsOf: pixels[start..<(start + rows * bytesPerRow)])
        bodyRows += rows

        lastPixels = pixels
        lastHashes = hashes
        acceptedFrames += 1
        return rows < shift ? .full : .appended(rows: rows)
    }

    /// The stitched image: accumulated body plus the latest frame's fixed footer
    public func makeImage() -> CGImage? {
        let footer = footerRows ?? 0
        var data = body
        if footer > 0 {
            let start = (frameHeight - footer) * bytesPerRow
            data.append(contentsOf: lastPixels[start..<(frameHeight * bytesPerRow)])
        }
        let totalRows = bodyRows + footer
        guard let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        return CGImage(
            width: width, height: totalRows, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    // MARK: - Matching

    /// Downward scroll distance in rows between two frames, voted by distinctive rows; nil when no shift wins
    static func scrollShift(previous: [UInt64], current: [UInt64]) -> Int? {
        let uniquePrevious = uniqueRowIndices(previous)
        let uniqueCurrent = uniqueRowIndices(current)

        var votes: [Int: Int] = [:]
        for (hash, i) in uniqueCurrent {
            if let j = uniquePrevious[hash] { votes[j - i, default: 0] += 1 }
        }
        guard let best = votes.filter({ $0.key > 0 }).max(by: { $0.value < $1.value }) else { return nil }
        // Enough agreeing rows that a few repeated lines can't fake a match
        let needed = max(4, (votes.values.reduce(0, +) - (votes[0] ?? 0)) / 4)
        return best.value >= needed ? best.key : nil
    }

    /// Row index for every hash that occurs exactly once (blank and repeated rows can't locate a shift)
    private static func uniqueRowIndices(_ hashes: [UInt64]) -> [UInt64: Int] {
        var index: [UInt64: Int] = [:]
        var duplicates = Set<UInt64>()
        for (i, hash) in hashes.enumerated() {
            if index.updateValue(i, forKey: hash) != nil { duplicates.insert(hash) }
        }
        for hash in duplicates { index.removeValue(forKey: hash) }
        return index
    }

    private static func staticRowCount(_ a: [UInt64], _ b: [UInt64]) -> Int {
        zip(a, b).reduce(0) { $0 + ($1.0 == $1.1 ? 1 : 0) }
    }

    // MARK: - Pixels

    static func pixels(of image: CGImage, width: Int, height: Int, bytesPerRow: Int, colorSpace: CGColorSpace) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? buffer : nil
    }

    /// FNV-1a hash per row over slightly quantized pixels, so tiny encoder noise doesn't break matches
    static func rowHashes(_ pixels: [UInt8], width: Int, height: Int, bytesPerRow: Int, ignoredTrailingColumns: Int) -> [UInt64] {
        let columns = max(width - ignoredTrailingColumns, 1)
        return pixels.withUnsafeBytes { raw -> [UInt64] in
            let words = raw.bindMemory(to: UInt32.self)
            let wordsPerRow = bytesPerRow / 4
            return (0..<height).map { row in
                var hash: UInt64 = 0xcbf29ce484222325
                let base = row * wordsPerRow
                for column in 0..<columns {
                    hash ^= UInt64(words[base + column] & 0xFCFCFCFC)
                    hash = hash &* 0x100000001b3
                }
                return hash
            }
        }
    }
}
