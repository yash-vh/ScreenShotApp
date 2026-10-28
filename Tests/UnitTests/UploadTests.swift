import CoreGraphics
import XCTest
@testable import ScreenshotApp

/// Records requests and replies with queued canned responses
final class MockTransport: HTTPTransport, @unchecked Sendable {
    struct Reply { let status: Int; let body: Data }
    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [(request: URLRequest, body: Data?)] = []

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    func send(_ request: URLRequest, body: Data?, progress: (@Sendable (Double) -> Void)?) async throws -> (Data, HTTPURLResponse) {
        let reply = lock.withLock {
            requests.append((request, body))
            return replies.isEmpty ? Reply(status: 500, body: Data()) : replies.removeFirst()
        }
        progress?(1)
        return (reply.body, HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!)
    }
}

final class SigV4SignerTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_369_353_600) // 2013-05-24T00:00:00Z
    private let signer = SigV4Signer(accessKeyID: "AKIAIOSFODNN7EXAMPLE", secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", region: "us-east-1")

    /// AWS documentation example: "Authenticating Requests: Using Query Parameters"
    func testPresignedURLMatchesAWSReference() throws {
        let url = try XCTUnwrap(signer.presignedURL(URL(string: "https://examplebucket.s3.amazonaws.com/test.txt")!, expires: 86_400, date: date))
        let signature = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "X-Amz-Signature" }?.value
        XCTAssertEqual(signature, "aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404")
        XCTAssertTrue(url.absoluteString.contains("X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20130524%2Fus-east-1%2Fs3%2Faws4_request"))
    }

    /// AWS documentation example: "GET Object" with a Range header (header-based signing)
    func testHeaderSigningMatchesAWSReference() {
        var request = URLRequest(url: URL(string: "https://examplebucket.s3.amazonaws.com/test.txt")!)
        request.httpMethod = "GET"
        request.setValue("bytes=0-9", forHTTPHeaderField: "Range")
        signer.sign(&request, payloadHash: SigV4Signer.emptyPayloadHash, date: date)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41"
        )
    }

    func testCanonicalPathEncodesSpecialCharactersOnce() {
        XCTAssertEqual(SigV4Signer.canonicalPath(URL(string: "https://h/bucket/a%20b/c+d.png")!), "/bucket/a%20b/c%2Bd.png")
    }
}

final class ProviderTests: XCTestCase {
    private let payload = UploadPayload(data: Data(repeating: 1, count: 64), expiry: .sevenDays)

    func testImgBBParsesDirectLinkAndExpiry() async throws {
        let body = #"{"data":{"id":"2ndCYJK","url":"https://i.ibb.co/w04Prt6/shot.png","url_viewer":"https://ibb.co/2ndCYJK","delete_url":"https://ibb.co/2ndCYJK/670a7e48"},"success":true,"status":200}"#
        let transport = MockTransport([.init(status: 200, body: Data(body.utf8))])
        let provider = ImgBBProvider(apiKey: "k1", transport: transport)
        let result = try await provider.upload(payload) { _ in }
        XCTAssertEqual(result.shareURL.absoluteString, "https://i.ibb.co/w04Prt6/shot.png")
        XCTAssertEqual(result.remoteKey, "2ndCYJK")
        XCTAssertEqual(result.deleteToken, "https://ibb.co/2ndCYJK/670a7e48")
        XCTAssertNotNil(result.expiresAt)
        let query = URLComponents(url: try XCTUnwrap(transport.requests.first?.request.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first { $0.name == "key" }?.value, "k1")
        XCTAssertEqual(query?.first { $0.name == "expiration" }?.value, "604800")
        XCTAssertEqual(transport.requests.first?.request.httpMethod, "POST")
    }

    func testImgBBSurfacesAPIErrorMessage() async {
        let body = #"{"status_code":400,"error":{"message":"Invalid API v1 key.","code":100},"status_txt":"Bad Request"}"#
        let provider = ImgBBProvider(apiKey: "bad", transport: MockTransport([.init(status: 400, body: Data(body.utf8))]))
        do {
            _ = try await provider.upload(payload) { _ in }
            XCTFail("expected error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Invalid API v1 key"), error.localizedDescription)
        }
    }

