import AppKit
import AVFoundation
import Foundation
import ImageIO
import SwiftData

/// Disk usage of everything the history knows about
public struct StorageUsage: Equatable, Sendable {
    /// App-managed captures in Application Support (deleted on cleanup)
    public var cacheBytes: Int64
    /// Generated Library thumbnails
    public var thumbnailBytes: Int64
    /// Captures saved into the user's own folder (never deleted by cleanup)
    public var savedBytes: Int64
    /// SwiftData store files
    public var databaseBytes: Int64

    public var totalBytes: Int64 { cacheBytes + thumbnailBytes + savedBytes + databaseBytes }
    /// Bytes the app may reclaim without touching user-chosen folders
    public var reclaimableBytes: Int64 { cacheBytes + thumbnailBytes }
}

/// Persistent, searchable capture history backed by SwiftData.
/// Owns the app-managed media folder in `~/Library/Application Support/com.screenshotapp.mac`.
@MainActor
public final class HistoryStore: ObservableObject {
    public static let shared = HistoryStore()

    /// Newest first
    @Published public private(set) var assets: [ScreenshotAsset] = []

    public let rootDirectory: URL
    public let capturesDirectory: URL
    public let thumbnailsDirectory: URL
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let thumbnailCache = NSCache<NSUUID, NSImage>()

