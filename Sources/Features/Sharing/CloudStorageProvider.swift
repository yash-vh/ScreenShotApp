import Foundation
import Security

/// How long a share link stays alive
public enum UploadExpiry: String, Codable, Sendable, CaseIterable, Identifiable {
    case oneDay = "1d"
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case never = "never"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .oneDay: return "1 day"
        case .sevenDays: return "7 days"
        case .thirtyDays: return "30 days"
        case .never: return "Keep"
        }
    }

    public var seconds: Int? {
        switch self {
        case .oneDay: return 86_400
        case .sevenDays: return 7 * 86_400
        case .thirtyDays: return 30 * 86_400
        case .never: return nil
        }
    }
}

/// Bytes to upload, already stripped of metadata
public struct UploadPayload: Sendable {
    public var data: Data
    public var contentType: String
    public var fileExtension: String
    public var expiry: UploadExpiry

    public init(data: Data, contentType: String = "image/png", fileExtension: String = "png", expiry: UploadExpiry) {
        self.data = data
        self.contentType = contentType
        self.fileExtension = fileExtension
        self.expiry = expiry
    }
}

public struct UploadResult: Sendable, Equatable {
    /// Provider-side identifier needed to delete the upload (share ID, object key, …)
    public var remoteKey: String
    public var shareURL: URL
    public var expiresAt: Date?
    /// Secret proving ownership; stored in the Keychain, never in the history database
    public var deleteToken: String?

    public init(remoteKey: String, shareURL: URL, expiresAt: Date?, deleteToken: String?) {
        self.remoteKey = remoteKey
        self.shareURL = shareURL
        self.expiresAt = expiresAt
        self.deleteToken = deleteToken
    }
}

/// A destination for share uploads
public protocol CloudStorageProvider: Sendable {
    var type: CloudProviderType { get }
    var capabilities: ProviderCapabilities { get }
    func upload(_ payload: UploadPayload, progress: @escaping @Sendable (Double) -> Void) async throws -> UploadResult
    func delete(remoteKey: String, deleteToken: String?) async throws
}

// MARK: - HTTP Transport

/// Minimal HTTP abstraction so providers can be tested without the network
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest, body: Data?, progress: (@Sendable (Double) -> Void)?) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest, body: Data?, progress: (@Sendable (Double) -> Void)?) async throws -> (Data, HTTPURLResponse) {
        let delegate = progress.map(UploadProgressDelegate.init)
        let (data, response): (Data, URLResponse)
        if let body {
            (data, response) = try await session.upload(for: request, from: body, delegate: delegate)
        } else {
            (data, response) = try await session.data(for: request, delegate: delegate)
        }
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(_ onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}

// MARK: - Shared Helpers

enum ShareID {
    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

    /// Unguessable base62 identifier (16 chars ≈ 95 bits) — never sequential
    static func random(length: Int = 16) -> String {
        var bytes = [UInt8](repeating: 0, count: length * 2)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        var result = ""
        var index = 0
        while result.count < length {
            if index == bytes.count {
                _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
                index = 0
            }
            let byte = bytes[index]
            index += 1
            // Reject the top of the range so every character is equally likely
            if byte < 248 { result.append(alphabet[Int(byte) % 62]) }
        }
        return result
    }
}

extension HTTPURLResponse {
    var isSuccess: Bool { (200..<300).contains(statusCode) }
}

func providerError(_ provider: CloudProviderType, _ response: HTTPURLResponse, _ data: Data) -> AppError {
    let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
    return .cloudUploadFailed(provider: provider.displayName, reason: "HTTP \(response.statusCode) \(body)")
}
