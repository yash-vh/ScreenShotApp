import AppKit
import Foundation
import ImageIO
import Network
import UniformTypeIdentifiers

/// Orchestrates share uploads: metadata stripping, short links, provider calls, history records,
/// delete tokens in the Keychain, and an offline queue that retries when the network returns.
@MainActor
public final class UploadService: ObservableObject {
    public static let shared = UploadService()

    public typealias ProviderFactory = @MainActor (CloudProviderType) throws -> CloudStorageProvider

    @Published public private(set) var activeUploads = 0

    private let history: HistoryStore
    private let secrets: SecretStore
    private let config: AppConfiguration
    private let makeProvider: ProviderFactory
    /// Builds the short-link client; replaced in tests to avoid the network
    var makeShortener: (LinkShortener) -> LinkShortenerService = { LinkShortenerService(kind: $0) }
    public let queueDirectory: URL
    private var pathMonitor: NWPathMonitor?
    private var isRetrying = false

    public init(
        history: HistoryStore? = nil,
        secrets: SecretStore = KeychainStore.shared,
        config: AppConfiguration? = nil,
        queueDirectory: URL? = nil,
        providerFactory: ProviderFactory? = nil
    ) {
        let history = history ?? .shared
        let config = config ?? .shared
        self.history = history
        self.secrets = secrets
        self.config = config
        self.queueDirectory = queueDirectory ?? history.rootDirectory.appendingPathComponent("UploadQueue", isDirectory: true)
        self.makeProvider = providerFactory ?? { type in try UploadService.defaultProvider(for: type, config: config, secrets: secrets) }
        try? FileManager.default.createDirectory(at: self.queueDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Provider Resolution

    static func defaultProvider(for type: CloudProviderType, config: AppConfiguration, secrets: SecretStore) throws -> CloudStorageProvider {
        switch type {
        case .imgbb:
            guard let key = try secrets.value(for: KeychainStore.Account.imgbbAPIKey)?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
                throw AppError.invalidConfiguration(key: "ImgBB API key", reason: "Get a free key at api.imgbb.com and paste it in Settings › Storage & Cloud.")
            }
            return ImgBBProvider(apiKey: key)
        case .s3Compatible:
            let region = config.s3Region.trimmingCharacters(in: .whitespaces).isEmpty ? "us-east-1" : config.s3Region.trimmingCharacters(in: .whitespaces)
            var endpointString = config.s3Endpoint.trimmingCharacters(in: .whitespaces)
            if endpointString.isEmpty { endpointString = "https://s3.\(region).amazonaws.com" }
            if !endpointString.contains("://") { endpointString = "https://" + endpointString }
            let bucket = config.s3Bucket.trimmingCharacters(in: .whitespaces)
            guard let endpoint = URL(string: endpointString), endpoint.host != nil, !bucket.isEmpty,
                  let keyID = try secrets.value(for: KeychainStore.Account.s3AccessKeyID), !keyID.isEmpty,
                  let secret = try secrets.value(for: KeychainStore.Account.s3SecretAccessKey), !secret.isEmpty else {
                throw AppError.invalidConfiguration(key: "S3", reason: "Enter the endpoint, bucket and access keys in Settings › Storage & Cloud.")
            }
            let publicBaseString = config.s3PublicBaseURL.trimmingCharacters(in: .whitespaces)
            let publicBase = publicBaseString.isEmpty ? nil : URL(string: publicBaseString.contains("://") ? publicBaseString : "https://" + publicBaseString)
            return S3Provider(endpoint: endpoint, bucket: bucket, region: region, accessKeyID: keyID.trimmingCharacters(in: .whitespaces), secretAccessKey: secret, publicBaseURL: publicBase)
        case .legacy:
            throw AppError.invalidConfiguration(key: type.displayName, reason: "YnShot now uploads to ImgBB or Amazon S3 only.")
        }
    }

    // MARK: - Payload

    /// Re-encode budget per provider; S3 has no practical cap, so it shares the default
    public nonisolated static let defaultMaxUploadBytes = 10 * 1_048_576

    static func maxUploadBytes(for type: CloudProviderType) -> Int {
        type == .imgbb ? ImgBBProvider.maxUploadBytes : defaultMaxUploadBytes
    }

    /// Re-encodes pixels only (no EXIF / TIFF / window metadata). Falls back to JPEG when PNG exceeds the size limit.
    public nonisolated static func makePayload(from image: CGImage, expiry: UploadExpiry, maxBytes: Int = UploadService.defaultMaxUploadBytes) -> UploadPayload? {
        guard let png = encode(image, type: .png, properties: [:]) else { return nil }
        if png.count <= maxBytes {
            return UploadPayload(data: png, contentType: "image/png", fileExtension: "png", expiry: expiry)
        }
        for quality in [0.85, 0.7, 0.5] {
            if let jpeg = encode(image, type: .jpeg, properties: [kCGImageDestinationLossyCompressionQuality: quality]), jpeg.count <= maxBytes {
                return UploadPayload(data: jpeg, contentType: "image/jpeg", fileExtension: "jpg", expiry: expiry)
            }
        }
        return UploadPayload(data: png, contentType: "image/png", fileExtension: "png", expiry: expiry)
    }

    private nonisolated static func encode(_ image: CGImage, type: UTType, properties: [CFString: Any]) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    nonisolated static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - Core Upload

    /// Uploads `image` (or the asset's file) and records the result on the asset.
    /// Throws `AppError.networkUnavailable` when offline — the upload is then queued and retried automatically.
    @discardableResult
    public func upload(assetId: UUID, image: CGImage? = nil, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> UploadRecord {
        guard let providerType = config.uploadProvider else { throw AppError.cloudProviderNotConfigured }
        let provider = try makeProvider(providerType)
        guard let asset = history.asset(id: assetId) else { throw AppError.assetCorrupted(id: assetId) }
        // Decode + encode off the main thread so the HUD stays responsive
        let fileURL = asset.originalFileURL
        let expiry = config.uploadExpiry
        let maxBytes = Self.maxUploadBytes(for: providerType)
        let encoded = await Task.detached(priority: .userInitiated) { () -> UploadPayload? in
            guard let source = image ?? Self.loadImage(at: fileURL) else { return nil }
            return Self.makePayload(from: source, expiry: expiry, maxBytes: maxBytes)
        }.value
        guard let payload = encoded else {
            throw AppError.fileReadFailed(path: fileURL.lastPathComponent)
        }

        let record = UploadRecord(providerType: providerType, remoteKey: "", status: .inProgress, capabilities: provider.capabilities)
        history.mutate(id: assetId) { $0.uploadRecords.append(record) }
        let queued = queueFile(for: record.id, ext: payload.fileExtension)
        let queuedData = payload.data
        await Task.detached(priority: .utility) { try? queuedData.write(to: queued, options: .atomic) }.value
        return try await perform(recordId: record.id, assetId: assetId, payload: payload, provider: provider, queuedFile: queued, progress: progress)
    }

    private func perform(recordId: UUID, assetId: UUID, payload: UploadPayload, provider: CloudStorageProvider, queuedFile: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> UploadRecord {
        activeUploads += 1
        defer { activeUploads -= 1 }
        setRecord(recordId, on: assetId) { $0.status = .inProgress; $0.errorMessage = nil }

        do {
            let result = try await provider.upload(payload, progress: progress)
            if let token = result.deleteToken {
                try? secrets.set(token, for: KeychainStore.Account.deleteToken(for: recordId))
            }
            try? FileManager.default.removeItem(at: queuedFile)
            let shortURL = await shortened(result.shareURL)
            let record = setRecord(recordId, on: assetId) {
                $0.status = .completed
                $0.remoteKey = result.remoteKey
                $0.shareURL = shortURL ?? result.shareURL
                $0.originalURL = shortURL == nil ? nil : result.shareURL
                $0.uploadedAt = Date()
                $0.expiresAt = result.expiresAt
            }
            AppLogger.shared.sharing.info("Upload completed via \(provider.type.displayName, privacy: .public)")
            return record ?? UploadRecord(providerType: provider.type, remoteKey: result.remoteKey, shareURL: result.shareURL, status: .completed)
        } catch where Self.isConnectivityError(error) {
            setRecord(recordId, on: assetId) { $0.status = .pending; $0.errorMessage = "Waiting for network" }
            AppLogger.shared.sharing.notice("Upload queued until the network is available")
            startNetworkMonitoring()
            throw AppError.networkUnavailable
        } catch {
            try? FileManager.default.removeItem(at: queuedFile)
            setRecord(recordId, on: assetId) { $0.status = .failed; $0.errorMessage = error.localizedDescription }
            AppLogger.shared.sharing.error("Upload failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Short link for `url`, or nil when shortening is off or the shortener fails (the full link is used then)
    private func shortened(_ url: URL) async -> URL? {
        guard config.linkShortener != .off else { return nil }
        do {
            return try await makeShortener(config.linkShortener).shorten(url)
        } catch {
            AppLogger.shared.sharing.notice("Link shortener failed, using full link: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @discardableResult
    private func setRecord(_ recordId: UUID, on assetId: UUID, _ change: (inout UploadRecord) -> Void) -> UploadRecord? {
        var updated: UploadRecord?
        history.mutate(id: assetId) { asset in
            guard let index = asset.uploadRecords.firstIndex(where: { $0.id == recordId }) else { return }
            change(&asset.uploadRecords[index])
            updated = asset.uploadRecords[index]
        }
        return updated
    }

    static func isConnectivityError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost, .dataNotAllowed, .internationalRoamingOff:
            return true
        default:
            return false
        }
    }

    private func queueFile(for recordId: UUID, ext: String) -> URL {
        queueDirectory.appendingPathComponent("\(recordId.uuidString).\(ext)")
    }

    // MARK: - Delete

    public func deleteUpload(assetId: UUID, recordId: UUID) async throws {
        guard let record = history.asset(id: assetId)?.uploadRecords.first(where: { $0.id == recordId }) else { return }
        let account = KeychainStore.Account.deleteToken(for: recordId)
        if record.status == .completed {
            let provider = try makeProvider(record.providerType)
            try await provider.delete(remoteKey: record.remoteKey, deleteToken: try? secrets.value(for: account))
        }
        secrets.remove(account)
        for ext in ["png", "jpg"] { try? FileManager.default.removeItem(at: queueFile(for: recordId, ext: ext)) }
        setRecord(recordId, on: assetId) { $0.status = .deleted; $0.shareURL = nil }
        AppLogger.shared.sharing.info("Deleted upload \(record.remoteKey, privacy: .private)")
    }

    // MARK: - Offline Queue

    /// Uploads every record left pending while offline. Returns the records that completed.
    @discardableResult
    public func retryPendingUploads() async -> [UploadRecord] {
        guard !isRetrying else { return [] }
        isRetrying = true
        defer { isRetrying = false }

        var completed: [UploadRecord] = []
        for asset in history.assets {
            for record in asset.uploadRecords where record.status == .pending {
                guard let provider = try? makeProvider(record.providerType) else { continue }
                let candidates = [("png", "image/png"), ("jpg", "image/jpeg")].map { (queueFile(for: record.id, ext: $0.0), $0) }
                guard let (file, kind) = candidates.first(where: { FileManager.default.fileExists(atPath: $0.0.path) }),
                      let data = try? Data(contentsOf: file) else {
                    setRecord(record.id, on: asset.id) { $0.status = .failed; $0.errorMessage = "Queued image was removed" }
                    continue
                }
                let payload = UploadPayload(data: data, contentType: kind.1, fileExtension: kind.0, expiry: config.uploadExpiry)
                do {
                    let done = try await perform(recordId: record.id, assetId: asset.id, payload: payload, provider: provider, queuedFile: file, progress: { _ in })
                    completed.append(done)
                } catch AppError.networkUnavailable {
                    return completed
                } catch {
                    continue
                }
            }
        }
        return completed
    }

    public var hasPendingUploads: Bool {
        history.assets.contains { $0.uploadRecords.contains { $0.status == .pending } }
    }

    /// Watches connectivity while uploads are queued; stops once the queue drains
    public func startNetworkMonitoring() {
        guard pathMonitor == nil, hasPendingUploads else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let done = await self.retryPendingUploads()
                if let first = done.first, let url = first.shareURL {
                    UploadHUD.shared.showQueuedCompletion(url: url, count: done.count)
                }
                if !self.hasPendingUploads {
                    self.pathMonitor?.cancel()
                    self.pathMonitor = nil
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.screenshotapp.upload-network"))
        pathMonitor = monitor
    }

    // MARK: - User-Facing Flow

    /// Entry point for ⌘U / Upload buttons: uploads straight away, shows progress and copies the link
    public func requestUpload(assetId: UUID, image: CGImage? = nil) {
        guard let providerType = config.uploadProvider else {
            let alert = NSAlert()
            alert.messageText = "Choose where to upload"
            alert.informativeText = "Uploading is off. Pick ImgBB or your own S3 bucket in Settings › Storage & Cloud to get instant share links."
            alert.addButton(withTitle: "Use ImgBB")
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                config.uploadDestination = .imgbb
                requestUpload(assetId: assetId, image: image)
            case .alertSecondButtonReturn:
                AppCoordinator.shared.openSettings(tab: .storage)
            default:
                break
            }
            return
        }

        if providerType == .imgbb, !ensureImgBBKey() { return }

        // Missing credentials are a setup problem, not an upload failure: send the user to Settings
        do {
            _ = try makeProvider(providerType)
        } catch {
            let alert = NSAlert()
            alert.messageText = "\(providerType.displayName) isn't set up yet"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                AppCoordinator.shared.openSettings(tab: .storage)
            }
            return
        }

        let hud = UploadHUD.shared
        hud.showProgress(providerName: providerType.displayName)
        Task { @MainActor in
            do {
                let record = try await upload(assetId: assetId, image: image) { fraction in
                    Task { @MainActor in hud.updateProgress(fraction) }
                }
                if let url = record.shareURL {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(url.absoluteString, forType: .string)
                    let deletePage = record.capabilities.supportsDelete ? nil : (try? secrets.value(for: KeychainStore.Account.deleteToken(for: record.id))).flatMap { $0.flatMap(URL.init(string:)) }
                    hud.showSuccess(url: url, expiresAt: record.expiresAt, canDelete: record.capabilities.supportsDelete, deletePageURL: deletePage) { [weak self] in
                        Task { @MainActor in
                            do {
                                try await self?.deleteUpload(assetId: assetId, recordId: record.id)
                                CaptureHUD.shared.show(title: "Upload deleted", detail: "The link no longer works.", symbol: "trash.fill")
                            } catch {
                                CaptureHUD.shared.show(title: "Couldn't delete upload", detail: error.localizedDescription, symbol: "exclamationmark.triangle.fill")
                            }
                        }
                    }
                }
            } catch AppError.networkUnavailable {
                hud.showMessage(title: "You're offline", detail: "The upload will start automatically when you reconnect.", symbol: "wifi.slash")
            } catch {
                hud.showMessage(title: "Upload failed", detail: error.localizedDescription, symbol: "exclamationmark.icloud.fill")
            }
        }
    }

    /// Settings "Test Upload": sends a tiny image to the chosen provider and returns its (possibly shortened) link.
    /// The test object is removed again where the provider supports deleting.
    public func testCurrentDestination() async throws -> URL {
        guard let providerType = config.uploadProvider else { throw AppError.cloudProviderNotConfigured }
        let provider = try makeProvider(providerType)
        let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 1, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        guard let image = context?.makeImage(), let payload = Self.makePayload(from: image, expiry: .oneDay) else {
            throw AppError.cloudUploadFailed(provider: providerType.displayName, reason: "Could not create the test image.")
        }
        let result = try await provider.upload(payload) { _ in }
        if provider.capabilities.supportsDelete {
            try? await provider.delete(remoteKey: result.remoteKey, deleteToken: result.deleteToken)
        }
        return await shortened(result.shareURL) ?? result.shareURL
    }

    /// Asks for an ImgBB API key inline when none is saved, so the first upload needs no trip to Settings
    private func ensureImgBBKey() -> Bool {
        if let key = try? secrets.value(for: KeychainStore.Account.imgbbAPIKey), !key.trimmingCharacters(in: .whitespaces).isEmpty {
            return true
        }
        let alert = NSAlert()
        alert.messageText = "Add your ImgBB API key"
        alert.informativeText = "Uploads go to ImgBB. Create a free key at api.imgbb.com, then paste it below. It's stored in your Keychain."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "API key"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save & Upload")
        alert.addButton(withTitle: "Get a Key")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, (try? secrets.set(key, for: KeychainStore.Account.imgbbAPIKey)) != nil else { return false }
            return true
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(URL(string: "https://api.imgbb.com/")!)
            return false
        default:
            return false
        }
    }
}
