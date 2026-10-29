import Foundation
import CoreGraphics
import Vision

/// A recognized line of text with its normalized (top-left origin) bounding box
public struct RecognizedTextBlock: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var text: String
    public var confidence: Float
    public var boundingBox: NormalizedRect

    public init(id: UUID = UUID(), text: String, confidence: Float, boundingBox: NormalizedRect) {
        self.id = id
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

/// A detected barcode / QR code payload with its normalized (top-left origin) bounding box
public struct DetectedBarcode: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var payload: String
    public var symbology: String
    public var boundingBox: NormalizedRect

    public init(id: UUID = UUID(), payload: String, symbology: String, boundingBox: NormalizedRect) {
        self.id = id
        self.payload = payload
        self.symbology = symbology
        self.boundingBox = boundingBox
    }

    /// The payload as a web URL, when it is one
    public var url: URL? {
        guard let url = URL(string: payload.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        return url
    }
}

/// Combined on-device recognition output for one image
public struct RecognitionResult: Sendable, Equatable {
    public var textBlocks: [RecognizedTextBlock]
    public var barcodes: [DetectedBarcode]

    public init(textBlocks: [RecognizedTextBlock] = [], barcodes: [DetectedBarcode] = []) {
        self.textBlocks = textBlocks
        self.barcodes = barcodes
    }

    public var isEmpty: Bool { textBlocks.isEmpty && barcodes.isEmpty }

    /// All recognized text in reading order, one line per block
    public var fullText: String {
        VisionService.normalizeText(textBlocks.map(\.text))
    }
}

/// On-device asynchronous text recognition (`VNRecognizeTextRequest`) and barcode/QR detection (`VNDetectBarcodesRequest`).
/// Nothing leaves the machine.
///
/// The `.accurate` recognizer runs with a time budget. If it errors or exceeds the budget (some macOS
/// builds fail to compile its Neural Engine model), recognition falls back to `.fast`, and accurate mode
/// is skipped for the rest of the session after a hard failure.
public final class VisionService: @unchecked Sendable {
    public static let shared = VisionService()

    private enum AccurateState {
        case unknown, probing, available, unavailable
    }

    private let lock = NSLock()
    private var accurateState: AccurateState = .unknown
    private let queue = DispatchQueue(label: "com.screenmint.vision", qos: .userInitiated, attributes: .concurrent)

    /// Maximum time to wait for the accurate recognizer before falling back to the fast one
    public var accurateTimeout: TimeInterval = 8

    private init() {}

    /// Probes the accurate recognizer once in the background (call at launch) so a broken model
    /// is detected before the user's first OCR request instead of during it.
    public func prewarm() {
        lock.lock()
        guard accurateState == .unknown else { lock.unlock(); return }
        accurateState = .probing
        lock.unlock()

        guard let probe = Self.probeImage() else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            let succeeded = (try? VNImageRequestHandler(cgImage: probe, options: [:]).perform([request])) != nil
            self?.setAccurateState(succeeded ? .available : .unavailable)
            AppLogger.shared.recognition.info("Accurate OCR model \(succeeded ? "ready" : "unavailable; using fast recognition", privacy: .public).")
        }
    }

    /// Runs text recognition and barcode detection
    public func recognize(in image: CGImage, recognitionLevel: VNRequestTextRecognitionLevel = .accurate) async throws -> RecognitionResult {
        let state = currentAccurateState
        let wantsAccurate = recognitionLevel == .accurate && (state == .available || state == .unknown)
        if wantsAccurate {
            do {
                return try await perform(on: image, level: .accurate, timeout: accurateTimeout)
            } catch let error as RecognitionTimeout {
                AppLogger.shared.recognition.notice("Accurate OCR exceeded \(error.seconds, privacy: .public)s; falling back to fast recognition.")
            } catch {
                setAccurateState(.unavailable)
                AppLogger.shared.recognition.notice("Accurate OCR failed (\(error.localizedDescription, privacy: .public)); using fast recognition.")
            }
        }
        return try await perform(on: image, level: .fast, timeout: nil)
    }

    public func recognizeText(in image: CGImage) async throws -> [RecognizedTextBlock] {
        try await recognize(in: image).textBlocks
    }

    public func detectBarcodes(in image: CGImage) async throws -> [DetectedBarcode] {
        try await recognize(in: image, recognitionLevel: .fast).barcodes
    }

    // MARK: - Execution

    private struct RecognitionTimeout: Error {
        let seconds: TimeInterval
    }

    private var currentAccurateState: AccurateState {
        lock.lock(); defer { lock.unlock() }
        return accurateState
    }

    private func setAccurateState(_ state: AccurateState) {
        lock.lock(); accurateState = state; lock.unlock()
    }

    private static func probeImage() -> CGImage? {
        guard let context = CGContext(
            data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        return context.makeImage()
    }

    private func perform(on image: CGImage, level: VNRequestTextRecognitionLevel, timeout: TimeInterval?) async throws -> RecognitionResult {
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = level
        textRequest.usesLanguageCorrection = level == .accurate
        let barcodeRequest = VNDetectBarcodesRequest()

        return try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeGate()

            queue.async {
                do {
                    try VNImageRequestHandler(cgImage: image, options: [:]).perform([textRequest, barcodeRequest])
                    let result = Self.makeResult(textRequest: textRequest, barcodeRequest: barcodeRequest)
                    if gate.claim() { continuation.resume(returning: result) }
                } catch {
                    if gate.claim() { continuation.resume(throwing: error) }
                }
            }

            if let timeout = timeout {
                queue.asyncAfter(deadline: .now() + timeout) {
                    guard gate.claim() else { return }
                    textRequest.cancel()
                    barcodeRequest.cancel()
                    continuation.resume(throwing: RecognitionTimeout(seconds: timeout))
                }
            }
        }
    }

    private static func makeResult(textRequest: VNRecognizeTextRequest, barcodeRequest: VNDetectBarcodesRequest) -> RecognitionResult {
        let blocks = (textRequest.results ?? []).compactMap { observation -> RecognizedTextBlock? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return RecognizedTextBlock(text: text, confidence: candidate.confidence, boundingBox: normalizedRect(fromVision: observation.boundingBox))
        }

        let barcodes = (barcodeRequest.results ?? []).compactMap { observation -> DetectedBarcode? in
            guard let payload = observation.payloadStringValue, !payload.isEmpty else { return nil }
            return DetectedBarcode(payload: payload, symbology: observation.symbology.rawValue, boundingBox: normalizedRect(fromVision: observation.boundingBox))
        }

        AppLogger.shared.recognition.info("Recognition finished: \(blocks.count) text blocks, \(barcodes.count) barcodes")
        return RecognitionResult(textBlocks: orderedForReading(blocks), barcodes: barcodes)
    }

    /// Ensures a continuation is resumed exactly once when racing completion against a timeout
    private final class ResumeGate: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false

        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }

    // MARK: - Helpers

    /// Converts a Vision bounding box (normalized, bottom-left origin) to the app's top-left normalized space
    public static func normalizedRect(fromVision box: CGRect) -> NormalizedRect {
        let minX = min(max(box.minX, 0), 1)
        let maxX = min(max(box.maxX, 0), 1)
        let minY = min(max(box.minY, 0), 1)
        let maxY = min(max(box.maxY, 0), 1)
        return NormalizedRect(x: minX, y: 1.0 - maxY, width: maxX - minX, height: maxY - minY)
    }

    /// Sorts blocks top-to-bottom, then left-to-right for blocks sharing a visual line
    public static func orderedForReading(_ blocks: [RecognizedTextBlock]) -> [RecognizedTextBlock] {
        blocks.sorted { a, b in
            let aMid = a.boundingBox.origin.y + a.boundingBox.height / 2
            let bMid = b.boundingBox.origin.y + b.boundingBox.height / 2
            let lineTolerance = min(a.boundingBox.height, b.boundingBox.height) / 2
            if abs(aMid - bMid) <= lineTolerance {
                return a.boundingBox.origin.x < b.boundingBox.origin.x
            }
            return aMid < bMid
        }
    }

    /// Trims each line, collapses runs of internal whitespace, and drops empty lines
    public static func normalizeText(_ lines: [String]) -> String {
        lines
            .map { line in
                line.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
