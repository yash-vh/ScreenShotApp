import Foundation
import Combine

/// Shared observable tool & style state for one editor window.
/// The SwiftUI toolbar binds to it directly; the AppKit canvas observes and writes to it.
@MainActor
public final class EditorState: ObservableObject {
    @Published public var tool: EditorTool
    @Published public var color: AnnotationColor = .red
    @Published public var strokeWidth: Double = 4.0
    @Published public var fontSize: Double = 22.0
    @Published public var blurRadius: Double = 20.0

    /// Whether an annotation is currently selected on the canvas (drives contextual toolbar actions)
    @Published public var hasSelection = false
    /// Whether on-device text recognition results are displayed over the canvas
    @Published public var isShowingRecognition = false
    @Published public var isRecognizing = false

    public init(tool: EditorTool = .arrow) {
        self.tool = tool
    }
}
