import Foundation

/// Upload to ImgBB (https://imgbb.com) with a free API key from https://api.imgbb.com.
/// Links point straight at the image file. ImgBB can auto-delete after an expiry but has no delete API,
/// so the `delete_url` web page is kept as the delete token for manual removal.
public struct ImgBBProvider: CloudStorageProvider {
    public let type = CloudProviderType.imgbb
    public let capabilities = ProviderCapabilities.imgbbDefault

    /// ImgBB rejects files above 32 MB
    public static let maxUploadBytes = 32 * 1_048_576
    /// Longest auto-delete window ImgBB accepts (180 days)
    static let maxExpirySeconds = 15_552_000

    private let apiKey: String
    private let apiBase: URL
    private let transport: HTTPTransport

    public init(apiKey: String, apiBase: URL = URL(string: "https://api.imgbb.com/1")!, transport: HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.apiBase = apiBase
        self.transport = transport
    }

    struct Envelope: Decodable {
        struct Image: Decodable {
            let id: String
            let url: URL
            let url_viewer: URL?
            let delete_url: URL?
        }
        let data: Image
        let success: Bool
    }

    struct ErrorEnvelope: Decodable {
        struct Detail: Decodable {
            let message: String
            let code: Int?
        }
        let error: Detail
    }

    public func upload(_ payload: UploadPayload, progress: @escaping @Sendable (Double) -> Void) async throws -> UploadResult {
        guard payload.data.count <= Self.maxUploadBytes else {
            throw AppError.cloudUploadFailed(provider: type.displayName, reason: "Image is larger than 32 MB.")
        }

        var components = URLComponents(url: apiBase.appendingPathComponent("upload"), resolvingAgainstBaseURL: false)!
        var query = [URLQueryItem(name: "key", value: apiKey)]
        let expirySeconds = payload.expiry.seconds.map { min($0, Self.maxExpirySeconds) }
        if let expirySeconds {
            query.append(URLQueryItem(name: "expiration", value: String(expirySeconds)))
        }
        components.queryItems = query

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data(capacity: payload.data.count + 512)
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"image\"; filename=\"screenshot.\(payload.fileExtension)\"\r\n".utf8))
        body.append(Data("Content-Type: \(payload.contentType)\r\n\r\n".utf8))
        body.append(payload.data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        let (data, response) = try await transport.send(request, body: body, progress: progress)
        guard response.isSuccess else { throw imgbbError(response, data) }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data), envelope.success else {
            throw imgbbError(response, data)
        }
        return UploadResult(
            remoteKey: envelope.data.id,
            shareURL: envelope.data.url,
            expiresAt: expirySeconds.map { Date().addingTimeInterval(TimeInterval($0)) },
            deleteToken: envelope.data.delete_url?.absoluteString
        )
    }

    /// ImgBB has no delete endpoint; removal happens on the `delete_url` page in the browser
    public func delete(remoteKey: String, deleteToken: String?) async throws {
        throw AppError.cloudUploadFailed(provider: type.displayName, reason: "ImgBB images can only be deleted from their delete page.")
    }

    private func imgbbError(_ response: HTTPURLResponse, _ data: Data) -> AppError {
        if let detail = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error {
            // 103: ImgBB has banned the account that owns the key
            if detail.code == 103 {
                return .cloudUploadFailed(provider: type.displayName, reason: "ImgBB has blocked this API key's account. Sign in at imgbb.com with a different account and create a new key.")
            }
            let message = detail.message
            let hint = response.statusCode == 400 && message.localizedCaseInsensitiveContains("key") ? " Check the API key in Settings › Storage & Cloud." : ""
            return .cloudUploadFailed(provider: type.displayName, reason: message + hint)
        }
        return providerError(type, response, data)
    }
}
