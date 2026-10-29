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
    case password
    case date
    case address
    case secret
}

/// A sensitive span inside one line of recognized text
public struct SensitiveMatch: Sendable, Equatable {
    public var kind: SensitiveInfoKind
    public var range: Range<String.Index>
}

/// Finds sensitive information in screenshots, entirely on device: Vision reads the text, then
/// patterns pick out emails, phone numbers, card numbers (Luhn-checked) with expiry and CVV, dates, masked
/// passwords, postal addresses, IPs, IBANs and API keys / tokens. Form labels ("Password", "Mobile", …) also hide the value next to them.
public enum SensitiveInfoDetector {
    // MARK: - Text Matching

    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // Patterns are compile-time constants
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let months = #"(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?"#

    /// Form field names whose value is personal; the value may share the line or sit beside / below the label
    private static let fieldLabels = #"(?:e-?mail(?: address| id)?|password|passwd|pwd|passcode|pin|otp|one[ -]time (?:password|code)|verification code|(?:mobile|phone|cell|tel(?:ephone)?)(?: no\.?| number| #)?|contact (?:no\.?|number)|card(?:holder)?(?: number| no\.?| name)?|cvv2?|cvc2?|security code|exp(?:iry|iration)?(?: date)?|valid (?:thru|till|until)|d\.?o\.?b\.?|date of birth|birth ?date|birthday|account(?: number| no\.?)|ifsc|aadhaar(?: number| no\.?)?|pan(?: number| no\.?)?|ssn|username|user ?id|login|(?:(?:home|billing|shipping|delivery|permanent|current|residential|office|street|mailing|postal) )?address(?: line ?\d)?|street|city|landmark|locality|zip(?: ?code)?|pin ?code|postal ?code|post ?code)"#

