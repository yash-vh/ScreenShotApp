import Foundation
import CoreGraphics

/// A curated presentation backdrop: one color renders as a solid fill, two or more as a diagonal gradient.
public struct BackgroundPreset: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let colors: [AnnotationColor]

    public init(id: String, name: String, colors: [AnnotationColor]) {
        self.id = id
        self.name = name
        self.colors = colors
    }

    public var isGradient: Bool { colors.count > 1 }

    public var cgColors: [CGColor] {
        colors.map { CGColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha) }
    }
}

/// Curated modern gradient and solid backdrop presets for styled exports.
public enum BackgroundPresets {
    public static let all: [BackgroundPreset] = [
        BackgroundPreset(id: "sunset", name: "Sunset", colors: [
            AnnotationColor(red: 1.00, green: 0.48, blue: 0.36),
            AnnotationColor(red: 0.93, green: 0.25, blue: 0.56)
        ]),
        BackgroundPreset(id: "ocean", name: "Ocean", colors: [
            AnnotationColor(red: 0.16, green: 0.62, blue: 0.98),
            AnnotationColor(red: 0.33, green: 0.24, blue: 0.85)
        ]),
        BackgroundPreset(id: "mint", name: "Mint", colors: [
            AnnotationColor(red: 0.26, green: 0.86, blue: 0.67),
            AnnotationColor(red: 0.10, green: 0.55, blue: 0.75)
        ]),
        BackgroundPreset(id: "peach", name: "Peach", colors: [
            AnnotationColor(red: 1.00, green: 0.83, blue: 0.62),
            AnnotationColor(red: 0.99, green: 0.55, blue: 0.50)
        ]),
        BackgroundPreset(id: "lavender", name: "Lavender", colors: [
            AnnotationColor(red: 0.80, green: 0.66, blue: 1.00),
            AnnotationColor(red: 0.52, green: 0.42, blue: 0.95)
        ]),
        BackgroundPreset(id: "midnight", name: "Midnight", colors: [
            AnnotationColor(red: 0.14, green: 0.15, blue: 0.24),
            AnnotationColor(red: 0.05, green: 0.06, blue: 0.10)
        ]),
        BackgroundPreset(id: "graphite", name: "Graphite", colors: [
            AnnotationColor(red: 0.20, green: 0.20, blue: 0.22)
        ]),
        BackgroundPreset(id: "snow", name: "Snow", colors: [
            AnnotationColor(red: 0.96, green: 0.96, blue: 0.97)
        ])
    ]

    public static func preset(id: String?) -> BackgroundPreset? {
        guard let id = id else { return nil }
        return all.first { $0.id == id }
    }
}