    func testS3UploadSignsPutAndReturnsPresignedLink() async throws {
        let transport = MockTransport([.init(status: 200, body: Data())])
        let provider = S3Provider(endpoint: URL(string: "https://s3.example.com")!, bucket: "shots", region: "auto", accessKeyID: "AK", secretAccessKey: "SK", transport: transport)
        let result = try await provider.upload(payload) { _ in }

        let put = try XCTUnwrap(transport.requests.first?.request)
        XCTAssertEqual(put.httpMethod, "PUT")
        XCTAssertTrue(put.url!.path.hasPrefix("/shots/screenshots/"))
        XCTAssertTrue(put.value(forHTTPHeaderField: "Authorization")?.hasPrefix("AWS4-HMAC-SHA256 Credential=AK/") ?? false)
        XCTAssertEqual(put.value(forHTTPHeaderField: "x-amz-content-sha256"), SigV4Signer.sha256Hex(payload.data))
        XCTAssertTrue(result.shareURL.absoluteString.contains("X-Amz-Expires=604800"))
        XCTAssertEqual(result.remoteKey, String(put.url!.path.dropFirst("/shots/".count)))
    }

    func testS3UsesPublicBaseURLWhenConfigured() async throws {
        let transport = MockTransport([.init(status: 200, body: Data())])
        let provider = S3Provider(endpoint: URL(string: "https://s3.example.com")!, bucket: "shots", region: "auto", accessKeyID: "AK", secretAccessKey: "SK", publicBaseURL: URL(string: "https://cdn.example.com"), transport: transport)
        let result = try await provider.upload(payload) { _ in }
        XCTAssertEqual(result.shareURL.absoluteString, "https://cdn.example.com/\(result.remoteKey)")
        XCTAssertNil(result.expiresAt)
    }

    func testShareIDsAreUnguessableBase62() {
        let ids = (0..<500).map { _ in ShareID.random() }
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.allSatisfy { $0.count == 16 && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } })
    }
}

/// Provider whose behaviour each test scripts
final class FakeProvider: CloudStorageProvider, @unchecked Sendable {
    let type = CloudProviderType.imgbb
    let capabilities = ProviderCapabilities.s3Default
    var uploadError: Error?
    var uploads = 0
    var deleted: [(String, String?)] = []

    func upload(_ payload: UploadPayload, progress: @escaping @Sendable (Double) -> Void) async throws -> UploadResult {
        uploads += 1
        if let uploadError { throw uploadError }
        return UploadResult(remoteKey: "id\(uploads)", shareURL: URL(string: "https://s.example/id\(uploads)")!, expiresAt: nil, deleteToken: "token\(uploads)")
    }

    func delete(remoteKey: String, deleteToken: String?) async throws {
        deleted.append((remoteKey, deleteToken))
    }
}

@MainActor
final class UploadServiceTests: XCTestCase {
    private var root: URL!
    private var history: HistoryStore!
    private var config: AppConfiguration!
    private var secrets: InMemorySecretStore!
    private var provider: FakeProvider!
    private var service: UploadService!
    private var asset: ScreenshotAsset!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("UploadServiceTests-\(UUID().uuidString)", isDirectory: true)
        history = HistoryStore(rootDirectory: root, inMemory: true)
        let defaults = UserDefaults(suiteName: "UploadServiceTests-\(UUID().uuidString)")!
        config = AppConfiguration(defaults: defaults)
        config.storageMode = .managedCloud
        secrets = InMemorySecretStore()
        provider = FakeProvider()
        let provider = self.provider!
        service = UploadService(history: history, secrets: secrets, config: config, providerFactory: { _ in provider })

