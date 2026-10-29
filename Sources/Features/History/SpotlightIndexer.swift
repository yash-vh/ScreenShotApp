import AppKit
import Combine
import CoreSpotlight
import UniformTypeIdentifiers

/// Makes captures searchable in Spotlight: title, capture date, size and recognized (OCR) text.
/// Picking a result opens the capture in its default app (`AppDelegate` handles the activity).
@MainActor
public final class SpotlightIndexer {
    public static let shared = SpotlightIndexer()

    nonisolated static let domain = "com.screenmint.mac.captures"

    private let index = CSSearchableIndex(name: "ScreenMintCaptures")
    private var indexed: [UUID: Date] = [:]
    private var hasSynced = false
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    /// Starts mirroring the capture history into Spotlight (call once at launch)
    public func start(history: HistoryStore? = nil, config: AppConfiguration? = nil) {
        guard cancellables.isEmpty else { return }
        (history ?? .shared).$assets
            .combineLatest((config ?? .shared).$indexInSpotlight)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] assets, enabled in
                self?.sync(enabled ? assets : [])
            }
            .store(in: &cancellables)
    }

    private func sync(_ assets: [ScreenshotAsset]) {
        let visible = assets.filter(\.isAvailableLocally)
        let current = Dictionary(visible.map { ($0.id, $0.modifiedAt) }, uniquingKeysWith: { first, _ in first })
        let changed = visible.filter { indexed[$0.id] != $0.modifiedAt }.map(Self.item(for:))
        let removed = indexed.keys.filter { current[$0] == nil }.map(\.uuidString)
        let isFirstSync = !hasSynced
        hasSynced = true
        indexed = current

        let index = self.index
        let add = {
            guard !changed.isEmpty else { return }
            index.indexSearchableItems(changed) { error in
                if let error {
                    AppLogger.shared.storage.error("Spotlight indexing failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        if isFirstSync || visible.isEmpty {
            // Start clean so captures deleted while ScreenMint wasn't running (or indexing turned off) disappear
            index.deleteSearchableItems(withDomainIdentifiers: [Self.domain]) { _ in add() }
        } else if !removed.isEmpty {
            index.deleteSearchableItems(withIdentifiers: removed) { _ in add() }
        } else {
            add()
        }
    }

    nonisolated static func item(for asset: ScreenshotAsset) -> CSSearchableItem {
        let type: UTType
        switch asset.mediaType {
        case .image: type = asset.originalFileURL.pathExtension.lowercased() == "jpg" ? .jpeg : .png
        case .video: type = .mpeg4Movie
        case .gif: type = .gif
        }
        let attributes = CSSearchableItemAttributeSet(contentType: type)
        attributes.title = asset.title
        attributes.displayName = "\(asset.title) — \(asset.createdAt.formatted(date: .abbreviated, time: .shortened))"
        attributes.contentDescription = [asset.dimensionsString, asset.ocrText.map { String($0.prefix(300)) }]
            .compactMap { $0 }
            .joined(separator: " · ")
        attributes.textContent = asset.ocrText
        attributes.contentURL = asset.originalFileURL
        attributes.thumbnailURL = asset.mediaType == .image ? asset.originalFileURL : nil
        attributes.contentCreationDate = asset.createdAt
        attributes.contentModificationDate = asset.modifiedAt
        attributes.keywords = ["screenshot", "capture", AppBranding.appName] + asset.tags

        let item = CSSearchableItem(uniqueIdentifier: asset.id.uuidString, domainIdentifier: domain, attributeSet: attributes)
        item.expirationDate = .distantFuture
        return item
    }

    /// Opens the capture behind a Spotlight result; returns false for activities that aren't ours
    @discardableResult
    public static func open(_ activity: NSUserActivity) -> Bool {
        guard activity.activityType == CSSearchableItemActionType,
              let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let id = UUID(uuidString: identifier) else { return false }
        guard let asset = HistoryStore.shared.asset(id: id),
              FileManager.default.fileExists(atPath: asset.originalFileURL.path) else {
            CaptureHUD.shared.show(title: "Capture not found", detail: "It may have been moved or deleted.", symbol: "exclamationmark.triangle.fill")
            return true
        }
        NSWorkspace.shared.open(asset.originalFileURL)
        return true
    }
}
