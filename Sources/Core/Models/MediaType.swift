import Foundation

/// Supported media asset types
public enum MediaType: String, Codable, Sendable, CaseIterable {
    case image = "image"
    case video = "video"
    case gif = "gif"

    public var fileExtension: String {
        switch self {
        case .image: return "png"
        case .video: return "mp4"
        case .gif: return "gif"
        }
    }

    public var utiType: String {
        switch self {
        case .image: return "public.png"
        case .video: return "public.mpeg-4"
        case .gif: return "com.compuserve.gif"
        }
    }

    public var systemIconName: String {
        switch self {
        case .image: return "photo"
        case .video: return "video.fill"
        case .gif: return "play.square.stack"
        }
    }
}
