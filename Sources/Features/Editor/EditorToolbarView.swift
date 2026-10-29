import AppKit
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
    var onAutoRedact: (() -> Void)?
    var secondaryActions: [EditorToolbarAction]
    var closeTitle: String
    var closeHelp: String
    var onClose: () -> Void

    @State private var isShowingStyle = false
    @State private var isShowingInk = false

    private let standardColors: [AnnotationColor] = [
        .red,
        AnnotationColor(red: 1.0, green: 0.85, blue: 0.10), // Neon Yellow
        AnnotationColor(red: 0.15, green: 0.80, blue: 0.35), // Green
        AnnotationColor(red: 0.20, green: 0.55, blue: 1.0),  // Vivid Blue
        AnnotationColor(red: 0.65, green: 0.25, blue: 0.90), // Purple
        .white,
        .black
    ]

    private static let drawTools: [(EditorTool, String)] = [
        (.select, "V"), (.arrow, "A"), (.rectangle, "R"), (.ellipse, "O"), (.freehand, "P")
    ]
    private static let markTools: [(EditorTool, String)] = [(.highlight, "H"), (.text, "T"), (.step, "N")]
    private static let redactTools: [(EditorTool, String)] = [(.blur, "B"), (.pixelate, "X")]

    public init(
        undoRedoManager: UndoRedoManager,
        state: EditorState,
        placement: Placement = .docked,
        onUndo: @escaping () -> Void,
        onRedo: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onCopyToClipboard: @escaping () -> Void,
        onAutoRedact: (() -> Void)? = nil,
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
        self.onAutoRedact = onAutoRedact
        self.secondaryActions = secondaryActions
        self.closeTitle = closeTitle
        self.closeHelp = closeHelp
        self.onClose = onClose
    }

    public var body: some View {
        HStack(spacing: 8) {
            // MARK: - 1. Tools, grouped by purpose: draw · mark up · redact
            ToolbarGroup {
                ForEach(Self.drawTools, id: \.0) { toolButton($0.0, shortcut: $0.1) }
            }
            ToolbarGroup {
                ForEach(Self.markTools, id: \.0) { toolButton($0.0, shortcut: $0.1) }
            }
            ToolbarGroup {
                ForEach(Self.redactTools, id: \.0) { toolButton($0.0, shortcut: $0.1) }
                if let onAutoRedact {
                    Button(action: onAutoRedact) {
                        if state.isAutoRedacting {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "eye.slash")
                        }
                    }
                    .buttonStyle(ToolbarIconButtonStyle(isActive: state.isAutoRedacting, activeStyle: .tinted))
                    .disabled(state.isAutoRedacting)
                    .help("Auto-Blur Sensitive Info: emails, phone numbers, cards, keys")
                }
            }

            // MARK: - 2. Ink: color + stroke / size / intensity for the current tool, in one popover
            ToolbarGroup {
                Button {
                    isShowingInk.toggle()
                } label: {
                    inkButtonLabel
                }
                .buttonStyle(ToolbarIconButtonStyle(isActive: isShowingInk, activeStyle: .tinted, fixedWidth: false))
                .help(inkHelp)
                .popover(isPresented: $isShowingInk, arrowEdge: .bottom) {
                    inkPanel
                }
            }

            ToolbarSeparator()

            // MARK: - 3. History
            ToolbarGroup {
                iconButton("arrow.uturn.backward", help: "Undo (⌘Z)", enabled: undoRedoManager.canUndo, action: onUndo)
                iconButton("arrow.uturn.forward", help: "Redo (⇧⌘Z)", enabled: undoRedoManager.canRedo, action: onRedo)
                iconButton("trash", help: "Delete Selection (⌫)", enabled: state.hasSelection, action: onDelete)
            }

            // MARK: - 4. Styling & Recognition
            ToolbarGroup {
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

            // MARK: - 5. Output: secondary actions, then the primary Copy, then close
            HStack(spacing: 4) {
                ForEach(secondaryActions) { item in
                    Button(action: item.action) {
                        Image(systemName: item.symbol)
                    }
                    .buttonStyle(ToolbarIconButtonStyle(isActive: false))
                    .help(item.help)
                }
            }

            Button(action: onCopyToClipboard) {
                Label("Copy", systemImage: "doc.on.doc.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 16)
                    .frame(height: 32)
                    .foregroundStyle(.white)
                    .background(Color.accentColor.gradient, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .help("Copy to Clipboard (⌘C · Return)")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(ToolbarIconButtonStyle(isActive: false, filled: true, size: 28, shape: .circle))
            .accessibilityLabel(closeTitle)
            .help(closeHelp)
        }
        .padding(.horizontal, placement == .floating ? 12 : 14)
        .padding(.vertical, 10)
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
            // Liquid Glass on macOS 26+, vibrancy before; one soft shadow lifts it off the screenshot
            Color.clear
                .hudGlass(cornerRadius: 26)
                .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        }
    }

    // MARK: - Ink (color, stroke, size, intensity)

    private var usesIntensity: Bool { state.tool == .blur || state.tool == .pixelate }
    /// Text and step markers are sized by font size rather than stroke
    private var usesFontSize: Bool { state.tool == .text || state.tool == .step }

    private var currentColor: Color {
        Color(red: state.color.red, green: state.color.green, blue: state.color.blue)
    }

    private var inkHelp: String {
        if usesIntensity { return "Intensity" }
        if state.tool == .step { return "Color & Step Size" }
        return state.tool == .text ? "Color & Text Size" : "Color & Stroke"
    }

    /// Current color swatch (or intensity) so the setting is visible without opening the popover
    @ViewBuilder
    private var inkButtonLabel: some View {
        HStack(spacing: 5) {
            if usesIntensity {
                Image(systemName: state.tool == .blur ? "drop.fill" : "checkerboard.rectangle")
                    .font(.system(size: 12, weight: .medium))
                Text("\(Int(state.blurRadius))")
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
            } else {
                Circle()
                    .fill(currentColor.gradient)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                    .padding(2)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.35), lineWidth: 1.5))
                if usesFontSize {
                    Text("\(Int(state.fontSize))")
                        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                } else if state.tool != .highlight {
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: 12, height: CGFloat(max(1.5, state.strokeWidth / 2)))
                }
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
    }

    private var inkPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelHeader(title: inkHelp, symbol: state.tool.systemIcon)

            if usesIntensity {
                PanelSlider(title: state.tool == .blur ? "Blur Amount" : "Pixel Size", symbol: "drop.halffull",
                            value: $state.blurRadius, range: 8...60, unit: "px")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    PanelSectionTitle("Color")
                    colorChips
                }
                if usesFontSize {
                    PanelSlider(title: state.tool == .step ? "Marker Size" : "Text Size", symbol: "textformat.size",
                                value: $state.fontSize, range: state.tool == .step ? 14...48 : 12...72, unit: "pt")
                } else if state.tool != .highlight {
                    VStack(alignment: .leading, spacing: 8) {
                        PanelSectionTitle("Stroke")
                        HStack(spacing: 6) {
                            ForEach([(2.0, "Fine"), (4.0, "Medium"), (8.0, "Bold")], id: \.0) { width, name in
                                strokeOption(width: width, name: name)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 268)
    }

    /// Visual line-weight choice: shows the actual thickness instead of a word
    private func strokeOption(width: Double, name: String) -> some View {
        let selected = state.strokeWidth == width
        return Button {
            state.strokeWidth = width
        } label: {
            VStack(spacing: 6) {
                Capsule()
                    .fill(currentColor)
                    .frame(width: 34, height: CGFloat(width / 1.6 + 0.5))
                    .frame(height: 8)
                Text(name)
                    .font(.system(size: 10.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(selected ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.15), value: selected)
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
        HStack(spacing: 4) {
            ForEach(standardColors, id: \.self) { color in
                let isSelected = state.color == color
                Circle()
                    .fill(Color(red: color.red, green: color.green, blue: color.blue).gradient)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(color.red + color.green + color.blue > 2.2 ? .black : .white)
                        }
                    }
                    .padding(2)
                    .overlay(Circle().strokeBorder(Color.accentColor.opacity(isSelected ? 1 : 0), lineWidth: 1.5))
                    .contentShape(Circle())
                    .onTapGesture { state.color = color }
                    .help(colorName(color))
                    .animation(.snappy(duration: 0.15), value: isSelected)
            }
            // Compact custom-color well: opens the system color panel
            Circle()
                .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                .frame(width: 20, height: 20)
                .overlay(Circle().fill(.white).frame(width: 8, height: 8))
                .padding(2)
                .contentShape(Circle())
                .onTapGesture { ColorPanelBridge.shared.open(current: currentColor) { state.color = $0 } }
                .help("Custom Color…")
        }
    }

    private func colorName(_ color: AnnotationColor) -> String {
        switch color {
        case .red: return "Red"
        case .white: return "White"
        case .black: return "Black"
        default:
            if color.green > 0.7 && color.red > 0.9 { return "Yellow" }
            if color.green > 0.7 { return "Green" }
            if color.red > 0.5 { return "Purple" }
            return "Blue"
        }
    }
}

// MARK: - Popover Building Blocks

/// Routes the shared system color panel to whichever toolbar opened it
@MainActor
private final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()
    private var onChange: ((AnnotationColor) -> Void)?

    func open(current: Color, onChange: @escaping (AnnotationColor) -> Void) {
        self.onChange = onChange
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = NSColor(current)
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        // Above the capture overlay
        panel.level = .screenSaver + 1
        panel.orderFrontRegardless()
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        guard let rgb = sender.color.usingColorSpace(.sRGB) else { return }
        onChange?(AnnotationColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent))
    }
}

