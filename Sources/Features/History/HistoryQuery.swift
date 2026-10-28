import Foundation

/// Filter + full-text search applied to the capture history.
/// Pure value logic so the Library window and tests share one implementation.
public struct HistoryQuery: Equatable, Sendable {
    public enum MediaFilter: String, CaseIterable, Identifiable, Sendable {
        case all = "All"
        case images = "Images"
        case recordings = "Recordings"
        case uploaded = "Uploaded"
        case missing = "Missing Files"

        public var id: String { rawValue }
    }

    public enum DateFilter: String, CaseIterable, Identifiable, Sendable {
        case anyTime = "Any Time"
        case today = "Today"
        case lastSevenDays = "Last 7 Days"
        case lastThirtyDays = "Last 30 Days"

        public var id: String { rawValue }
    }

    public var text: String
    public var media: MediaFilter
    public var date: DateFilter

    public init(text: String = "", media: MediaFilter = .all, date: DateFilter = .anyTime) {
        self.text = text
        self.media = media
        self.date = date
    }

    /// Whitespace-separated search terms; every term must appear in the title, a tag, or the OCR text
    var terms: [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    public func matches(_ asset: ScreenshotAsset, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch media {
        case .all: break
        case .images: guard asset.mediaType == .image else { return false }
        case .recordings: guard asset.mediaType != .image else { return false }
        case .uploaded: guard asset.uploadRecords.contains(where: { $0.status == .completed }) else { return false }
        case .missing: guard !asset.isAvailableLocally else { return false }
        }

        switch date {
        case .anyTime: break
        case .today:
            guard calendar.isDate(asset.createdAt, inSameDayAs: now) else { return false }
        case .lastSevenDays:
            guard let start = calendar.date(byAdding: .day, value: -7, to: now), asset.createdAt >= start else { return false }
        case .lastThirtyDays:
            guard let start = calendar.date(byAdding: .day, value: -30, to: now), asset.createdAt >= start else { return false }
        }

        let terms = self.terms
        guard !terms.isEmpty else { return true }
        let haystack = ([asset.title, asset.originalFileURL.lastPathComponent, asset.ocrText ?? ""] + asset.tags).joined(separator: "\n")
        return terms.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    public func apply(to assets: [ScreenshotAsset], now: Date = Date(), calendar: Calendar = .current) -> [ScreenshotAsset] {
        assets.filter { matches($0, now: now, calendar: calendar) }
    }

    /// Groups assets (already newest-first) into day sections for the Library grid
    public static func sections(for assets: [ScreenshotAsset], now: Date = Date(), calendar: Calendar = .current) -> [(title: String, assets: [ScreenshotAsset])] {
        var result: [(title: String, assets: [ScreenshotAsset])] = []
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        for asset in assets {
            let title: String
            if calendar.isDate(asset.createdAt, inSameDayAs: now) {
                title = "Today"
            } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(asset.createdAt, inSameDayAs: yesterday) {
                title = "Yesterday"
            } else {
                title = formatter.string(from: asset.createdAt)
            }
            if result.last?.title == title {
                result[result.count - 1].assets.append(asset)
            } else {
                result.append((title, [asset]))
            }
        }
        return result
    }
}
