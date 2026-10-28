import CryptoKit
import Foundation

/// AWS Signature Version 4 for S3 and S3-compatible services (R2, B2, MinIO, …)
public struct SigV4Signer: Sendable {
    public let accessKeyID: String
    public let secretAccessKey: String
    public let region: String
    public let service: String

    public init(accessKeyID: String, secretAccessKey: String, region: String, service: String = "s3") {
        self.accessKeyID = accessKeyID
        self.secretAccessKey = secretAccessKey
        self.region = region
        self.service = service
    }

    public static let emptyPayloadHash = sha256Hex(Data())

    /// Adds `Authorization`, `x-amz-date` and `x-amz-content-sha256` headers
    public func sign(_ request: inout URLRequest, payloadHash: String, date: Date = Date()) {
        guard let url = request.url else { return }
        let (amzDate, day) = Self.timestamps(date)
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")

        var headers: [String: String] = ["host": Self.hostHeader(url)]
        for (key, value) in request.allHTTPHeaderFields ?? [:] {
            let lower = key.lowercased()
            if lower == "host" || lower == "content-type" || lower == "range" || lower.hasPrefix("x-amz-") {
                headers[lower] = value.trimmingCharacters(in: .whitespaces)
            }
        }
        let signedHeaders = headers.keys.sorted().joined(separator: ";")
        let canonicalHeaders = headers.keys.sorted().map { "\($0):\(headers[$0]!)\n" }.joined()
        let canonicalRequest = [
            request.httpMethod ?? "GET",
            Self.canonicalPath(url),
            Self.canonicalQuery(url),
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        let scope = "\(day)/\(region)/\(service)/aws4_request"
        let signature = signature(canonicalRequest: canonicalRequest, amzDate: amzDate, day: day)
        request.setValue(
            "AWS4-HMAC-SHA256 Credential=\(accessKeyID)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)",
            forHTTPHeaderField: "Authorization"
        )
    }

    /// Query-string presigned URL (e.g. a time-limited GET link to a private object). `expires` is capped at 7 days by S3.
    public func presignedURL(_ url: URL, method: String = "GET", expires: Int, date: Date = Date()) -> URL? {
        let (amzDate, day) = Self.timestamps(date)
        let scope = "\(day)/\(region)/\(service)/aws4_request"
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var items = components.percentEncodedQueryItems ?? []
        items += [
            URLQueryItem(name: "X-Amz-Algorithm", value: "AWS4-HMAC-SHA256"),
            URLQueryItem(name: "X-Amz-Credential", value: Self.encode("\(accessKeyID)/\(scope)")),
            URLQueryItem(name: "X-Amz-Date", value: amzDate),
            URLQueryItem(name: "X-Amz-Expires", value: String(min(max(expires, 1), 604_800))),
            URLQueryItem(name: "X-Amz-SignedHeaders", value: "host")
        ]
        components.percentEncodedQueryItems = items
        guard let unsigned = components.url else { return nil }

        let canonicalRequest = [
            method,
            Self.canonicalPath(unsigned),
            Self.canonicalQuery(unsigned),
            "host:\(Self.hostHeader(unsigned))\n",
            "host",
            "UNSIGNED-PAYLOAD"
        ].joined(separator: "\n")
        let signature = signature(canonicalRequest: canonicalRequest, amzDate: amzDate, day: day)
        components.percentEncodedQueryItems = items + [URLQueryItem(name: "X-Amz-Signature", value: signature)]
        return components.url
    }

    private func signature(canonicalRequest: String, amzDate: String, day: String) -> String {
        let scope = "\(day)/\(region)/\(service)/aws4_request"
        let stringToSign = ["AWS4-HMAC-SHA256", amzDate, scope, Self.sha256Hex(Data(canonicalRequest.utf8))].joined(separator: "\n")
        var key = SymmetricKey(data: Data("AWS4\(secretAccessKey)".utf8))
        for part in [day, region, service, "aws4_request"] {
            key = SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(for: Data(part.utf8), using: key)))
        }
        let mac = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Canonicalization

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func timestamps(_ date: Date) -> (amzDate: String, day: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = formatter.string(from: date)
        return (amzDate, String(amzDate.prefix(8)))
    }

