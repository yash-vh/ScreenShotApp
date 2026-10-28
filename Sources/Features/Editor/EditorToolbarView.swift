import SwiftUI

/// A trailing action button on the editor toolbar (Save, Upload, …)
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
        HStack(spacing: 8) {
            // MARK: - 1. Tools Group
            ToolbarGroup {
                ForEach(Self.toolOrder, id: \.0) { tool, shortcut in
                    toolButton(tool, shortcut: shortcut)
                }
            }

            // MARK: - 2. Contextual Properties (Color, Thickness, or Intensity)
            ToolbarGroup {
                contextualProperties
                    .padding(.horizontal, 6)
            }

            ToolbarSeparator()

            // MARK: - 3. History & Layer Actions
            HStack(spacing: 2) {
                iconButton("arrow.uturn.backward", help: "Undo (⌘Z)", enabled: undoRedoManager.canUndo, action: onUndo)
                iconButton("arrow.uturn.forward", help: "Redo (⇧⌘Z)", enabled: undoRedoManager.canRedo, action: onRedo)
                iconButton("trash", help: "Delete Selection (⌫)", enabled: state.hasSelection, action: onDelete)
            }

            ToolbarSeparator()

            // MARK: - 4. Styling & Recognition
            HStack(spacing: 2) {
                Button {
                    isShowingStyle.toggle()
                } label: {
                    Image(systemName: "paintpalette")
                }
                .buttonStyle(ToolbarIconButtonStyle(isActive: undoRedoManager.document.hasStyling, activeStyle: .tinted))
                .help("Background, Padding & Shadow")
                .popover(isPresented: $isShowingStyle, arrowEdge: .bottom) {
                    StylePanel(undoRedoManager: undoRedoManager)
                }

                Button {
                    state.isShowingRecognition.toggle()
                } label: {
                    if state.isRecognizing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "text.viewfinder")
                    }
                }
                .buttonStyle(ToolbarIconButtonStyle(isActive: state.isShowingRecognition))
                .help("Recognize Text & QR Codes (⇧⌘T)")
            }

            if placement == .docked {
                Spacer(minLength: 8)
            } else {
                ToolbarSeparator()
            }

            // MARK: - 5. Direct Actions
            HStack(spacing: 6) {
                Button(action: onCopyToClipboard) {
                    Label("Copy", systemImage: "doc.on.doc.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .foregroundStyle(.white)
                        .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: Color.accentColor.opacity(0.4), radius: 4, y: 1)
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .help("Copy to Clipboard (⌘C)")

                ForEach(secondaryActions) { item in
                    Button(action: item.action) {
                        Image(systemName: item.symbol)
                    }
                    .buttonStyle(ToolbarIconButtonStyle(isActive: false, filled: true))
                    .help(item.help)
                }

                Button(action: onClose) {
                    Text(closeTitle)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                }
                .buttonStyle(ToolbarIconButtonStyle(isActive: false, fixedWidth: false))
                .help(closeHelp)
            }
        }
        .padding(.horizontal, placement == .floating ? 10 : 12)
        .padding(.vertical, 8)
        .fixedSize(horizontal: placement == .floating, vertical: false)
        .background(toolbarBackground)
        .animation(.snappy(duration: 0.18), value: state.tool)
        .animation(.snappy(duration: 0.18), value: state.isShowingRecognition)
    }

    @ViewBuilder
    private var toolbarBackground: some View {
        switch placement {
        case .docked:
            Rectangle().fill(.ultraThinMaterial)
        case .floating:
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            shape
                .fill(.ultraThinMaterial)
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                )
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                .shadow(color: .black.opacity(0.32), radius: 18, y: 8)
        }
    }

    // MARK: - Contextual Properties

    @ViewBuilder
    private var contextualProperties: some View {
        if state.tool == .blur || state.tool == .pixelate {
            HStack(spacing: 6) {
                Image(systemName: state.tool == .blur ? "drop.fill" : "checkerboard.rectangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Slider(value: $state.blurRadius, in: 8...60, step: 2)
                    .controlSize(.small)
                    .frame(width: 90)
                Text("\(Int(state.blurRadius))px")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .leading)
            }
        } else if state.tool == .text {
            HStack(spacing: 6) {
                Image(systemName: "textformat.size")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Slider(value: $state.fontSize, in: 12...72, step: 2)
                    .controlSize(.small)
                    .frame(width: 76)
                Text("\(Int(state.fontSize))pt")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .leading)
                ToolbarSeparator(height: 16)
                colorChips
            }
        } else {
            HStack(spacing: 8) {
                colorChips
                if state.tool != .highlight {
                    ToolbarSeparator(height: 16)
                    HStack(spacing: 2) {
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
        }
        .buttonStyle(ToolbarIconButtonStyle(isActive: state.tool == tool))
        .help("\(tool.rawValue) (\(shortcut))")
    }

    private func iconButton(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(ToolbarIconButtonStyle(isActive: false))
        .disabled(!enabled)
        .help(help)
    }

    private var colorChips: some View {
        HStack(spacing: 6) {
            ForEach(standardColors, id: \.self) { color in
                let isSelected = state.color == color
                Circle()
                    .fill(Color(red: color.red, green: color.green, blue: color.blue).gradient)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                    .padding(2)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.85 : 0), lineWidth: 1.5))
                    .scaleEffect(isSelected ? 1.06 : 1)
                    .contentShape(Circle())
                    .onTapGesture { state.color = color }
                    .animation(.snappy(duration: 0.15), value: isSelected)
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
        }
        .buttonStyle(ToolbarIconButtonStyle(isActive: state.strokeWidth == width, activeStyle: .tinted, size: 24))
        .help(label)
    }
}

