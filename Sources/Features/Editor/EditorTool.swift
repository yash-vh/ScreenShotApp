import Foundation

/// Tool mode for interactive canvas drawing and annotation selection
public enum EditorTool: String, CaseIterable, Identifiable {
    case select = "Select"
    case arrow = "Arrow"
    case rectangle = "Rectangle"
    case ellipse = "Ellipse"
    case freehand = "Pen"
    case highlight = "Highlight"
    case text = "Text"
    case blur = "Blur Redact"
    case pixelate = "Pixelate"

    public var id: String { rawValue }

    public var systemIcon: String {
        switch self {
        case .select: return "arrow.up.left.and.arrow.down.right"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .freehand: return "pencil.line"
        case .highlight: return "highlighter"
        case .text: return "textformat"
        case .blur: return "drop.fill"
        case .pixelate: return "checkerboard.rectangle"
        }
    }
}