    static func hostHeader(_ url: URL) -> String {
        let host = url.host ?? ""
        guard let port = url.port, !(url.scheme == "https" && port == 443), !(url.scheme == "http" && port == 80) else { return host }
        return "\(host):\(port)"
    }

    /// RFC 3986 encoding of everything except unreserved characters
    static func encode(_ string: String, keepSlash: Bool = false) -> String {
        var allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        if keepSlash { allowed.insert("/") }
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    static func canonicalPath(_ url: URL) -> String {
        let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? "/"
        let decoded = raw.removingPercentEncoding ?? raw
        let path = encode(decoded, keepSlash: true)
        return path.isEmpty ? "/" : path
    }

    static func canonicalQuery(_ url: URL) -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQueryItems ?? []
        var pairs: [(name: String, value: String)] = []
        for item in items {
            let rawValue = item.value ?? ""
            let name = item.name.removingPercentEncoding ?? item.name
            let value = rawValue.removingPercentEncoding ?? rawValue
            pairs.append((encode(name), encode(value)))
        }
        pairs.sort { lhs, rhs in lhs.name == rhs.name ? lhs.value < rhs.value : lhs.name < rhs.name }
        return pairs.map { pair in pair.name + "=" + pair.value }.joined(separator: "&")
    }
}

/// Uploads to the user's own S3 / S3-compatible bucket using path-style URLs (`endpoint/bucket/key`).
/// Share links are either public (when a public base URL is configured) or presigned GET URLs (max 7 days).
public struct S3Provider: CloudStorageProvider {
    public let type = CloudProviderType.s3Compatible
    public let capabilities = ProviderCapabilities.s3Default

    private let endpoint: URL
    private let bucket: String
    private let publicBaseURL: URL?
    private let signer: SigV4Signer
    private let transport: HTTPTransport

    public init(endpoint: URL, bucket: String, region: String, accessKeyID: String, secretAccessKey: String, publicBaseURL: URL? = nil, transport: HTTPTransport = URLSessionTransport()) {
        self.endpoint = endpoint
        self.bucket = bucket
        self.publicBaseURL = publicBaseURL
        self.signer = SigV4Signer(accessKeyID: accessKeyID, secretAccessKey: secretAccessKey, region: region)
        self.transport = transport
    }

    func objectURL(for key: String) -> URL {
        endpoint.appendingPathComponent(bucket).appendingPathComponent(key)
    }

    public func upload(_ payload: UploadPayload, progress: @escaping @Sendable (Double) -> Void) async throws -> UploadResult {
        let key = "screenshots/\(ShareID.random()).\(payload.fileExtension)"
        var request = URLRequest(url: objectURL(for: key))
        request.httpMethod = "PUT"
        request.setValue(payload.contentType, forHTTPHeaderField: "Content-Type")
        signer.sign(&request, payloadHash: SigV4Signer.sha256Hex(payload.data))

        let (data, response) = try await transport.send(request, body: payload.data, progress: progress)
        guard response.isSuccess else { throw providerError(type, response, data) }

        if let publicBaseURL {
            return UploadResult(remoteKey: key, shareURL: publicBaseURL.appendingPathComponent(key), expiresAt: nil, deleteToken: nil)
        }
        // Private bucket: a presigned link can live at most 7 days
        let lifetime = min(payload.expiry.seconds ?? 604_800, 604_800)
        guard let link = signer.presignedURL(objectURL(for: key), expires: lifetime) else {
            throw AppError.cloudUploadFailed(provider: type.displayName, reason: "Could not sign the share link.")
        }
        return UploadResult(remoteKey: key, shareURL: link, expiresAt: Date().addingTimeInterval(TimeInterval(lifetime)), deleteToken: nil)
    }

    public func delete(remoteKey: String, deleteToken: String?) async throws {
        var request = URLRequest(url: objectURL(for: remoteKey))
        request.httpMethod = "DELETE"
        signer.sign(&request, payloadHash: SigV4Signer.emptyPayloadHash)
        let (data, response) = try await transport.send(request, body: nil, progress: nil)
        guard response.isSuccess || response.statusCode == 404 else { throw providerError(type, response, data) }
    }
}
