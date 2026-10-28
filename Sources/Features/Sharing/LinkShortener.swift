import Foundation

/// Optional short-link service applied to share links after upload
public enum LinkShortener: String, Codable, Sendable, CaseIterable, Identifiable {
    case off
    case isgd = "is.gd"
    case tinyurl

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: return "Off (full link)"
        case .isgd: return "is.gd"
        case .tinyurl: return "TinyURL"
        }
    }
}

/// Turns a long share link into a short one using a free, key-less shortener API
public struct LinkShortenerService: Sendable {
    public let kind: LinkShortener
    private let transport: HTTPTransport

    public init(kind: LinkShortener, transport: HTTPTransport = URLSessionTransport()) {
        self.kind = kind
        self.transport = transport
    }

    func requestURL(for url: URL) -> URL? {
        // Encode everything but unreserved characters so S3 presigned query strings survive intact
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: unreserved) else { return nil }
        switch kind {
        case .off: return nil
        case .isgd: return URL(string: "https://is.gd/create.php?format=simple&url=\(encoded)")
        case .tinyurl: return URL(string: "https://tinyurl.com/api-create.php?url=\(encoded)")
        }
    }

    public func shorten(_ url: URL) async throws -> URL {
        guard let endpoint = requestURL(for: url) else { return url }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        let (data, response) = try await transport.send(request, body: nil, progress: nil)
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard response.isSuccess, let short = URL(string: text), short.scheme == "https", short.host != nil else {
            throw AppError.cloudUploadFailed(provider: kind.title, reason: text.isEmpty ? "HTTP \(response.statusCode)" : text)
        }
        return short
    }
}
