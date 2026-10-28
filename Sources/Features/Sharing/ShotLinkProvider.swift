import Foundation

/// Client for the free Shot Link share service (Cloudflare Worker + R2, see `Services/share-worker`).
///
/// 1. `POST /v1/uploads` reserves an unguessable ID and returns a one-time upload URL and a delete token.
/// 2. `PUT uploadURL` sends the image bytes.
/// 3. `DELETE /v1/uploads/{id}` with `Authorization: Bearer <deleteToken>` removes it.
public struct ShotLinkProvider: CloudStorageProvider {
    public let type = CloudProviderType.managedCloud
    public let capabilities = ProviderCapabilities.managedDefault

    /// Server-side limit; checked locally to fail fast
    public static let maxUploadBytes = 10 * 1_048_576

    private let baseURL: URL
    private let installID: String
    private let transport: HTTPTransport

    public init(baseURL: URL, installID: String, transport: HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.installID = installID
        self.transport = transport
    }

    struct CreateRequest: Encodable {
        let size: Int
        let contentType: String
        let expiresIn: Int?
    }

    struct CreateResponse: Decodable {
        let id: String
        let url: URL
        let uploadURL: URL
        let deleteToken: String
        let expiresAt: Date?
    }

    public func upload(_ payload: UploadPayload, progress: @escaping @Sendable (Double) -> Void) async throws -> UploadResult {
        guard payload.data.count <= Self.maxUploadBytes else {
            throw AppError.cloudUploadFailed(provider: type.displayName, reason: "Image is larger than 10 MB.")
        }

        var create = URLRequest(url: baseURL.appendingPathComponent("v1/uploads"))
        create.httpMethod = "POST"
        create.setValue("application/json", forHTTPHeaderField: "Content-Type")
        create.setValue(installID, forHTTPHeaderField: "X-Install-ID")
        let body = try JSONEncoder().encode(CreateRequest(size: payload.data.count, contentType: payload.contentType, expiresIn: payload.expiry.seconds))
        let (createData, createResponse) = try await transport.send(create, body: body, progress: nil)
        guard createResponse.isSuccess else { throw providerError(type, createResponse, createData) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let reservation = try decoder.decode(CreateResponse.self, from: createData)

        var put = URLRequest(url: reservation.uploadURL)
        put.httpMethod = "PUT"
        put.setValue(payload.contentType, forHTTPHeaderField: "Content-Type")
        let (putData, putResponse) = try await transport.send(put, body: payload.data, progress: progress)
        guard putResponse.isSuccess else { throw providerError(type, putResponse, putData) }

        return UploadResult(remoteKey: reservation.id, shareURL: reservation.url, expiresAt: reservation.expiresAt, deleteToken: reservation.deleteToken)
    }

    public func delete(remoteKey: String, deleteToken: String?) async throws {
        guard let deleteToken else { throw AppError.credentialsExpired }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/uploads").appendingPathComponent(remoteKey))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(deleteToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.send(request, body: nil, progress: nil)
        // Already gone (expired or deleted elsewhere) counts as success
        guard response.isSuccess || response.statusCode == 404 else { throw providerError(type, response, data) }
    }
}
