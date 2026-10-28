import SwiftUI

/// A trailing action button on the editor toolbar (Save, Upload, Open in Editor, …)
public struct EditorToolbarAction: Identifiable {
    public let id: String
    public let symbol: String
    public let help: String
    public let action: () -> Void

    public init(id: String, symbol: String, help: String, action: @escaping () -> Void) {
        self.id = id
        self.symbol = symbol
        self.help = help
        self.action = action
    }
}

/// Modern, streamlined single-row glassmorphic toolbar shared by the Screenshot Editor window
/// and the region-capture overlay, so both offer identical tools, styling and shortcuts.
public struct EditorToolbarView: View {
    /// Where the toolbar is hosted: docked across the editor window, or floating beside a capture selection
    public enum Placement {
        case docked
        case floating
    }

    @ObservedObject var undoRedoManager: UndoRedoManager
    @ObservedObject var state: EditorState
    var placement: Placement
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onDelete: () -> Void
    var onCopyToClipboard: () -> Void
    var secondaryActions: [EditorToolbarAction]
    var closeTitle: String
    var closeHelp: String
    var onClose: () -> Void

    @State private var isShowingStyle = false

    private let standardColors: [AnnotationColor] = [
        .red,
        AnnotationColor(red: 1.0, green: 0.85, blue: 0.10), // Neon Yellow
        AnnotationColor(red: 0.15, green: 0.80, blue: 0.35), // Green
        AnnotationColor(red: 0.20, green: 0.55, blue: 1.0),  // Vivid Blue
        AnnotationColor(red: 0.65, green: 0.25, blue: 0.90), // Purple
        .white,
        .black
    ]

    private static let toolOrder: [(EditorTool, String)] = [
        (.select, "V"), (.arrow, "A"), (.rectangle, "R"), (.ellipse, "O"), (.freehand, "P"),
        (.highlight, "H"), (.text, "T"), (.blur, "B"), (.pixelate, "X")
    ]

    public init(
        undoRedoManager: UndoRedoManager,
        state: EditorState,
        placement: Placement = .docked,
        onUndo: @escaping () -> Void,
        onRedo: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onCopyToClipboard: @escaping () -> Void,
        secondaryActions: [EditorToolbarAction],
        closeTitle: String = "Done",
        closeHelp: String = "Close Editor (Esc)",
        onClose: @escaping () -> Void
    ) {
        self.undoRedoManager = undoRedoManager
        self.state = state
        self.placement = placement
        self.onUndo = onUndo
        self.onRedo = onRedo
        self.onDelete = onDelete
        self.onCopyToClipboard = onCopyToClipboard
        self.secondaryActions = secondaryActions
        self.closeTitle = closeTitle
        self.closeHelp = closeHelp
        self.onClose = onClose
    }

