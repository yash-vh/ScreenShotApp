import SwiftUI

/// Modern, streamlined single-row glassmorphic toolbar for the Screenshot Editor.
public struct EditorToolbarView: View {
    @ObservedObject var undoRedoManager: UndoRedoManager
    @Binding var selectedTool: EditorTool
    @Binding var selectedColor: AnnotationColor
    @Binding var strokeWidth: Double
    @Binding var fontSize: Double
    @Binding var blurRadius: Double
    var onExport: () -> Void
    var onCopyToClipboard: () -> Void
    var onClose: () -> Void

    private let standardColors: [AnnotationColor] = [
        .red,
        AnnotationColor(red: 1.0, green: 0.85, blue: 0.10), // Neon Yellow
        AnnotationColor(red: 0.15, green: 0.80, blue: 0.35), // Green
        AnnotationColor(red: 0.20, green: 0.55, blue: 1.0),  // Vivid Blue
        AnnotationColor(red: 0.65, green: 0.25, blue: 0.90), // Purple
        .white,
        .black
    ]

    public init(
        undoRedoManager: UndoRedoManager,
        selectedTool: Binding<EditorTool>,
        selectedColor: Binding<AnnotationColor>,
        strokeWidth: Binding<Double>,
        fontSize: Binding<Double>,
        blurRadius: Binding<Double>,
        onExport: @escaping () -> Void,
        onCopyToClipboard: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.undoRedoManager = undoRedoManager
        self._selectedTool = selectedTool
        self._selectedColor = selectedColor
        self._strokeWidth = strokeWidth
        self._fontSize = fontSize
        self._blurRadius = blurRadius
        self.onExport = onExport
        self.onCopyToClipboard = onCopyToClipboard
        self.onClose = onClose
    }

    public var body: some View {
        HStack(spacing: 12) {
            // MARK: - 1. Tools Group
            HStack(spacing: 2) {
                toolButton(.select, shortcut: "V")
                toolButton(.arrow, shortcut: "A")
                toolButton(.rectangle, shortcut: "R")
                toolButton(.ellipse, shortcut: "O")
                toolButton(.freehand, shortcut: "P")
                toolButton(.highlight, shortcut: "H")
                toolButton(.text, shortcut: "T")
                toolButton(.blur, shortcut: "B")
                toolButton(.pixelate, shortcut: "X")
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.secondary.opacity(0.12)))

            Divider().frame(height: 20)

            // MARK: - 2. Contextual Properties (Color, Thickness, or Intensity)
            if selectedTool == .blur || selectedTool == .pixelate {
                // Redaction slider
                HStack(spacing: 6) {
                    Image(systemName: selectedTool == .blur ? "drop.fill" : "checkerboard.rectangle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Slider(value: $blurRadius, in: 8...60, step: 2)
                        .frame(width: 80)

                    Text("\(Int(blurRadius))px")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 32, alignment: .leading)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.08)))
            } else if selectedTool == .text {
                // Text size controls
                HStack(spacing: 6) {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Slider(value: $fontSize, in: 14...64, step: 2)
                        .frame(width: 75)

                    Text("\(Int(fontSize))pt")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 30, alignment: .leading)

                    Divider().frame(height: 16)

                    colorChips
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.08)))
            } else {
                // Shapes, arrow, pen, highlight: Color & Thickness
                HStack(spacing: 8) {
                    colorChips

                    Divider().frame(height: 16)

                    // Stroke thickness chips
                    HStack(spacing: 3) {
                        thicknessButton(width: 2.0, label: "Fine")
                        thicknessButton(width: 4.0, label: "Medium")
                        thicknessButton(width: 8.0, label: "Bold")
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.08)))
            }

            Divider().frame(height: 20)

            // MARK: - 3. Undo / Redo
            HStack(spacing: 2) {
                Button {
                    undoRedoManager.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!undoRedoManager.canUndo)
                .opacity(undoRedoManager.canUndo ? 1.0 : 0.35)
                .help("Undo (⌘Z)")

                Button {
                    undoRedoManager.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!undoRedoManager.canRedo)
                .opacity(undoRedoManager.canRedo ? 1.0 : 0.35)
                .help("Redo (⇧⌘Z)")
            }

            Spacer()

            // MARK: - 4. Direct Actions
            HStack(spacing: 8) {
                // Copy Button (Primary Blue)
                Button {
                    onCopyToClipboard()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 11))
                        Text("Copy")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(6)
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 3, y: 1)
                }
                .buttonStyle(.plain)
                .help("Copy to Clipboard (⌘C)")

                // Save Button
                Button {
                    onExport()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 11))
                        Text("Save")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Save to Disk (⌘S)")

                // Done Button
                Button {
                    onClose()
                } label: {
                    Text("Done")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .help("Close Editor (Esc)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func toolButton(_ tool: EditorTool, shortcut: String) -> some View {
        Button {
            selectedTool = tool
        } label: {
            Image(systemName: tool.systemIcon)
                .font(.system(size: 12, weight: selectedTool == tool ? .bold : .medium))
                .frame(width: 28, height: 26)
                .background(selectedTool == tool ? Color.accentColor : Color.clear)
                .foregroundColor(selectedTool == tool ? .white : .primary)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help("\(tool.rawValue) (\(shortcut))")
    }

    private var colorChips: some View {
        HStack(spacing: 5) {
            ForEach(0..<standardColors.count, id: \.self) { i in
                let color = standardColors[i]
                Circle()
                    .fill(Color(red: color.red, green: color.green, blue: color.blue))
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .stroke(Color.primary, lineWidth: selectedColor == color ? 2 : 0)
                            .padding(-2)
                    )
                    .contentShape(Circle())
                    .onTapGesture {
                        selectedColor = color
                    }
            }
        }
    }

    @ViewBuilder
    private func thicknessButton(width: Double, label: String) -> some View {
        Button {
            strokeWidth = width
        } label: {
            Circle()
                .fill(Color.primary)
                .frame(width: CGFloat(width + 1), height: CGFloat(width + 1))
                .frame(width: 20, height: 20)
                .background(strokeWidth == width ? Color.accentColor.opacity(0.2) : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .help(label)
    }
}