        let url = history.capturesDirectory.appendingPathComponent("shot.png")
        try ScreenCaptureService.shared.saveImage(Self.makeImage(), format: .png, jpegQuality: 1, to: url)
        asset = ScreenshotAsset(title: "Shot", originalFileURL: url, pixelWidth: 8, pixelHeight: 8, fileSizeBytes: 1)
        history.add(asset)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    static func makeImage() -> CGImage {
        let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return context.makeImage()!
    }

    func testShortenerReplacesShareLinkAndKeepsOriginal() async throws {
        config.linkShortener = .isgd
        let transport = MockTransport([.init(status: 200, body: Data("https://is.gd/abc12\n".utf8))])
        service.makeShortener = { LinkShortenerService(kind: $0, transport: transport) }

        let record = try await service.upload(assetId: asset.id)

        XCTAssertEqual(record.shareURL?.absoluteString, "https://is.gd/abc12")
        XCTAssertEqual(record.originalURL?.absoluteString, "https://s.example/id1")
        let query = try XCTUnwrap(transport.requests.first?.request.url?.absoluteString)
        XCTAssertTrue(query.hasPrefix("https://is.gd/create.php?format=simple&url=https%3A%2F%2Fs.example%2Fid1"), query)
    }

    func testShortenerFailureFallsBackToFullLink() async throws {
        config.linkShortener = .tinyurl
        let transport = MockTransport([.init(status: 400, body: Data("Error".utf8))])
        service.makeShortener = { LinkShortenerService(kind: $0, transport: transport) }

        let record = try await service.upload(assetId: asset.id)

        XCTAssertEqual(record.status, .completed)
        XCTAssertEqual(record.shareURL?.absoluteString, "https://s.example/id1")
        XCTAssertNil(record.originalURL)
    }

    func testShortenerEncodesPresignedQueryStrings() {
        let service = LinkShortenerService(kind: .tinyurl)
        let url = service.requestURL(for: URL(string: "https://b.s3.amazonaws.com/k.png?X-Amz-Date=1&X-Amz-Signature=ab")!)
        XCTAssertEqual(url?.absoluteString, "https://tinyurl.com/api-create.php?url=https%3A%2F%2Fb.s3.amazonaws.com%2Fk.png%3FX-Amz-Date%3D1%26X-Amz-Signature%3Dab")
    }

    func testUploadDestinationMapsToStorageModeAndProvider() {
        config.uploadDestination = .s3
        XCTAssertEqual(config.storageMode, .userOwned)
        XCTAssertEqual(config.uploadProvider, .s3Compatible)
        config.uploadDestination = .imgbb
        XCTAssertEqual(config.storageMode, .managedCloud)
        XCTAssertEqual(config.uploadProvider, .imgbb)
        XCTAssertEqual(config.uploadDestination, .imgbb)
        config.uploadDestination = .off
        XCTAssertNil(config.uploadProvider)
        XCTAssertEqual(config.uploadDestination, .off)
    }

    func testOnlyS3AndImgBBAreUploadDestinations() {
        XCTAssertEqual(UploadDestination.allCases, [.off, .imgbb, .s3])
        XCTAssertEqual(Set(UploadDestination.allCases.compactMap { dest -> CloudProviderType? in
            config.uploadDestination = dest
            return config.uploadProvider
        }), [.imgbb, .s3Compatible])
        XCTAssertEqual(CloudProviderType.allCases.filter(\.isImplemented), [.s3Compatible, .imgbb])
    }