    public var body: some View {
        HStack(spacing: 10) {
            // MARK: - 1. Tools Group
            HStack(spacing: 2) {
                ForEach(Self.toolOrder, id: \.0) { tool, shortcut in
                    toolButton(tool, shortcut: shortcut)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.secondary.opacity(0.12)))

            // MARK: - 2. Contextual Properties (Color, Thickness, or Intensity)
            contextualProperties
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.08)))

            Divider().frame(height: 20)

            // MARK: - 3. History & Layer Actions
            HStack(spacing: 2) {
                iconButton("arrow.uturn.backward", help: "Undo (⌘Z)", enabled: undoRedoManager.canUndo, action: onUndo)
                iconButton("arrow.uturn.forward", help: "Redo (⇧⌘Z)", enabled: undoRedoManager.canRedo, action: onRedo)
                iconButton("trash", help: "Delete Selection (⌫)", enabled: state.hasSelection, action: onDelete)
            }

            Divider().frame(height: 20)

            // MARK: - 4. Styling & Recognition
            HStack(spacing: 2) {
                Button {
                    isShowingStyle.toggle()
                } label: {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 26)
                        .background(undoRedoManager.document.hasStyling ? Color.accentColor.opacity(0.25) : Color.clear)
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Background, Padding & Shadow")
                .popover(isPresented: $isShowingStyle, arrowEdge: .bottom) {
                    StylePanel(undoRedoManager: undoRedoManager)
                }

                Button {
                    state.isShowingRecognition.toggle()
                } label: {
                    Group {
                        if state.isRecognizing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "text.viewfinder")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .frame(width: 28, height: 26)
                    .background(state.isShowingRecognition ? Color.accentColor : Color.clear)
                    .foregroundColor(state.isShowingRecognition ? .white : .primary)
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Recognize Text & QR Codes (⇧⌘T)")
            }

            if placement == .docked {
                Spacer(minLength: 8)
            } else {
                Divider().frame(height: 20)
            }

            // MARK: - 5. Direct Actions
            HStack(spacing: 8) {
                Button(action: onCopyToClipboard) {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.on.doc.fill").font(.system(size: 11))
                        Text("Copy").font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(
                        LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                    )
                    .foregroundColor(.white)
                    .cornerRadius(6)
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 3, y: 1)
                }
                .buttonStyle(.plain)
                .help("Copy to Clipboard (⌘C)")

                ForEach(secondaryActions) { item in
                    Button(action: item.action) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 28, height: 24)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(item.help)
                }

                Button(action: onClose) {
                    Text(closeTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(closeHelp)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .fixedSize(horizontal: placement == .floating, vertical: false)
        .background(toolbarBackground)
    }

    @ViewBuilder
    private var toolbarBackground: some View {
        switch placement {
        case .docked:
            Rectangle().fill(.ultraThinMaterial)
        case .floating:
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
        }
    }

    // MARK: - Contextual Properties

    @ViewBuilder
    private var contextualProperties: some View {
        if state.tool == .blur || state.tool == .pixelate {
            HStack(spacing: 6) {
                Image(systemName: state.tool == .blur ? "drop.fill" : "checkerboard.rectangle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Slider(value: $state.blurRadius, in: 8...60, step: 2)
                    .frame(width: 80)
                Text("\(Int(state.blurRadius))px")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 32, alignment: .leading)
            }
        } else if state.tool == .text {
            HStack(spacing: 6) {
                Image(systemName: "textformat.size")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Slider(value: $state.fontSize, in: 12...72, step: 2)
                    .frame(width: 70)
                Text("\(Int(state.fontSize))pt")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 30, alignment: .leading)
                Divider().frame(height: 16)
                colorChips
            }
        } else {
            HStack(spacing: 8) {
                colorChips
                if state.tool != .highlight {
                    Divider().frame(height: 16)
                    HStack(spacing: 3) {
                        thicknessButton(width: 2.0, label: "Fine")
                        thicknessButton(width: 4.0, label: "Medium")
                        thicknessButton(width: 8.0, label: "Bold")
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func toolButton(_ tool: EditorTool, shortcut: String) -> some View {
        Button {
            state.tool = tool
        } label: {
            Image(systemName: tool.systemIcon)
                .font(.system(size: 12, weight: state.tool == tool ? .bold : .medium))
                .frame(width: 28, height: 26)
                .background(state.tool == tool ? Color.accentColor : Color.clear)
                .foregroundColor(state.tool == tool ? .white : .primary)
                .cornerRadius(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(tool.rawValue) (\(shortcut))")
    }

    private func iconButton(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1.0 : 0.35)
        .help(help)
    }

    private var colorChips: some View {
        HStack(spacing: 5) {
            ForEach(standardColors, id: \.self) { color in
                Circle()
                    .fill(Color(red: color.red, green: color.green, blue: color.blue))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
                    .overlay(
                        Circle()
                            .stroke(Color.primary, lineWidth: state.color == color ? 2 : 0)
                            .padding(-2)
                    )
                    .contentShape(Circle())
                    .onTapGesture {
                        state.color = color
                    }
            }
        }
    }

    private func thicknessButton(width: Double, label: String) -> some View {
        Button {
            state.strokeWidth = width
        } label: {
            Circle()
                .fill(Color.primary)
                .frame(width: CGFloat(width + 1), height: CGFloat(width + 1))
                .frame(width: 20, height: 20)
                .background(state.strokeWidth == width ? Color.accentColor.opacity(0.25) : Color.clear)
                .cornerRadius(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

// MARK: - Style Panel (M4 Image Styling)

/// Popover controls for presentation backdrop, padding, corner radius and drop shadow.
struct StylePanel: View {
    @ObservedObject var undoRedoManager: UndoRedoManager

    private var document: AnnotationDocument { undoRedoManager.document }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Background").font(.system(size: 12, weight: .semibold))

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 8), count: 5), spacing: 8) {
                swatch(selected: document.backgroundPresetID == nil && document.backgroundColor == nil, help: "None") {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15))
                        Image(systemName: "nosign").font(.system(size: 12)).foregroundColor(.secondary)
                    }
                } action: {
                    update("background") { $0.backgroundPresetID = nil; $0.backgroundColor = nil }
                }

                ForEach(BackgroundPresets.all) { preset in
                    swatch(selected: document.backgroundPresetID == preset.id, help: preset.name) {
                        RoundedRectangle(cornerRadius: 6).fill(
                            LinearGradient(
                                colors: preset.colors.map { Color(red: $0.red, green: $0.green, blue: $0.blue) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    } action: {
                        update("background") { doc in
                            doc.backgroundPresetID = preset.id
                            doc.backgroundColor = nil
                            // A backdrop is invisible without padding: give it sensible defaults on first use
                            if doc.padding == 0 { doc.padding = 48 }
                            if doc.cornerRadius == 0 { doc.cornerRadius = 10 }
                            if doc.shadowRadius == 0 { doc.shadowRadius = 24 }
                        }
                    }
                }
            }

            Divider()

            slider("Padding", value: \.padding, range: 0...160, unit: "pt")
            slider("Corners", value: \.cornerRadius, range: 0...48, unit: "pt")
            slider("Shadow", value: \.shadowRadius, range: 0...80, unit: "pt")

            HStack {
                Spacer()
                Button("Reset Style") {
                    update("reset") { doc in
                        doc.backgroundPresetID = nil
                        doc.backgroundColor = nil
                        doc.padding = 0
                        doc.cornerRadius = 0
                        doc.shadowRadius = 0
                    }
                }
                .disabled(!document.hasStyling)
            }
        }
        .padding(14)
        .frame(width: 250)
    }

    private func update(_ key: String, _ mutate: (inout AnnotationDocument) -> Void) {
        undoRedoManager.updateDocument(coalescingKey: "style-\(key)", mutate)
    }

    private func swatch<Content: View>(selected: Bool, help: String, @ViewBuilder content: () -> Content, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            content()
                .frame(width: 30, height: 30)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.accentColor, lineWidth: selected ? 2 : 0).padding(-2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func slider(_ title: String, value: WritableKeyPath<AnnotationDocument, Double>, range: ClosedRange<Double>, unit: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11))
                .frame(width: 52, alignment: .leading)
            Slider(
                value: Binding(
                    get: { document[keyPath: value] },
                    set: { newValue in update(title) { $0[keyPath: value] = newValue } }
                ),
                in: range,
                step: 2,
                onEditingChanged: { editing in
                    if !editing { undoRedoManager.breakCoalescing() }
                }
            )
            Text("\(Int(document[keyPath: value]))\(unit)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}