// MARK: - Toolbar Building Blocks

/// Inset well that groups related controls
private struct ToolbarGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 2) { content }
            .padding(3)
            .frame(minHeight: 36)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct ToolbarSeparator: View {
    var height: CGFloat = 22

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: height)
    }
}

/// Icon button with hover and pressed feedback; `isActive` highlights the current tool or toggle
private struct ToolbarIconButtonStyle: ButtonStyle {
    enum ActiveStyle { case filled, tinted }

    var isActive: Bool
    var activeStyle: ActiveStyle = .filled
    var filled = false
    var fixedWidth = true
    var size: CGFloat = 30

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, style: self)
    }

    private struct StyledLabel: View {
        let configuration: ButtonStyleConfiguration
        let style: ToolbarIconButtonStyle
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            configuration.label
                .font(.system(size: 13, weight: style.isActive ? .semibold : .medium))
                .frame(width: style.fixedWidth ? style.size : nil, height: style.size)
                .foregroundStyle(foreground)
                .background(background, in: shape)
                .contentShape(shape)
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .opacity(isEnabled ? 1 : 0.35)
                .onHover { isHovered = $0 }
                .animation(.snappy(duration: 0.12), value: isHovered)
                .animation(.snappy(duration: 0.12), value: configuration.isPressed)
        }

        private var foreground: Color {
            if style.isActive && style.activeStyle == .filled { return .white }
            if style.isActive { return .accentColor }
            return .primary
        }

        private var background: Color {
            if style.isActive {
                return style.activeStyle == .filled ? .accentColor : Color.accentColor.opacity(0.2)
            }
            if isHovered && isEnabled { return Color.primary.opacity(0.1) }
            return style.filled ? Color.primary.opacity(0.06) : .clear
        }
    }
}

/// Subtle press feedback for custom-drawn buttons
private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
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

                swatch(selected: document.backgroundPresetID == BackgroundPresets.desktopID, help: "Desktop Wallpaper") {
                    DesktopWallpaperSwatch()
                } action: {
                    update("background") { doc in
                        doc.backgroundPresetID = BackgroundPresets.desktopID
                        doc.backgroundColor = nil
                        if doc.padding == 0 { doc.padding = 48 }
                        if doc.cornerRadius == 0 { doc.cornerRadius = 10 }
                        if doc.shadowRadius == 0 { doc.shadowRadius = 24 }
                    }
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

/// Thumbnail of the current desktop picture for the Desktop backdrop swatch
private struct DesktopWallpaperSwatch: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        if let wallpaper = DesktopWallpaper.current() {
            Image(decorative: wallpaper, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 30, height: 30)
                .clipShape(shape)
        } else {
            shape.fill(Color.secondary.opacity(0.2))
                .overlay(Image(systemName: "photo").font(.system(size: 12)).foregroundStyle(.secondary))
        }
    }
}