    private static let addressLabel = regex(#"address"#, .caseInsensitive)

    private static let labelOnly = regex(#"^\s*"# + fieldLabels + #"\s*[:*]?\s*$"#, .caseInsensitive)

    private static let patterns: [(SensitiveInfoKind, NSRegularExpression, Int)] = {
        return [
            (.email, regex(#"[A-Z0-9._%+-]+ ?@ ?[A-Z0-9-]+(?:\.[A-Z0-9-]+)*\.[A-Z]{2,}"#, .caseInsensitive), 0),
            (.creditCard, regex(#"(?<!\d)(?:\d[ -]?){12,18}\d(?!\d)"#), 0),
            // Expiry and CVV next to their label: "Exp 12/30", "Valid thru 08/27", "CVV: 123"
            (.creditCard, regex(#"\b(?:exp(?:iry|iration)?(?: date)?|valid (?:thru|till|until))\.?\s*[:=]?\s*((?:0?[1-9]|1[0-2])\s?[/-]\s?(?:\d{4}|\d{2}))(?!\d)"#, .caseInsensitive), 1),
            (.creditCard, regex(#"\b(?:cvv2?|cvc2?|security code)\s*[:=]?\s*(\d{3,4})(?!\d)"#, .caseInsensitive), 1),
            // Mobile numbers: Indian 10-digit (optionally +91) and any "+country" number
            (.phoneNumber, regex(#"(?<![\d+])(?:(?:\+|00)?91[\s-]?)?[6-9]\d{4}[\s-]?\d{5}(?!\d)"#), 0),
            (.phoneNumber, regex(#"(?<![\d+])\+\d{1,3}[\s.-]?\(?\d{1,5}\)?(?:[\s.-]?\d{2,5}){1,4}(?!\d)"#), 0),
            // Dates: 12/05/2024, 2024-05-12, 12.05.24, 12 May 2024, May 12, 2024, May 2024, and month/year like 05/27
            (.date, regex(#"(?<![\d.])(?:\d{1,2}[/.-]\d{1,2}[/.-](?:\d{4}|\d{2})|\d{4}[/.-]\d{1,2}[/.-]\d{1,2})(?![\d.])"#), 0),
            (.date, regex(#"\b\d{1,2}(?:st|nd|rd|th)?[ -]"# + months + #"[ -,]*(?:\d{4}|'?\d{2})\b"#, .caseInsensitive), 0),
            (.date, regex(#"\b"# + months + #" \d{1,2}(?:st|nd|rd|th)?,? (?:\d{4}|'\d{2})\b"#, .caseInsensitive), 0),
            (.date, regex(#"\b"# + months + #",? \d{4}\b"#, .caseInsensitive), 0),
            (.date, regex(#"(?<![\d./-])(?:0[1-9]|1[0-2])\s?/\s?(?:20)?\d{2}(?![\d./-])"#), 0),
            // Street lines: a house / flat number followed by a street word ("221B Baker Street", "12, MG Road", "A-402 Shanti Nagar")
            // The words between are capitalized names, so prose like "3 people walked down the road" is left alone
            (.address, regex(#"(?:\b(?i:flat|apt|apartment|house|plot|unit|suite|block|bldg|building|shop|door) ?(?i:no\.?)?\s*[-#:]?\s*)?(?<![\w.])[A-Z]?-?\d{1,5}[A-Z]?(?:[/-]\d{1,5}[A-Z]?)?,?\s+(?:[A-Z][A-Za-z.'-]*,?\s+){0,4}?(?i:street|st\.|road|rd\.?|avenue|ave\.?|lane|marg|nagar|society|colony|sector|layout|boulevard|blvd\.?|highway|chowk|residency|apartments|towers?|heights|enclave|vihar|bagh|puram|wadi|gali)\b.*$"#), 0),
            // "Ahmedabad - 380015", "Ahmedabad, Gujarat 380015": city followed by a 6-digit Indian PIN
            (.address, regex(#"\b[A-Z][A-Za-z]+(?:[ ,]+[A-Z][A-Za-z]+){0,3}\s*[,-]?\s*[1-9]\d{2}\s?\d{3}(?!\d)"#), 0),
            // "Springfield, IL 62704", "London SW1A 1AA"
            (.address, regex(#"\b[A-Z][a-z]+,? [A-Z]{2} \d{5}(?:-\d{4})?\b"#), 0),
            (.address, regex(#"\b[A-Z]{1,2}\d[A-Z\d]? \d[A-Z]{2}\b"#), 0),
            // Masked password fields read as a row of bullets or asterisks
            (.password, regex(#"[•●◦∙⋅·*]{4,}"#), 0),
            (.password, regex(#"^\s*\.{6,}\s*$"#), 0),
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
            (.password, regex(#"(?:password|passwd|pwd|passcode|pin|otp)\s*[:=]\s*(\S{3,})"#, .caseInsensitive), 1),
            (.secret, regex(#"(?:secret|token|api[ _-]?key)\s*[:=]\s*(\S{4,})"#, .caseInsensitive), 1),
            // "Mobile: 98765 43210", "DOB: 1 Jan 1990", "Username: yash": hide everything after the label
            (.secret, regex(#"\b"# + fieldLabels + #"\s*[:=]\s*(\S.*?)\s*$"#, .caseInsensitive), 1),
            // Long random-looking tokens (letters and digits mixed, 32+ characters)
            (.secret, regex(#"\b(?=[A-Za-z0-9_-]*\d)(?=[A-Za-z0-9_-]*[A-Za-z])[A-Za-z0-9_-]{32,}\b"#), 0)
        ]
    }()

    private static let dataDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue | NSTextCheckingResult.CheckingType.address.rawValue
    )

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

        for result in dataDetector?.matches(in: text, range: whole) ?? [] {
            guard let range = Range(result.range, in: text) else { continue }
            if result.resultType == .address {
                found.append(SensitiveMatch(kind: .address, range: range))
                continue
            }
            // Phone numbers: require enough digits so years, prices and versions aren't hidden
            let digits = text[range].filter(\.isNumber).count
            if digits >= 7 { found.append(SensitiveMatch(kind: .phoneNumber, range: range)) }
        }

        return merged(found)
    }

    /// Luhn checksum over the digits of a card-number candidate
    /// True when `text` is only a form label such as "Password" or "Mobile number:", whose value sits beside or below it
    public static func isFieldLabel(_ text: String) -> Bool {
        labelOnly.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

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

        let lines: [(text: String, candidate: VNRecognizedText, rect: NormalizedRect)] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return (candidate.string, candidate, VisionService.normalizedRect(fromVision: observation.boundingBox))
        }

        var boxes: [NormalizedRect] = []
        for line in lines {
            for match in matches(in: line.text) {
                guard let box = try? line.candidate.boundingBox(for: match.range)?.boundingBox else { continue }
                boxes.append(padded(VisionService.normalizedRect(fromVision: box)))
            }
        }

        // A label on its own ("Password", "Mobile number") hides the field value read beside or below it;
        // "Address" also hides the lines that continue the address underneath
        let values = lines.filter { !isFieldLabel($0.text) }.map(\.rect)
        for label in lines where isFieldLabel(label.text) {
            guard let value = fieldValue(for: label.rect, among: values) else { continue }
            boxes.append(padded(value))
            guard addressLabel.firstMatch(in: label.text, range: NSRange(label.text.startIndex..., in: label.text)) != nil else { continue }
            for line in continuationLines(below: value, among: values) {
                boxes.append(padded(line))
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

    /// The nearest text right of `label` on the same row, else the nearest text just below it
    static func fieldValue(for label: NormalizedRect, among lines: [NormalizedRect]) -> NormalizedRect? {
        let labelMidY = label.origin.y + label.height / 2
        let labelMaxX = label.origin.x + label.width

        let sameRow = lines.filter { line in
            let midY = line.origin.y + line.height / 2
            return abs(midY - labelMidY) < label.height * 0.6
                && line.origin.x >= labelMaxX - label.height * 0.5
                && line.origin.x - labelMaxX < 0.35
        }
        if let right = sameRow.min(by: { $0.origin.x < $1.origin.x }) { return right }

        let labelMaxY = label.origin.y + label.height
        let below = lines.filter { line in
            let gap = line.origin.y - labelMaxY
            let overlapsColumn = line.origin.x < labelMaxX + 0.2 && line.origin.x + line.width > label.origin.x - 0.02
            return gap >= -label.height * 0.3 && gap < label.height * 3 && overlapsColumn
        }
        return below.min(by: { $0.origin.y < $1.origin.y })
    }

    /// Up to three more lines stacked under `first` with the same left edge, as in a multi-line address
    static func continuationLines(below first: NormalizedRect, among lines: [NormalizedRect]) -> [NormalizedRect] {
        var result: [NormalizedRect] = []
        var last = first
        while result.count < 3 {
            let lastMaxY = last.origin.y + last.height
            let next = lines
                .filter { line in
                    let gap = line.origin.y - lastMaxY
                    return gap >= -last.height * 0.3 && gap < last.height * 1.2 && abs(line.origin.x - last.origin.x) < 0.03
                }
                .min(by: { $0.origin.y < $1.origin.y })
            guard let next else { break }
            result.append(next)
            last = next
        }
        return result
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
