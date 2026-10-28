import Foundation

/// Anonymous Imgur upload (Flameshot's approach). Needs a registered application Client-ID.
/// Images are public on Imgur and never expire; the delete hash removes them.
public struct ImgurProvider: CloudStorageProvider {
    public let type = CloudProviderType.imgur
    public let capabilities = ProviderCapabilities.imgurDefault

    private let clientID: String
    private let apiBase: URL
    private let transport: HTTPTransport

    public init(clientID: String, apiBase: URL = URL(string: "https://api.imgur.com/3")!, transport: HTTPTransport = URLSessionTransport()) {
        self.clientID = clientID
        self.apiBase = apiBase
        self.transport = transport
    }

    struct Envelope: Decodable {
        struct Image: Decodable {
            let id: String
            let link: URL
            let deletehash: String?
        }
        let data: Image
        let success: Bool
    }

    public func upload(_ payload: UploadPayload, progress: @escaping @Sendable (Double) -> Void) async throws -> UploadResult {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: apiBase.appendingPathComponent("image"))
        request.httpMethod = "POST"
        request.setValue("Client-ID \(clientID)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"image\"; filename=\"screenshot.\(payload.fileExtension)\"\r\n".utf8))
        body.append(Data("Content-Type: \(payload.contentType)\r\n\r\n".utf8))
        body.append(payload.data)
        body.append(Data("\r\n--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"type\"\r\n\r\nfile\r\n".utf8))
        body.append(Data("--\(boundary)--\r\n".utf8))

        let (data, response) = try await transport.send(request, body: body, progress: progress)
        guard response.isSuccess else { throw providerError(type, response, data) }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.success else { throw providerError(type, response, data) }
        return UploadResult(remoteKey: envelope.data.id, shareURL: envelope.data.link, expiresAt: nil, deleteToken: envelope.data.deletehash)
    }

    public func delete(remoteKey: String, deleteToken: String?) async throws {
        guard let deleteToken else { throw AppError.credentialsExpired }
        var request = URLRequest(url: apiBase.appendingPathComponent("image").appendingPathComponent(deleteToken))
        request.httpMethod = "DELETE"
        request.setValue("Client-ID \(clientID)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.send(request, body: nil, progress: nil)
        guard response.isSuccess || response.statusCode == 404 else { throw providerError(type, response, data) }
    }
}
