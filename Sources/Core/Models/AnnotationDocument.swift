import Foundation

/// Normalized point in the unit coordinate space [0.0 ... 1.0]
public struct NormalizedPoint: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = min(max(x, 0.0), 1.0)
        self.y = min(max(y, 0.0), 1.0)
    }
}

/// Normalized rectangle in the unit coordinate space [0.0 ... 1.0]
public struct NormalizedRect: Codable, Sendable, Equatable {
    public var origin: NormalizedPoint
    public var width: Double
    public var height: Double

    public init(origin: NormalizedPoint, width: Double, height: Double) {
        self.origin = origin
        self.width = min(max(width, 0.0), 1.0 - origin.x)
        self.height = min(max(height, 0.0), 1.0 - origin.y)
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(origin: NormalizedPoint(x: x, y: y), width: width, height: height)
    }
}

/// Color representation compatible with Codable and multi-platform rendering
public struct AnnotationColor: Codable, Sendable, Equatable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let red = AnnotationColor(red: 0.95, green: 0.25, blue: 0.25)
    public static let yellow = AnnotationColor(red: 1.0, green: 0.85, blue: 0.15)
    public static let green = AnnotationColor(red: 0.20, green: 0.80, blue: 0.35)
    public static let blue = AnnotationColor(red: 0.20, green: 0.50, blue: 0.95)
    public static let white = AnnotationColor(red: 1.0, green: 1.0, blue: 1.0)
    public static let black = AnnotationColor(red: 0.0, green: 0.0, blue: 0.0)
    public static let highlightYellow = AnnotationColor(red: 1.0, green: 0.90, blue: 0.20, alpha: 0.40)
}

/// Type of annotation item
public enum AnnotationType: String, Codable, Sendable, CaseIterable {
    case arrow = "arrow"
    case rectangle = "rectangle"
    case ellipse = "ellipse"
    case text = "text"
    case highlight = "highlight"
    case freehand = "freehand"
    case blur = "blur"
    case pixelation = "pixelation"
}

/// An individual annotation layer/element
public struct AnnotationItem: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var type: AnnotationType
    public var bounds: NormalizedRect
    public var strokeColor: AnnotationColor
    public var fillColor: AnnotationColor?
    public var strokeWidth: Double
    
    // Type-specific attributes
    public var textContent: String?
    public var fontSize: Double?
    public var points: [NormalizedPoint]?  // For freehand drawing or arrow path
    public var blurRadius: Double?         // For blur / pixelate intensity

    public init(
        id: UUID = UUID(),
        type: AnnotationType,
        bounds: NormalizedRect,
        strokeColor: AnnotationColor = .red,
        fillColor: AnnotationColor? = nil,
        strokeWidth: Double = 3.0,
        textContent: String? = nil,
        fontSize: Double? = 16.0,
        points: [NormalizedPoint]? = nil,
        blurRadius: Double? = 15.0
    ) {
        self.id = id
        self.type = type
        self.bounds = bounds
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.strokeWidth = strokeWidth
        self.textContent = textContent
        self.fontSize = fontSize
        self.points = points
        self.blurRadius = blurRadius
    }
}

/// Persistent annotation document holding base metadata and all vector layers
public struct AnnotationDocument: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var assetId: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    public var items: [AnnotationItem]
    
    // Background styling presets
    public var backgroundColor: AnnotationColor?
    public var padding: Double
    public var cornerRadius: Double
    public var shadowRadius: Double

    public init(
        id: UUID = UUID(),
        assetId: UUID,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        items: [AnnotationItem] = [],
        backgroundColor: AnnotationColor? = nil,
        padding: Double = 0.0,
        cornerRadius: Double = 0.0,
        shadowRadius: Double = 0.0
    ) {
        self.id = id
        self.assetId = assetId
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.items = items
        self.backgroundColor = backgroundColor
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
    }
}
