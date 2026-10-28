import XCTest
@testable import ScreenshotApp

@MainActor
final class HistoryStoreTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeAsset(in store: HistoryStore, title: String = "Capture", managed: Bool = true, bytes: Int = 1024, createdAt: Date = Date(), ocr: String? = nil) throws -> ScreenshotAsset {
        let dir = managed ? store.capturesDirectory : root.appendingPathComponent("User", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString).png")
        try Data(repeating: 7, count: bytes).write(to: url)
        return ScreenshotAsset(title: title, createdAt: createdAt, originalFileURL: url, pixelWidth: 10, pixelHeight: 10, fileSizeBytes: Int64(bytes), ocrText: ocr)
    }

    func testAddPersistsAcrossReopen() throws {
        let store = HistoryStore(rootDirectory: root)
        var asset = try makeAsset(in: store, title: "Invoice", ocr: "Total $1,240.00")
        asset.uploadRecords = [UploadRecord(providerType: .s3Compatible, remoteKey: "abc", shareURL: URL(string: "https://s.example/abc"), status: .completed)]
        store.add(asset)

        let reopened = HistoryStore(rootDirectory: root)
        XCTAssertEqual(reopened.assets.count, 1)
        XCTAssertEqual(reopened.assets.first?.title, "Invoice")
        XCTAssertEqual(reopened.assets.first?.ocrText, "Total $1,240.00")
        XCTAssertEqual(reopened.assets.first?.uploadRecords.first?.remoteKey, "abc")
        XCTAssertEqual(reopened.assets.first?.originalFileURL, asset.originalFileURL)
    }

    func testMutateUpdatesRecord() throws {
        let store = HistoryStore(rootDirectory: root, inMemory: true)
        let asset = try makeAsset(in: store)
        store.add(asset)
        store.mutate(id: asset.id) { $0.ocrText = "hello"; $0.tags = ["bug"] }
        XCTAssertEqual(store.asset(id: asset.id)?.ocrText, "hello")
        XCTAssertEqual(store.asset(id: asset.id)?.tags, ["bug"])
    }

    func testRemoveDeletesManagedFilesButKeepsUserFiles() throws {
        let store = HistoryStore(rootDirectory: root, inMemory: true)
        let managed = try makeAsset(in: store, managed: true)
        let user = try makeAsset(in: store, managed: false)
        store.add(managed)
        store.add(user)

        store.remove(ids: [managed.id, user.id])

        XCTAssertTrue(store.assets.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: managed.originalFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: user.originalFileURL.path))
    }

    func testMissingFileDetectionPruneAndRelocate() throws {
        let store = HistoryStore(rootDirectory: root, inMemory: true)
        let a = try makeAsset(in: store, managed: false)
        let b = try makeAsset(in: store, managed: false)
        store.add(a)
        store.add(b)

        let moved = root.appendingPathComponent("moved.png")
        try FileManager.default.moveItem(at: a.originalFileURL, to: moved)
        try FileManager.default.removeItem(at: b.originalFileURL)

        XCTAssertEqual(store.refreshAvailability(), 2)
        XCTAssertEqual(store.search(HistoryQuery(media: .missing)).count, 2)

        store.relocate(id: a.id, to: moved)
        XCTAssertEqual(store.asset(id: a.id)?.isAvailableLocally, true)
        XCTAssertEqual(store.asset(id: a.id)?.originalFileURL, moved)

        XCTAssertEqual(store.pruneMissing(), 1)
        XCTAssertEqual(store.assets.map(\.id), [a.id])
    }

    func testCleanupOnlyRemovesOldCachedCaptures() throws {
        let store = HistoryStore(rootDirectory: root, inMemory: true)
        let old = try makeAsset(in: store, createdAt: Date().addingTimeInterval(-40 * 86_400))
        let recent = try makeAsset(in: store)
        let userOld = try makeAsset(in: store, managed: false, createdAt: Date().addingTimeInterval(-40 * 86_400))
        [old, recent, userOld].forEach(store.add)

        let freed = store.cleanUpCache(olderThanDays: 30)

        XCTAssertGreaterThanOrEqual(freed, 1024)
        XCTAssertEqual(Set(store.assets.map(\.id)), [recent.id, userOld.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: userOld.originalFileURL.path))
    }

    func testCacheQuotaEvictsOldestCachedCaptures() throws {
        let store = HistoryStore(rootDirectory: root, inMemory: true)
        let oldest = try makeAsset(in: store, bytes: 4000, createdAt: Date().addingTimeInterval(-300))
        let middle = try makeAsset(in: store, bytes: 4000, createdAt: Date().addingTimeInterval(-200))
        let newest = try makeAsset(in: store, bytes: 4000, createdAt: Date().addingTimeInterval(-100))
        [oldest, middle, newest].forEach(store.add)
        store.reload()

        store.enforceCacheQuota(limitBytes: 9000)

        XCTAssertEqual(Set(store.assets.map(\.id)), [middle.id, newest.id])
    }

    func testStorageUsageSplitsCacheAndSavedFiles() throws {
        let store = HistoryStore(rootDirectory: root, inMemory: true)
        store.add(try makeAsset(in: store, managed: true, bytes: 2000))
        store.add(try makeAsset(in: store, managed: false, bytes: 3000))
        let usage = store.storageUsage()
        XCTAssertEqual(usage.cacheBytes, 2000)
        XCTAssertEqual(usage.savedBytes, 3000)
    }
}