    func testDestinationPersistsAcrossLaunches() {
        let suite = "UploadDestinationPersistence-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AppConfiguration(defaults: defaults)
        first.uploadDestination = .s3
        first.s3Bucket = "shots"
        first.s3Region = "eu-west-1"
        first.s3Endpoint = "https://s3.eu-west-1.amazonaws.com"
        first.s3PublicBaseURL = "https://cdn.example.com"

        let relaunched = AppConfiguration(defaults: defaults)
        XCTAssertEqual(relaunched.uploadDestination, .s3)
        XCTAssertEqual(relaunched.s3Bucket, "shots")
        XCTAssertEqual(relaunched.s3Region, "eu-west-1")
        XCTAssertEqual(relaunched.s3Endpoint, "https://s3.eu-west-1.amazonaws.com")
        XCTAssertEqual(relaunched.s3PublicBaseURL, "https://cdn.example.com")

        relaunched.uploadDestination = .imgbb
        XCTAssertEqual(AppConfiguration(defaults: defaults).uploadDestination, .imgbb)
    }

    func testRemovedProvidersDecodeAsLegacyAndCannotUpload() throws {
        let json = #"[{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","providerType":"imgur","remoteKey":"x","status":"completed","capabilities":{"supportsDelete":true,"supportsExpiringLinks":false,"supportsPasswordProtection":false,"supportsLinkRevocation":true,"supportsResumableUploads":false}}]"#
        let records = try JSONDecoder().decode([UploadRecord].self, from: Data(json.utf8))
        XCTAssertEqual(records.first?.providerType, .legacy)
        XCTAssertFalse(CloudProviderType.legacy.isImplemented)
        XCTAssertThrowsError(try UploadService.defaultProvider(for: .legacy, config: config, secrets: secrets))
    }

    func testSuccessfulUploadRecordsLinkAndStoresDeleteTokenInSecretStore() async throws {
        let record = try await service.upload(assetId: asset.id)

        XCTAssertEqual(record.status, .completed)
        XCTAssertEqual(record.shareURL?.absoluteString, "https://s.example/id1")
        let stored = try XCTUnwrap(history.asset(id: asset.id)?.uploadRecords.first)
        XCTAssertEqual(stored.status, .completed)
        XCTAssertEqual(try secrets.value(for: KeychainStore.Account.deleteToken(for: record.id)), "token1")
        let queued = try FileManager.default.contentsOfDirectory(atPath: service.queueDirectory.path)
        XCTAssertTrue(queued.isEmpty)
    }

    func testOfflineUploadIsQueuedAndRetried() async throws {
        provider.uploadError = URLError(.notConnectedToInternet)
        do {
            try await service.upload(assetId: asset.id)
            XCTFail("expected offline error")
        } catch AppError.networkUnavailable {}

        XCTAssertEqual(history.asset(id: asset.id)?.uploadRecords.first?.status, .pending)
        XCTAssertTrue(service.hasPendingUploads)

        provider.uploadError = nil
        let completed = await service.retryPendingUploads()

        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(history.asset(id: asset.id)?.uploadRecords.first?.status, .completed)
        XCTAssertFalse(service.hasPendingUploads)
    }

    func testNonNetworkFailureMarksRecordFailed() async {
        provider.uploadError = AppError.cloudUploadFailed(provider: "x", reason: "HTTP 500")
        _ = try? await service.upload(assetId: asset.id)
        XCTAssertEqual(history.asset(id: asset.id)?.uploadRecords.first?.status, .failed)
        XCTAssertFalse(service.hasPendingUploads)
    }

    func testDeleteUploadUsesStoredTokenAndClearsIt() async throws {
        let record = try await service.upload(assetId: asset.id)
        try await service.deleteUpload(assetId: asset.id, recordId: record.id)

        XCTAssertEqual(provider.deleted.first?.0, "id1")
        XCTAssertEqual(provider.deleted.first?.1, "token1")
        XCTAssertNil(try secrets.value(for: KeychainStore.Account.deleteToken(for: record.id)))
        XCTAssertEqual(history.asset(id: asset.id)?.uploadRecords.first?.status, .deleted)
        XCTAssertNil(history.asset(id: asset.id)?.uploadRecords.first?.shareURL)
    }

