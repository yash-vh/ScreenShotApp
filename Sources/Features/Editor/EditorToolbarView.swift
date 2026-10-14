import SwiftUI

/// Toolbar for selecting active annotation tools, colors, stroke widths, and actions.
public struct EditorToolbarView: View {
    @ObservedObject var undoRedoManager: UndoRedoManager
    @Binding var selectedTool: EditorTool
    @Binding var selectedColor: AnnotationColor
    @Binding var strokeWidth: Double
    var onExport: () -> Void
    var onCopyToClipboard: () -> Void
    var onClose: () -> Void

    private let colorPalette: [AnnotationColor] = [
        .red,
        .blue,
        .green,
        .yellow,
        AnnotationColor(red: 0.60, green: 0.20, blue: 0.80), // Purple
        AnnotationColor(red: 1.0, green: 0.50, blue: 0.10),  // Orange
        .black,
        .white
    ]

    public init(
        undoRedoManager: UndoRedoManager,
        selectedTool: Binding<EditorTool>,
        selectedColor: Binding<AnnotationColor>,
        strokeWidth: Binding<Double>,
        onExport: @escaping () -> Void,
        onCopyToClipboard: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.undoRedoManager = undoRedoManager
        self._selectedTool = selectedTool
        self._selectedColor = selectedColor
        self._strokeWidth = strokeWidth
        self.onExport = onExport
        self.onCopyToClipboard = onCopyToClipboard
        self.onClose = onClose
    }

    public var body: some View {
        HStack(spacing: 12) {
            // 1. Tool Selector
            HStack(spacing: 4) {
                ForEach(EditorTool.allCases) { tool in
                    Button {
                        selectedTool = tool
                    } label: {
                        Image(systemName: tool.systemIcon)
                            .frame(width: 28, height: 28)
                            .background(selectedTool == tool ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help(tool.rawValue)
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))

            Divider().frame(height: 24)

            // 2. Color Palette
            HStack(spacing: 6) {
                ForEach(0..<colorPalette.count, id: \.self) { idx in
                    let col = colorPalette[idx]
                    Circle()
                        .fill(Color(red: col.red, green: col.green, blue: col.blue))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle()
                                .stroke(Color.primary, lineWidth: selectedColor == col ? 2 : 0)
                        )
                        .onTapGesture {
                            selectedColor = col
                        }
                }
            }

            Divider().frame(height: 24)

            // 3. Stroke Width
            HStack(spacing: 8) {
                StrokeButton(width: 2.0, currentWidth: $strokeWidth, label: "Thin")
                StrokeButton(width: 4.0, currentWidth: $strokeWidth, label: "Medium")
                StrokeButton(width: 8.0, currentWidth: $strokeWidth, label: "Thick")
            }

            Divider().frame(height: 24)

            // 4. Undo / Redo
            HStack(spacing: 4) {
                Button {
                    undoRedoManager.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!undoRedoManager.canUndo)
                .help("Undo (⌘Z)")

                Button {
                    undoRedoManager.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!undoRedoManager.canRedo)
                .help("Redo (⇧⌘Z)")
            }

            Spacer()

            // 5. Actions
            HStack(spacing: 8) {
                Button("Copy") {
                    onCopyToClipboard()
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    onExport()
                }
                .buttonStyle(.borderedProminent)

                Button("Done") {
                    onClose()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct StrokeButton: View {
    let width: Double
    @Binding var currentWidth: Double
    let label: String

    var body: some View {
        Button {
            currentWidth = width
        } label: {
            Circle()
                .fill(Color.primary)
                .frame(width: CGFloat(width + 2), height: CGFloat(width + 2))
                .frame(width: 24, height: 24)
                .background(currentWidth == width ? Color.accentColor.opacity(0.2) : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .help(label)
    }
}
