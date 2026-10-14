import SwiftUI

/// Toolbar for selecting active annotation tools, colors, stroke widths, text content, blur intensity, and actions.
public struct EditorToolbarView: View {
    @ObservedObject var undoRedoManager: UndoRedoManager
    @Binding var selectedTool: EditorTool
    @Binding var selectedColor: AnnotationColor
    @Binding var strokeWidth: Double
    @Binding var textContent: String
    @Binding var fontSize: Double
    @Binding var blurRadius: Double
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

    private let highlightPalette: [AnnotationColor] = [
        AnnotationColor(red: 1.0, green: 0.95, blue: 0.10),  // Neon Yellow
        AnnotationColor(red: 0.20, green: 0.95, blue: 0.35),  // Neon Green
        AnnotationColor(red: 0.20, green: 0.80, blue: 1.0),   // Sky Cyan
        AnnotationColor(red: 1.0, green: 0.55, blue: 0.15),   // Vivid Orange
        AnnotationColor(red: 1.0, green: 0.25, blue: 0.65)    // Electric Pink
    ]

    public init(
        undoRedoManager: UndoRedoManager,
        selectedTool: Binding<EditorTool>,
        selectedColor: Binding<AnnotationColor>,
        strokeWidth: Binding<Double>,
        textContent: Binding<String>,
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
        self._textContent = textContent
        self._fontSize = fontSize
        self._blurRadius = blurRadius
        self.onExport = onExport
        self.onCopyToClipboard = onCopyToClipboard
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 8) {
            // MARK: - Row 1: Tool Picker, Undo/Redo, and Global Actions
            HStack(spacing: 10) {
                // Tool Selector
                HStack(spacing: 2) {
                    ForEach(EditorTool.allCases) { tool in
                        Button {
                            selectedTool = tool
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: tool.systemIcon)
                                    .font(.system(size: 13, weight: .semibold))
                                if selectedTool == tool {
                                    Text(tool.rawValue)
                                        .font(.system(size: 11, weight: .semibold))
                                }
                            }
                            .padding(.horizontal, selectedTool == tool ? 8 : 6)
                            .frame(height: 28)
                            .background(selectedTool == tool ? Color.accentColor : Color.clear)
                            .foregroundColor(selectedTool == tool ? .white : .primary)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help(tool.rawValue)
                    }
                }
                .padding(3)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))

                Divider().frame(height: 22)

                // Undo / Redo
                HStack(spacing: 4) {
                    Button {
                        undoRedoManager.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!undoRedoManager.canUndo)
                    .help("Undo (⌘Z / ^Z)")

                    Button {
                        undoRedoManager.redo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!undoRedoManager.canRedo)
                    .help("Redo (⇧⌘Z / ⌘Y / ^Y)")
                }

                Spacer()

                // Global Export Actions
                HStack(spacing: 8) {
                    Button {
                        onCopyToClipboard()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text("Copy")
                        }
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onExport()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Save")
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Done") {
                        onClose()
                    }
                    .buttonStyle(.bordered)
                }
            }

            // MARK: - Row 2: Dedicated Contextual Options Bar
            HStack(spacing: 12) {
                switch selectedTool {
                case .text:
                    HStack(spacing: 8) {
                        Label("Text:", systemImage: "character.textbox")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        TextField("Enter text...", text: $textContent)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)

                        Divider().frame(height: 18)

                        Label("Size:", systemImage: "textformat.size")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        Slider(value: $fontSize, in: 12...72, step: 2)
                            .frame(width: 75)

                        Text("\(Int(fontSize)) pt")
                            .font(.caption2.monospacedDigit())
                            .frame(width: 32, alignment: .leading)

                        Divider().frame(height: 18)

                        Label("Color:", systemImage: "paintpalette")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        colorDots(palette: colorPalette)
                    }

                case .blur, .pixelate:
                    HStack(spacing: 10) {
                        Label("Redaction:", systemImage: selectedTool == .blur ? "drop.fill" : "checkerboard.rectangle")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        Picker("", selection: $selectedTool) {
                            Text("Blur").tag(EditorTool.blur)
                            Text("Pixelate").tag(EditorTool.pixelate)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 130)

                        Divider().frame(height: 18)

                        Label("Intensity:", systemImage: "slider.horizontal.3")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        Slider(value: $blurRadius, in: 5...60, step: 1)
                            .frame(width: 85)

                        Text("\(Int(blurRadius)) px")
                            .font(.caption2.monospacedDigit())
                            .frame(width: 34, alignment: .leading)

                        Divider().frame(height: 18)

                        Text("Drag a box over canvas to obscure sensitive areas")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                case .highlight:
                    HStack(spacing: 10) {
                        Label("Color:", systemImage: "highlighter")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        colorDots(palette: highlightPalette)

                        Divider().frame(height: 18)

                        Label("Thickness:", systemImage: "line.diagonal")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        Slider(value: $strokeWidth, in: 8...60, step: 2)
                            .frame(width: 80)

                        Text("\(Int(strokeWidth)) pt")
                            .font(.caption2.monospacedDigit())
                            .frame(width: 34, alignment: .leading)
                    }

                case .arrow, .rectangle, .ellipse, .freehand:
                    HStack(spacing: 10) {
                        Label("Stroke:", systemImage: "line.diagonal")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        Slider(value: $strokeWidth, in: 1...30, step: 1)
                            .frame(width: 80)

                        Text("\(Int(strokeWidth)) pt")
                            .font(.caption2.monospacedDigit())
                            .frame(width: 32, alignment: .leading)

                        Divider().frame(height: 18)

                        Label("Color:", systemImage: "paintpalette")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        colorDots(palette: colorPalette)
                    }

                case .select:
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.accentColor)
                        Text("Click any item to select & drag anywhere. Customize its text, blur, or color in real-time. Press Backspace to delete.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: NSColorPanel.colorDidChangeNotification)) { _ in
            let panel = NSColorPanel.shared
            if let nsColor = panel.color.usingColorSpace(.sRGB) {
                selectedColor = AnnotationColor(
                    red: Double(nsColor.redComponent),
                    green: Double(nsColor.greenComponent),
                    blue: Double(nsColor.blueComponent),
                    alpha: Double(nsColor.alphaComponent)
                )
            }
        }
    }

    @ViewBuilder
    private func colorDots(palette: [AnnotationColor]) -> some View {
        HStack(spacing: 6) {
            ForEach(palette, id: \.self) { col in
                Button {
                    selectedColor = col
                } label: {
                    Circle()
                        .fill(Color(red: col.red, green: col.green, blue: col.blue))
                        .frame(width: 17, height: 17)
                        .overlay(
                            Circle()
                                .stroke(selectedColor == col ? Color.primary : Color.clear, lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 1)
                }
                .buttonStyle(.plain)
            }

            // Native macOS ColorPanel button matching circular palette style
            Button {
                let panel = NSColorPanel.shared
                panel.color = NSColor(
                    red: CGFloat(selectedColor.red),
                    green: CGFloat(selectedColor.green),
                    blue: CGFloat(selectedColor.blue),
                    alpha: CGFloat(selectedColor.alpha)
                )
                panel.orderFront(nil)
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            AngularGradient(
                                gradient: Gradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red]),
                                center: .center
                            )
                        )
                        .frame(width: 17, height: 17)
                        .overlay(
                            Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1)
                        )
                }
            }
            .buttonStyle(.plain)
            .help("Pick custom color from palette")
        }
    }
}