    func testLocalOnlyModeRefusesToUpload() async {
        config.storageMode = .localOnly
        do {
            try await service.upload(assetId: asset.id)
            XCTFail("uploads must be off in Local Only mode")
        } catch {
            XCTAssertEqual(error as? AppError, .cloudProviderNotConfigured)
            XCTAssertEqual(provider.uploads, 0)
        }
    }

    func testPayloadStripsMetadataAndFitsLimit() throws {
        let payload = try XCTUnwrap(UploadService.makePayload(from: Self.makeImage(), expiry: .oneDay))
        XCTAssertEqual(payload.contentType, "image/png")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(payload.data as CFData, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        // Only pixel geometry may remain; nothing that identifies the machine, app, time or place
        let exif = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        XCTAssertTrue(Set(exif.keys).isSubset(of: [kCGImagePropertyExifPixelXDimension, kCGImagePropertyExifPixelYDimension]))
        let tiff = properties?[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        XCTAssertNil(tiff[kCGImagePropertyTIFFSoftware])
        XCTAssertNil(tiff[kCGImagePropertyTIFFDateTime])
        XCTAssertNil(tiff[kCGImagePropertyTIFFImageDescription])
        XCTAssertNil(properties?[kCGImagePropertyGPSDictionary])
    }

    func testProviderResolutionRequiresConfiguration() {
        XCTAssertThrowsError(try UploadService.defaultProvider(for: .imgbb, config: config, secrets: secrets))
        try? secrets.set("key", for: KeychainStore.Account.imgbbAPIKey)
        XCTAssertNoThrow(try UploadService.defaultProvider(for: .imgbb, config: config, secrets: secrets))

        XCTAssertThrowsError(try UploadService.defaultProvider(for: .s3Compatible, config: config, secrets: secrets))
        config.s3Bucket = " b "
        config.s3Endpoint = "minio.example:9000"
        try? secrets.set("AK", for: KeychainStore.Account.s3AccessKeyID)
        try? secrets.set("SK", for: KeychainStore.Account.s3SecretAccessKey)
        XCTAssertNoThrow(try UploadService.defaultProvider(for: .s3Compatible, config: config, secrets: secrets))
    }

    func testResolvedProvidersMatchTheirType() throws {
        try secrets.set("key", for: KeychainStore.Account.imgbbAPIKey)
        config.s3Bucket = "b"
        try secrets.set("AK", for: KeychainStore.Account.s3AccessKeyID)
        try secrets.set("SK", for: KeychainStore.Account.s3SecretAccessKey)

        let imgbb = try UploadService.defaultProvider(for: .imgbb, config: config, secrets: secrets)
        XCTAssertTrue(imgbb is ImgBBProvider)
        XCTAssertEqual(imgbb.capabilities, .imgbbDefault)

        let s3 = try UploadService.defaultProvider(for: .s3Compatible, config: config, secrets: secrets)
        XCTAssertTrue(s3 is S3Provider)
        XCTAssertEqual(s3.capabilities, .s3Default)
    }

    func testS3DefaultsToAWSEndpointForRegion() throws {
        config.s3Bucket = "shots"
        config.s3Region = "eu-central-1"
        config.s3Endpoint = ""
        try secrets.set("AK", for: KeychainStore.Account.s3AccessKeyID)
        try secrets.set("SK", for: KeychainStore.Account.s3SecretAccessKey)
        let provider = try XCTUnwrap(UploadService.defaultProvider(for: .s3Compatible, config: config, secrets: secrets) as? S3Provider)
        XCTAssertEqual(provider.objectURL(for: "k.png").absoluteString, "https://s3.eu-central-1.amazonaws.com/shots/k.png")
    }

    func testImgBBUsesItsOwnSizeLimit() {
        XCTAssertEqual(UploadService.maxUploadBytes(for: .imgbb), ImgBBProvider.maxUploadBytes)
        XCTAssertEqual(UploadService.maxUploadBytes(for: .s3Compatible), UploadService.defaultMaxUploadBytes)
    }
}