final class HistoryQueryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func asset(_ title: String, daysAgo: Double = 0, ocr: String? = nil, tags: [String] = [], media: MediaType = .image, uploaded: Bool = false, available: Bool = true) -> ScreenshotAsset {
        ScreenshotAsset(
            title: title,
            createdAt: now.addingTimeInterval(-daysAgo * 86_400),
            tags: tags,
            originalFileURL: URL(fileURLWithPath: "/tmp/\(title).png"),
            pixelWidth: 1, pixelHeight: 1, fileSizeBytes: 1,
            ocrText: ocr,
            mediaType: media,
            uploadRecords: uploaded ? [UploadRecord(providerType: .imgbb, remoteKey: "x", status: .completed)] : [],
            isAvailableLocally: available
        )
    }

    func testFullTextSearchAcrossTitleTagsAndOCR() {
        let assets = [
            asset("Invoice", ocr: "Total Amount Due"),
            asset("Figma", tags: ["design"]),
            asset("Slack", ocr: "standup notes")
        ]
        XCTAssertEqual(HistoryQuery(text: "amount").apply(to: assets, now: now).map(\.title), ["Invoice"])
        XCTAssertEqual(HistoryQuery(text: "DESIGN").apply(to: assets, now: now).map(\.title), ["Figma"])
        XCTAssertEqual(HistoryQuery(text: "standup slack").apply(to: assets, now: now).map(\.title), ["Slack"])
        XCTAssertTrue(HistoryQuery(text: "standup figma").apply(to: assets, now: now).isEmpty)
        XCTAssertEqual(HistoryQuery(text: "  ").apply(to: assets, now: now).count, 3)
    }

    func testTypeAndDateFilters() {
        let assets = [
            asset("today"),
            asset("video", daysAgo: 3, media: .video),
            asset("old", daysAgo: 20, uploaded: true),
            asset("ancient", daysAgo: 90, available: false)
        ]
        XCTAssertEqual(HistoryQuery(media: .recordings).apply(to: assets, now: now).map(\.title), ["video"])
        XCTAssertEqual(HistoryQuery(media: .uploaded).apply(to: assets, now: now).map(\.title), ["old"])
        XCTAssertEqual(HistoryQuery(media: .missing).apply(to: assets, now: now).map(\.title), ["ancient"])
        XCTAssertEqual(HistoryQuery(date: .today).apply(to: assets, now: now).map(\.title), ["today"])
        XCTAssertEqual(HistoryQuery(date: .lastSevenDays).apply(to: assets, now: now).map(\.title), ["today", "video"])
        XCTAssertEqual(HistoryQuery(date: .lastThirtyDays).apply(to: assets, now: now).count, 3)
    }

    func testDaySections() {
        let sections = HistoryQuery.sections(for: [asset("a"), asset("b"), asset("c", daysAgo: 1), asset("d", daysAgo: 5)], now: now)
        XCTAssertEqual(sections.map(\.title).prefix(2), ["Today", "Yesterday"])
        XCTAssertEqual(sections.map { $0.assets.count }, [2, 1, 1])
    }
}