/// Popover title row: tool glyph on a tinted tile + title
private struct PanelHeader: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 0)
        }
    }
}

private struct PanelSectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

/// Labeled slider with an icon and a value pill
struct PanelSlider: View {
    let title: String
    let symbol: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(value)) \(unit)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }
            Slider(value: $value, in: range, step: 2, onEditingChanged: onEditingChanged)
                .controlSize(.small)
        }
    }
}

// MARK: - Toolbar Building Blocks

/// Inset well that groups related controls
private struct ToolbarGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 2) { content }
            .padding(3)
            .frame(minHeight: 38)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct ToolbarSeparator: View {
    var height: CGFloat = 24

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
    var size: CGFloat = 32
    var shape: Shape = .rounded

    enum Shape { case rounded, circle }

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, style: self)
    }

    private struct StyledLabel: View {
        let configuration: ButtonStyleConfiguration
        let style: ToolbarIconButtonStyle
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: style.shape == .circle ? style.size / 2 : 9, style: .continuous)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                PanelHeader(title: "Background & Frame", symbol: "paintpalette")
                Button("Reset") {
                    update("reset") { doc in
                        doc.backgroundPresetID = nil
                        doc.backgroundColor = nil
                        doc.padding = 0
                        doc.cornerRadius = 0
                        doc.shadowRadius = 0
                    }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12, weight: .medium))
                .disabled(!document.hasStyling)
            }

            VStack(alignment: .leading, spacing: 8) {
                PanelSectionTitle("Background")
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 8), count: 5), spacing: 8) {
                    swatch(selected: document.backgroundPresetID == nil && document.backgroundColor == nil, help: "None") {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06))
                            Image(systemName: "nosign").font(.system(size: 13)).foregroundColor(.secondary)
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
                            Self.applyFrameDefaults(&doc)
                        }
                    }

                    ForEach(BackgroundPresets.all) { preset in
                        swatch(selected: document.backgroundPresetID == preset.id, help: preset.name) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(
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
                                Self.applyFrameDefaults(&doc)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                PanelSectionTitle("Frame")
                slider("Padding", symbol: "arrow.up.left.and.arrow.down.right", value: \.padding, range: 0...160)
                slider("Corners", symbol: "square.dashed", value: \.cornerRadius, range: 0...48)
                slider("Shadow", symbol: "shadow", value: \.shadowRadius, range: 0...80)
            }
        }
        .padding(16)
        .frame(width: 268)
    }

    /// A backdrop is invisible without padding: give it sensible defaults on first use
    private static func applyFrameDefaults(_ doc: inout AnnotationDocument) {
        if doc.padding == 0 { doc.padding = 48 }
        if doc.cornerRadius == 0 { doc.cornerRadius = 10 }
        if doc.shadowRadius == 0 { doc.shadowRadius = 24 }
    }

    private func update(_ key: String, _ mutate: (inout AnnotationDocument) -> Void) {
        undoRedoManager.updateDocument(coalescingKey: "style-\(key)", mutate)
    }

    private func swatch<Content: View>(selected: Bool, help: String, @ViewBuilder content: () -> Content, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            content()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .padding(2)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func slider(_ title: String, symbol: String, value: WritableKeyPath<AnnotationDocument, Double>, range: ClosedRange<Double>) -> some View {
        PanelSlider(
            title: title,
            symbol: symbol,
            value: Binding(
                get: { document[keyPath: value] },
                set: { newValue in update(title) { $0[keyPath: value] = newValue } }
            ),
            range: range,
            unit: "pt",
            onEditingChanged: { editing in
                if !editing { undoRedoManager.breakCoalescing() }
            }
        )
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
                .frame(width: 38, height: 38)
                .clipShape(shape)
        } else {
            shape.fill(Color.secondary.opacity(0.2))
                .overlay(Image(systemName: "photo").font(.system(size: 12)).foregroundStyle(.secondary))
        }
    }
}
