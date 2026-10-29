import Foundation
import CoreGraphics
import Vision

/// Kinds of personal or secret information that auto-blur hides
public enum SensitiveInfoKind: String, Sendable, CaseIterable {
    case email
    case phoneNumber
    case creditCard
    case ipAddress
    case socialSecurityNumber
    case iban
    case secret
}

/// A sensitive span inside one line of recognized text
public struct SensitiveMatch: Sendable, Equatable {
    public var kind: SensitiveInfoKind
    public var range: Range<String.Index>
}

/// Finds sensitive information in screenshots, entirely on device: Vision reads the text, then
/// patterns pick out emails, phone numbers, card numbers (Luhn-checked), IPs, IBANs and API keys / tokens.
public enum SensitiveInfoDetector {
    // MARK: - Text Matching

    private static let patterns: [(SensitiveInfoKind, NSRegularExpression, Int)] = {
        func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
            // Patterns are compile-time constants
            try! NSRegularExpression(pattern: pattern, options: options)
        }
        return [
            (.email, regex(#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, .caseInsensitive), 0),
            (.creditCard, regex(#"(?<!\d)(?:\d[ -]?){12,18}\d(?!\d)"#), 0),
            (.socialSecurityNumber, regex(#"(?<!\d)\d{3}-\d{2}-\d{4}(?!\d)"#), 0),
            (.ipAddress, regex(#"(?<![\d.])(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?![\d.])"#), 0),
            (.iban, regex(#"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){3,7}(?: ?[A-Z0-9]{1,3})?\b"#), 0),
            // Well-known key formats: OpenAI/Stripe, AWS, GitHub, Slack, Google, JWT
            (.secret, regex(#"\b(?:sk|pk|rk)[-_](?:live|test|proj|ant)?[-_]?[A-Za-z0-9_-]{16,}"#), 0),
            (.secret, regex(#"\bA(?:KIA|SIA)[0-9A-Z]{16}\b"#), 0),
            (.secret, regex(#"\bgh[pousr]_[A-Za-z0-9]{20,}\b"#), 0),
            (.secret, regex(#"\bxox[abposr]-[A-Za-z0-9-]{10,}"#), 0),
            (.secret, regex(#"\bAIza[0-9A-Za-z_-]{30,}"#), 0),
            (.secret, regex(#"\beyJ[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}"#), 0),
            // "password: hunter2", "token = abc…": hide the value only
            (.secret, regex(#"(?:password|passwd|pwd|passcode|secret|token|api[ _-]?key)\s*[:=]\s*(\S{4,})"#, .caseInsensitive), 1),
            // Long random-looking tokens (letters and digits mixed, 32+ characters)
            (.secret, regex(#"\b(?=[A-Za-z0-9_-]*\d)(?=[A-Za-z0-9_-]*[A-Za-z])[A-Za-z0-9_-]{32,}\b"#), 0)
        ]
    }()

    private static let phoneDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue)

    /// Sensitive spans in `text`, sorted and with overlaps merged
    public static func matches(in text: String) -> [SensitiveMatch] {
        let whole = NSRange(text.startIndex..., in: text)
        var found: [SensitiveMatch] = []

        for (kind, regex, group) in patterns {
            for result in regex.matches(in: text, range: whole) {
                let nsRange = result.range(at: group)
                guard nsRange.location != NSNotFound, let range = Range(nsRange, in: text) else { continue }
                if kind == .creditCard, !passesLuhn(String(text[range])) { continue }
                found.append(SensitiveMatch(kind: kind, range: range))
            }
        }

        // Phone numbers: require enough digits so years, prices and versions aren't hidden
        for result in phoneDetector?.matches(in: text, range: whole) ?? [] {
            guard let range = Range(result.range, in: text) else { continue }
            let digits = text[range].filter(\.isNumber).count
            if digits >= 7 { found.append(SensitiveMatch(kind: .phoneNumber, range: range)) }
        }

        return merged(found)
    }

    /// Luhn checksum over the digits of a card-number candidate
    public static func passesLuhn(_ candidate: String) -> Bool {
        let digits = candidate.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count) else { return false }
        var sum = 0
        for (index, digit) in digits.reversed().enumerated() {
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    private static func merged(_ matches: [SensitiveMatch]) -> [SensitiveMatch] {
        let sorted = matches.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var result: [SensitiveMatch] = []
        for match in sorted {
            if let last = result.last, match.range.lowerBound < last.range.upperBound {
                result[result.count - 1].range = last.range.lowerBound..<max(last.range.upperBound, match.range.upperBound)
            } else {
                result.append(match)
            }
        }
        return result
    }

    // MARK: - Image Detection

    /// Normalized (top-left origin) boxes covering every sensitive span of text in `image`
    public static func detectRegions(in image: CGImage) async throws -> [NormalizedRect] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try regions(in: image))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func regions(in image: CGImage) throws -> [NormalizedRect] {
        let observations: [VNRecognizedTextObservation]
        do {
            observations = try recognize(image, level: .accurate)
        } catch {
            // Some macOS builds can't load the accurate model; the fast one still finds most tokens
            observations = try recognize(image, level: .fast)
        }

        var boxes: [NormalizedRect] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            for match in matches(in: candidate.string) {
                guard let box = try? candidate.boundingBox(for: match.range)?.boundingBox else { continue }
                boxes.append(padded(VisionService.normalizedRect(fromVision: box)))
            }
        }
        AppLogger.shared.recognition.info("Auto-blur found \(boxes.count) sensitive region(s)")
        return boxes
    }

    private static func recognize(_ image: CGImage, level: VNRequestTextRecognitionLevel) throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        // Language correction "fixes" tokens and emails into words, which breaks matching
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return request.results ?? []
    }

    /// Grows a box slightly so glyph edges don't peek out from under the blur
    private static func padded(_ rect: NormalizedRect) -> NormalizedRect {
        let dx = rect.height * 0.25
        let dy = rect.height * 0.2
        let x = max(rect.origin.x - dx, 0)
        let y = max(rect.origin.y - dy, 0)
        return NormalizedRect(x: x, y: y, width: rect.width + dx * 2, height: rect.height + dy * 2)
    }
}