    /// - Parameters:
    ///   - rootDirectory: folder holding the store, captures and thumbnails; defaults to Application Support
    ///   - inMemory: keep the SwiftData store in memory (tests)
    public init(rootDirectory: URL? = nil, inMemory: Bool = false) {
        let root = rootDirectory ?? AppConfiguration.shared.appSupportDirectory()
        self.rootDirectory = root
        self.capturesDirectory = root.appendingPathComponent("Captures", isDirectory: true)
        self.thumbnailsDirectory = root.appendingPathComponent("Thumbnails", isDirectory: true)
        for dir in [root, capturesDirectory, thumbnailsDirectory] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let configuration = inMemory
            ? ModelConfiguration(isStoredInMemoryOnly: true)
            : ModelConfiguration(url: root.appendingPathComponent("History.store"))
        do {
            container = try ModelContainer(for: AssetRecord.self, configurations: configuration)
        } catch {
            // A corrupt store must never block capturing; fall back to an in-memory history for this session
            AppLogger.shared.storage.error("History store unavailable, using in-memory fallback: \(error.localizedDescription, privacy: .public)")
            container = try! ModelContainer(for: AssetRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        reload()
    }

    // MARK: - Queries

    public func reload() {
        let descriptor = FetchDescriptor<AssetRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        assets = ((try? context.fetch(descriptor)) ?? []).map(\.asset)
    }

    public func asset(id: UUID) -> ScreenshotAsset? {
        assets.first { $0.id == id }
    }

    public func search(_ query: HistoryQuery) -> [ScreenshotAsset] {
        query.apply(to: assets)
    }

    /// Whether the file lives in the app-managed cache (and may be deleted with its record)
    public func isManaged(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(capturesDirectory.standardizedFileURL.path + "/")
    }

    // MARK: - Mutations

    public func add(_ asset: ScreenshotAsset) {
        context.insert(AssetRecord(asset: asset))
        save()
        assets.insert(asset, at: 0)
        enforceCacheQuota()
    }

    public func update(_ asset: ScreenshotAsset) {
        guard let record = record(id: asset.id) else { return }
        record.apply(asset)
        save()
        if let index = assets.firstIndex(where: { $0.id == asset.id }) {
            assets[index] = asset
        }
    }

    /// Read-modify-write helper; returns the updated asset
    @discardableResult
    public func mutate(id: UUID, _ change: (inout ScreenshotAsset) -> Void) -> ScreenshotAsset? {
        guard var asset = asset(id: id) else { return nil }
        change(&asset)
        asset.modifiedAt = Date()
        update(asset)
        return asset
    }

    /// Removes records. App-managed files are always deleted; files in user folders are moved to the Trash only when asked.
    public func remove(ids: Set<UUID>, trashUserFiles: Bool = false) {
        for id in ids {
            guard let record = record(id: id) else { continue }
            let asset = record.asset
            if isManaged(asset.originalFileURL) {
                try? FileManager.default.removeItem(at: asset.originalFileURL)
            } else if trashUserFiles {
                try? FileManager.default.trashItem(at: asset.originalFileURL, resultingItemURL: nil)
            }
            removeThumbnail(for: id)
            context.delete(record)
        }
        save()
        assets.removeAll { ids.contains($0.id) }
    }

    // MARK: - Missing File Recovery

    /// Re-checks every record against the file system; returns how many files are missing
    @discardableResult
    public func refreshAvailability() -> Int {
        var missing = 0
        for record in (try? context.fetch(FetchDescriptor<AssetRecord>())) ?? [] {
            let exists = FileManager.default.fileExists(atPath: record.originalFilePath)
            if !exists { missing += 1 }
            if record.isAvailableLocally != exists {
                record.isAvailableLocally = exists
            }
        }
        save()
        reload()
        return missing
    }

    /// Deletes records whose file no longer exists; returns how many were pruned
    @discardableResult
    public func pruneMissing() -> Int {
        refreshAvailability()
        let stale = Set(assets.filter { !$0.isAvailableLocally }.map(\.id))
        remove(ids: stale)
        AppLogger.shared.storage.info("Pruned \(stale.count) stale history records")
        return stale.count
    }

    /// Points a record at a file the user located after it was moved
    public func relocate(id: UUID, to url: URL) {
        mutate(id: id) { asset in
            asset.originalFileURL = url
            asset.isAvailableLocally = FileManager.default.fileExists(atPath: url.path)
            asset.fileSizeBytes = Self.fileSize(at: url)
        }
        removeThumbnail(for: id)
    }

    // MARK: - Storage Quota & Cleanup

    public func storageUsage() -> StorageUsage {
        let savedBytes = assets
            .filter { $0.isAvailableLocally && !isManaged($0.originalFileURL) }
            .reduce(Int64(0)) { $0 + Self.fileSize(at: $1.originalFileURL) }
        let databaseBytes = ((try? FileManager.default.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("History.store") }
            .reduce(Int64(0)) { $0 + Self.fileSize(at: $1) }
        return StorageUsage(
            cacheBytes: Self.directorySize(capturesDirectory),
            thumbnailBytes: Self.directorySize(thumbnailsDirectory),
            savedBytes: savedBytes,
            databaseBytes: databaseBytes
        )
    }

    /// Deletes app-managed captures (and their records) older than `days`, or all of them when nil,
    /// plus every cached thumbnail. Returns the bytes freed. Files in user folders are never touched.
    @discardableResult
    public func cleanUpCache(olderThanDays days: Int? = nil, now: Date = Date()) -> Int64 {
        let before = storageUsage().reclaimableBytes
        let cutoff = days.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: now) } ?? .distantFuture
        let expired = Set(assets.filter { isManaged($0.originalFileURL) && $0.createdAt < cutoff }.map(\.id))
        remove(ids: expired)
        removeOrphanedCaptureFiles()
        try? FileManager.default.removeItem(at: thumbnailsDirectory)
        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        thumbnailCache.removeAllObjects()
        let freed = max(0, before - storageUsage().reclaimableBytes)
        AppLogger.shared.storage.info("Cache cleanup removed \(expired.count) captures, freed \(freed) bytes")
        return freed
    }

    /// Keeps the app-managed capture cache under the configured quota by dropping the oldest cached captures
    public func enforceCacheQuota(limitBytes: Int64? = nil) {
        let limit = limitBytes ?? Int64(AppConfiguration.shared.cacheQuotaMB) * 1_048_576
        guard limit > 0 else { return }
        var total = Self.directorySize(capturesDirectory)
        guard total > limit else { return }
        var evicted = Set<UUID>()
        for asset in assets.reversed() where isManaged(asset.originalFileURL) {
            guard total > limit else { break }
            total -= Self.fileSize(at: asset.originalFileURL)
            evicted.insert(asset.id)
        }
        remove(ids: evicted)
        AppLogger.shared.storage.notice("Cache quota exceeded; evicted \(evicted.count) oldest cached captures")
    }

    private func removeOrphanedCaptureFiles() {
        let known = Set(assets.map { $0.originalFileURL.standardizedFileURL.path })
        for file in (try? FileManager.default.contentsOfDirectory(at: capturesDirectory, includingPropertiesForKeys: nil)) ?? []
        where !known.contains(file.standardizedFileURL.path) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Thumbnails

    /// A small preview, generated once and cached on disk
    public func thumbnail(for asset: ScreenshotAsset, maxPixelSize: Int = 480) async -> NSImage? {
        if let cached = thumbnailCache.object(forKey: asset.id as NSUUID) { return cached }
        let thumbURL = thumbnailsDirectory.appendingPathComponent("\(asset.id.uuidString).png")
        if let image = NSImage(contentsOf: thumbURL) {
            thumbnailCache.setObject(image, forKey: asset.id as NSUUID)
            return image
        }
        guard asset.isAvailableLocally else { return nil }
        let cgThumb: CGImage
        if asset.mediaType == .video {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: asset.originalFileURL))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
            guard let frame = try? await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)).image else { return nil }
            cgThumb = frame
        } else {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            guard let source = CGImageSourceCreateWithURL(asset.originalFileURL as CFURL, nil),
                  let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            cgThumb = thumb
        }
        try? ScreenCaptureService.shared.saveImage(cgThumb, format: .png, jpegQuality: 1, to: thumbURL)
        let image = NSImage(cgImage: cgThumb, size: NSSize(width: cgThumb.width, height: cgThumb.height))
        thumbnailCache.setObject(image, forKey: asset.id as NSUUID)
        return image
    }

    private func removeThumbnail(for id: UUID) {
        thumbnailCache.removeObject(forKey: id as NSUUID)
        try? FileManager.default.removeItem(at: thumbnailsDirectory.appendingPathComponent("\(id.uuidString).png"))
    }

    // MARK: - Helpers

    private func record(id: UUID) -> AssetRecord? {
        var descriptor = FetchDescriptor<AssetRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func save() {
        do {
            try context.save()
        } catch {
            AppLogger.shared.storage.error("Failed to save history: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func fileSize(at url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
