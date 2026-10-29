import SwiftUI

/// Settings window in the macOS System Settings layout: a sidebar of colored panes and a detail area
/// whose controls take the selected pane's accent color.
public struct SettingsView: View {
    @EnvironmentObject var config: AppConfiguration
    @EnvironmentObject var coordinator: AppCoordinator

    public enum Tab: String, CaseIterable, Identifiable {
        case general = "General"
        case capture = "Capture"
        case recording = "Recording"
        case shortcuts = "Shortcuts"
        case storage = "Storage & Cloud"
        case privacy = "Privacy"
        case diagnostics = "Diagnostics"
        case subscription = "ScreenMint Pro"
        case about = "About"

        public var id: String { rawValue }

        public var systemIcon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .capture: return "camera.fill"
            case .recording: return "record.circle.fill"
            case .shortcuts: return "command"
            case .storage: return "cloud.fill"
            case .privacy: return "hand.raised.fill"
            case .diagnostics: return "terminal.fill"
            case .subscription: return "crown.fill"
            case .about: return "info.circle.fill"
            }
        }

        /// Accent for the pane's switches, pickers and sliders. Matches the tile, except where
        /// the tile color is too muted (gray) or too light (yellow) to read as an "on" switch.
        public var controlTint: Color {
            switch self {
            case .general: return .blue
            case .subscription: return .orange
            default: return color
            }
        }

        /// Sidebar tile color
        public var color: Color {
            switch self {
            case .general: return .gray
            case .capture: return .blue
            case .recording: return .red
            case .shortcuts: return .purple
            case .storage: return .cyan
            case .privacy: return .indigo
            case .diagnostics: return .orange
            case .subscription: return .yellow
            case .about: return .pink
            }
        }

        public var subtitle: String {
            switch self {
            case .general: return "Startup, visibility and background behavior"
            case .capture: return "Where captures go and what happens after"
            case .recording: return "Video, GIF, audio and pointer options"
            case .shortcuts: return "Global hotkeys and in-capture actions"
            case .storage: return "Uploads to ImgBB or Amazon S3, and local cache"
            case .privacy: return "Permissions and redaction"
            case .diagnostics: return "Recent activity for troubleshooting"
            case .subscription: return "Plans, billing and restore"
            case .about: return "Version, support and legal"
            }
        }
    }

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(Tab.allCases, selection: selection) { tab in
                Label {
                    Text(tab.rawValue)
                } icon: {
                    SettingsIconTile(symbol: tab.systemIcon, color: tab.color, size: 22)
                }
                .padding(.vertical, 2)
                .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            pane(for: coordinator.settingsTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tint(coordinator.settingsTab.controlTint)
                .toggleStyle(.switch)
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    private var selection: Binding<Tab?> {
        Binding(get: { coordinator.settingsTab }, set: { if let tab = $0 { coordinator.settingsTab = tab } })
    }

    @ViewBuilder
    private func pane(for tab: Tab) -> some View {
        switch tab {
        case .general: GeneralSettingsTab()
        case .capture: CaptureSettingsTab()
        case .recording: RecordingSettingsTab()
        case .shortcuts: ShortcutsSettingsTab()
        case .storage: StorageSettingsTab()
        case .privacy: PrivacySettingsTab()
        case .diagnostics: DiagnosticsTab()
        case .subscription: SubscriptionSettingsTab()
        case .about: AboutSettingsTab()
        }
    }
}

// MARK: - Shared Settings Components

/// Rounded, gradient-filled symbol tile in the style of System Settings
struct SettingsIconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }
}

/// Settings row title with an optional explanatory line beneath it
struct SettingsRowLabel: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @EnvironmentObject var config: AppConfiguration
    @State private var loginProblem: String?
    @State private var relaunchProblem: String?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { config.launchAtLogin },
                    set: { loginProblem = config.setLaunchAtLogin($0) }
                )) {
                    SettingsRowLabel(title: "Launch at login", subtitle: "Start \(AppBranding.appName) when you log in to your Mac.")
                }
                if let loginProblem {
                    SettingsWarning(loginProblem)
                }
                Toggle(isOn: $config.showDockIcon) {
                    SettingsRowLabel(title: "Show in Dock", subtitle: "When off, \(AppBranding.appName) runs from the menu bar only.")
                }
                Toggle(isOn: $config.showMenuBarIcon) {
                    SettingsRowLabel(
                        title: "Show in menu bar",
                        subtitle: config.showMenuBarIcon
                            ? "Quick access to captures, recording and the Library."
                            : "Hidden. Shortcuts still work; open \(AppBranding.appName) from Finder or Spotlight for Settings."
                    )
                }
                Toggle(isOn: $config.indexInSpotlight) {
                    SettingsRowLabel(
                        title: "Show captures in Spotlight",
                        subtitle: "Find screenshots by name, date or the text inside them. Indexed on this Mac only."
                    )
                }
            } header: {
                Text("Startup & Visibility")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { config.relaunchAfterUnexpectedQuit },
                    set: { enabled in
                        config.relaunchAfterUnexpectedQuit = enabled
                        relaunchProblem = BackgroundRelauncher.setEnabled(enabled)
                        if relaunchProblem != nil, !BackgroundRelauncher.isAgentEnabled {
                            config.relaunchAfterUnexpectedQuit = false
                        }
                    }
                )) {
                    SettingsRowLabel(
                        title: "Reopen after a force quit or crash",
                        subtitle: "Keeps the menu and shortcuts available. Quitting from the menu still quits."
                    )
                }
                if let relaunchProblem {
                    SettingsWarning(relaunchProblem)
                }
            } header: {
                Text("Background")
            } footer: {
                Text("Turning this on restarts \(AppBranding.appName) once and also starts it at login.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Toggle(isOn: Binding(
                        get: { config.captureSettings.playCaptureSound },
                        set: { enabled in
                            config.captureSettings.playCaptureSound = enabled
                            if enabled {
                                SoundManager.playShutterSound()
                            }
                        }
                    )) {
                        SettingsRowLabel(title: "Shutter sound", subtitle: "Play a camera shutter sound when a capture is taken.")
                    }
                    Button {
                        SoundManager.playShutterSound()
                    } label: {
                        Label("Test Sound", systemImage: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Play sample shutter sound")
                }
            } header: {
                Text("Audio Feedback")
            }
        }
        .formStyle(.grouped)
    }
}

/// Inline problem message under a settings row
struct SettingsWarning: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.orange)
    }
}

// MARK: - Capture Tab

struct CaptureSettingsTab: View {
    @EnvironmentObject var config: AppConfiguration
    @State private var folderProblem: String?

    var body: some View {
        Form {
            Section {
                Toggle("Save captures to a folder", isOn: $config.captureSettings.saveToDisk)

                if config.captureSettings.saveToDisk {
                    Picker("Save to", selection: saveLocationBinding) {
                        ForEach(SaveLocation.allCases) { location in
                            Label(location.displayName, systemImage: location.systemImage).tag(location)
                        }
                    }

                    LabeledContent("Folder") {
                        HStack(spacing: 8) {
                            Image(systemName: folderProblem == nil ? "folder.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(folderProblem == nil ? .accentColor : .orange)
                            Text(displayPath(config.configuredSaveDirectory))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .help(config.configuredSaveDirectory.path)
                            Spacer()
                            Button("Change…") { chooseCustomFolder() }
                            Button("Show in Finder") { showInFinder() }
                        }
                    }

                    if let folderProblem {
                        Text(folderProblem)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                } else {
                    Text("Captures are kept only in the Library (Application Support) and count toward the cache limit in Storage & Cloud.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Save Location")
            } footer: {
                if config.captureSettings.saveToDisk {
                    Text("Screen recordings are saved to the same folder. The folder is created automatically.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("Image Resolution & Quality")) {
                Picker("Resolution", selection: $config.captureSettings.imageResolution) {
                    ForEach(ImageResolution.allCases) { res in
                        Text(res.displayName).tag(res)
                    }
                }
                .pickerStyle(.segmented)

                Text(config.captureSettings.imageResolution == .retina
                     ? "Retina captures at native 2x display pixel density for maximum clarity."
                     : "Standard scales captures to 1x logical resolution for 50% smaller dimensions and compact file size.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Format", selection: $config.captureSettings.defaultFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                if config.captureSettings.defaultFormat == .jpeg {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("JPEG quality") {
                            HStack {
                                Slider(value: $config.captureSettings.jpegQuality, in: 0.5...1.0, step: 0.05)
                                Text("\(Int(config.captureSettings.jpegQuality * 100))%")
                                    .monospacedDigit()
                                    .frame(width: 45, alignment: .trailing)
                            }
                        }

                        HStack(spacing: 8) {
                            Text("Presets:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("Medium (70%)") { config.captureSettings.jpegQuality = 0.70 }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            Button("High (85%)") { config.captureSettings.jpegQuality = 0.85 }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            Button("Maximum (100%)") { config.captureSettings.jpegQuality = 1.0 }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                        }

                        Text(qualityDescription(config.captureSettings.jpegQuality))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    LabeledContent("Quality") {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                            Text("Lossless (100% Quality)")
                                .fontWeight(.medium)
                        }
                    }
                    Text("PNG maintains pixel-perfect fidelity with no compression artifacts. Ideal for screenshots with UI, text, and code.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                TextField("File name prefix", text: $config.captureSettings.fileNamePrefix, prompt: Text("Screenshot"))
                LabeledContent("Example file name") {
                    Text(exampleFileName)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("Feedback")) {
                HStack {
                    Toggle("Play shutter sound on capture", isOn: Binding(
                        get: { config.captureSettings.playCaptureSound },
                        set: { enabled in
                            config.captureSettings.playCaptureSound = enabled
                            if enabled {
                                SoundManager.playShutterSound()
                            }
                        }
                    ))
                    Spacer()
                    Button {
                        SoundManager.playShutterSound()
                    } label: {
                        Label("Test Sound", systemImage: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Play sample shutter sound")
                }
            }

            Section {
                Toggle("Copy image to clipboard", isOn: $config.captureSettings.copyToClipboard)
                Toggle("Recognize text for Library search (OCR, on-device)", isOn: $config.captureSettings.runOcrAutomatically)
            } header: {
                Text("After Full Screen & Window Capture")
            } footer: {
                Text("Region captures use the toolbar instead: Return copies, ⌘S saves, ⌘U uploads and copies the link.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshFolderStatus)
        .onChange(of: config.captureSettings.saveLocation) { _ in refreshFolderStatus() }
        .onChange(of: config.captureSettings.customSaveDirectory) { _ in refreshFolderStatus() }
        .onChange(of: config.captureSettings.saveToDisk) { _ in refreshFolderStatus() }
    }

    private func qualityDescription(_ quality: Double) -> String {
        switch quality {
        case 0.95...1.0:
            return "Maximum quality: Best visual fidelity, larger file size."
        case 0.80..<0.95:
            return "High quality (Recommended): Excellent balance of sharpness and file size."
        case 0.65..<0.80:
            return "Medium quality: Good for quick sharing and smaller attachments."
        default:
            return "Compact quality: Smallest file size, some compression artifacts may be visible."
        }
    }

    /// Picking "Custom Folder…" without a folder yet opens the chooser straight away
    private var saveLocationBinding: Binding<SaveLocation> {
        Binding(
            get: { config.captureSettings.saveLocation },
            set: { location in
                if location == .custom {
                    config.captureSettings.saveLocation = .custom
                    if (config.captureSettings.customSaveDirectory ?? "").isEmpty {
                        chooseCustomFolder()
                    }
                } else {
                    config.captureSettings.saveLocation = location
                }
                refreshFolderStatus()
            }
        )
    }

    private var exampleFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let ext = config.captureSettings.defaultFormat == .jpeg ? "jpg" : "png"
        return "\(config.captureSettings.sanitizedFileNamePrefix) \(formatter.string(from: Date())).\(ext)"
    }

    private func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    private func refreshFolderStatus() {
        folderProblem = config.captureSettings.saveToDisk ? config.saveDirectoryProblem() : nil
    }

    private func chooseCustomFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Save Folder"
        panel.prompt = "Set Folder"
        panel.message = "Choose a destination folder for ScreenMint captures and recordings"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        var initialURL = config.configuredSaveDirectory
        if !FileManager.default.fileExists(atPath: initialURL.path) {
            if (try? FileManager.default.createDirectory(at: initialURL, withIntermediateDirectories: true)) == nil {
                initialURL = FileManager.default.homeDirectoryForCurrentUser
            }
        }
        panel.directoryURL = initialURL

        NSApp.activate(ignoringOtherApps: true)

        let applyURL: (URL) -> Void = { url in
            config.captureSettings.customSaveDirectory = url.path
            config.captureSettings.saveLocation = .custom
            refreshFolderStatus()
        }

        if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && !$0.isExcludedFromWindowsMenu }) {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url {
                    applyURL(url)
                }
            }
        } else {
            panel.level = .floating
            if panel.runModal() == .OK, let url = panel.url {
                applyURL(url)
            }
        }
    }

    private func showInFinder() {
        let url = config.resolveLocalSaveDirectory()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
        refreshFolderStatus()
    }
}

// MARK: - Recording Tab

struct RecordingSettingsTab: View {
    @EnvironmentObject var config: AppConfiguration

    var body: some View {
        Form {
            Section(header: Text("Output")) {
                Picker("Save as", selection: $config.recordingSettings.outputFormat) {
                    ForEach(RecordingOutputFormat.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)

                if config.recordingSettings.outputFormat == .mp4 {
                    Picker("Codec", selection: $config.recordingSettings.codec) {
                        ForEach(RecordingCodec.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Frame rate", selection: $config.recordingSettings.frameRate) {
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }
                } else {
                    Picker("GIF frame rate", selection: $config.recordingSettings.gifFrameRate) {
                        Text("10 fps").tag(10)
                        Text("15 fps").tag(15)
                        Text("20 fps").tag(20)
                        Text("25 fps").tag(25)
                    }
                    Picker("GIF size", selection: $config.recordingSettings.gifMaxPixelSize) {
                        Text("Small (480 px)").tag(480)
                        Text("Medium (800 px)").tag(800)
                        Text("Large (1280 px)").tag(1280)
                        Text("Original").tag(0)
                    }
                }
                LabeledContent("Saved to") {
                    Text(config.captureSettings.saveToDisk
                         ? (config.configuredSaveDirectory.path as NSString).abbreviatingWithTildeInPath
                         : "Library only")
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if config.recordingSettings.outputFormat == .mp4 {
                Section(header: Text("Audio")) {
                    Toggle("Record microphone (voiceover)", isOn: $config.recordingSettings.recordMicrophone)
                    Toggle("Record system audio", isOn: $config.recordingSettings.recordSystemAudio)
                }
            }

            Section(header: Text("Pointer")) {
                Toggle("Show cursor", isOn: $config.recordingSettings.showCursor)
                if #available(macOS 15.0, *) {
                    Toggle("Highlight mouse clicks", isOn: $config.recordingSettings.showClicks)
                }
            }

            Section(header: Text("Safety")) {
                Picker("Stop when free disk space falls below", selection: $config.recordingSettings.minimumFreeSpaceMB) {
                    Text("512 MB").tag(512)
                    Text("1 GB").tag(1024)
                    Text("5 GB").tag(5120)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcuts Tab

struct ShortcutsSettingsTab: View {
    @EnvironmentObject var config: AppConfiguration
    @ObservedObject private var hotKeys = HotKeyManager.shared
    @State private var showingAddSheet = false

    var body: some View {
        Form {
            Section(header: Text("In-Place Capture & Actions")) {
                ShortcutRecorderRow(
                    label: "Copy Selection",
                    icon: "doc.on.doc.fill",
                    binding: $config.captureSettings.shortcutCopy,
                    defaultBinding: ShortcutBinding(key: "C", modifiers: ["⌘"])
                )

                ShortcutRecorderRow(
                    label: "Upload & Share Link",
                    icon: "icloud.and.arrow.up.fill",
                    binding: $config.captureSettings.shortcutUpload,
                    defaultBinding: ShortcutBinding(key: "U", modifiers: ["⌘"])
                )

                ShortcutRecorderRow(
                    label: "Cancel Capture / Selection",
                    icon: "xmark.circle.fill",
                    binding: $config.captureSettings.shortcutCancel,
                    defaultBinding: ShortcutBinding(key: "Esc", modifiers: [])
                )
            }

            Section(header: Text("Global Screen Capture")) {
                ShortcutRecorderRow(
                    label: "Capture Selected Region",
                    icon: "crop",
                    binding: $config.captureSettings.shortcutRegion,
                    defaultBinding: .defaultRegion
                )

                ShortcutRecorderRow(
                    label: "Capture Full Screen",
                    icon: "macwindow",
                    binding: $config.captureSettings.shortcutFullScreen,
                    defaultBinding: .defaultFullScreen
                )

                ShortcutRecorderRow(
                    label: "Capture All Screens",
                    icon: "rectangle.on.rectangle",
                    binding: $config.captureSettings.shortcutAllScreens,
                    defaultBinding: .defaultAllScreens
                )

                ShortcutRecorderRow(
                    label: "Capture Window",
                    icon: "macwindow.on.rectangle",
                    binding: $config.captureSettings.shortcutWindow,
                    defaultBinding: .defaultWindow
                )

                ShortcutRecorderRow(
                    label: "Record Screen",
                    icon: "record.circle",
                    binding: $config.captureSettings.shortcutRecording,
                    defaultBinding: .defaultRecording
                )

                ShortcutRecorderRow(
                    label: "OCR Text from Screen",
                    icon: "text.viewfinder",
                    binding: $config.captureSettings.shortcutQuickOcr,
                    defaultBinding: .defaultQuickOcr
                )

                VStack(alignment: .leading, spacing: 4) {
                    Label("macOS's own screenshot keys (⇧⌘3, ⇧⌘4, ⇧⌘5, ⇧⌘6) are left to macOS, so both tools work side by side.", systemImage: "info.circle")
                        .foregroundColor(.secondary)
                    if !hotKeys.failedBindings.isEmpty {
                        Label("Unavailable (in use by another app): \(hotKeys.failedBindings.joined(separator: ", "))", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    }
                }
                .font(.caption)
            }

            Section(header: Text("User Custom Shortcuts")) {
                if config.captureSettings.customShortcuts.isEmpty {
                    Text("No custom shortcuts added yet. You can add your own custom shortcuts below.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach($config.captureSettings.customShortcuts) { $item in
                        ShortcutRecorderRow(
                            label: "\(item.name) (\(item.action))",
                            icon: "star.fill",
                            binding: $item.binding,
                            defaultBinding: item.binding,
                            onDelete: {
                                config.captureSettings.customShortcuts.removeAll { $0.id == item.id }
                            }
                        )
                    }
                }

                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add New Shortcut...", systemImage: "plus.circle.fill")
                        .fontWeight(.medium)
                }
                .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAddSheet) {
            AddShortcutSheet(isPresented: $showingAddSheet) { newItem in
                config.captureSettings.customShortcuts.append(newItem)
            }
        }
    }
}

// MARK: - Interactive Shortcut Recorder Row

struct ShortcutRecorderRow: View {
    let label: String
    let icon: String
    @Binding var binding: ShortcutBinding
    let defaultBinding: ShortcutBinding
    var onDelete: (() -> Void)? = nil

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var rejection: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 20)

            Text(label)
                .font(.body)

            Spacer()

            if isRecording {
                Button {
                    stopRecording()
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("Type keys (or Esc)...")
                            .font(.system(.subheadline, design: .monospaced).bold())
                            .foregroundColor(.accentColor)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 1.5).background(Color.accentColor.opacity(0.12)))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    startRecording()
                } label: {
                    HStack(spacing: 6) {
                        Text(binding.displayString.isEmpty ? "None" : binding.displayString)
                            .font(.system(.body, design: .monospaced).bold())
                            .foregroundColor(.primary)

                        Image(systemName: "pencil")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .help("Click to record a new shortcut key")
            }

            if binding != defaultBinding {
                Button {
                    binding = defaultBinding
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reset to default (\(defaultBinding.displayString))")
            }

            if let onDelete = onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.85))
                }
                .buttonStyle(.plain)
                .help("Delete custom shortcut")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let note = rowNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .offset(y: 16)
            }
        }
        .padding(.bottom, rowNote != nil ? 14 : 0)
        .onDisappear {
            stopRecording()
        }
    }

    /// Why the key just typed was refused, or which app also uses the saved shortcut
    private var rowNote: String? {
        if isRecording { return rejection }
        return binding.knownAppConflict.map { "Also used by \($0); \(AppBranding.appName) takes it while running." }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        // Release global hotkeys so the keys being recorded aren't swallowed by Carbon
        HotKeyManager.shared.suspend()

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            var mods: [String] = []
            if flags.contains(.control) { mods.append("⌃") }
            if flags.contains(.option) { mods.append("⌥") }
            if flags.contains(.shift) { mods.append("⇧") }
            if flags.contains(.command) { mods.append("⌘") }

            // Record by key code so Shift doesn't turn "4" into "$"
            var keyName = KeyCodeMap.name(for: event.keyCode)
            if keyName == nil, let chars = event.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty {
                keyName = chars
            }

            if let key = keyName {
                // If bare Esc was pressed without modifiers and user was NOT recording the Cancel action:
                if key == "Esc" && mods.isEmpty && !self.label.lowercased().contains("cancel") {
                    DispatchQueue.main.async {
                        self.stopRecording()
                    }
                    return nil
                }

                let candidate = ShortcutBinding(key: key, modifiers: mods)
                DispatchQueue.main.async {
                    if candidate.isMacOSScreenshotShortcut {
                        // Keep listening so the user can try another combination
                        self.rejection = "\(candidate.displayString) belongs to macOS Screenshot. Try ⇧⌘ with 6–0, or ⌃⌥ with a key."
                        return
                    }
                    self.rejection = nil
                    self.binding = candidate
                    self.stopRecording()
                }
                return nil
            }

            return nil
        }
    }

    private func stopRecording() {
        if let mon = monitor {
            NSEvent.removeMonitor(mon)
            monitor = nil
        }
        if isRecording {
            HotKeyManager.shared.resume()
        }
        isRecording = false
        rejection = nil
    }
}

// MARK: - Add New Custom Shortcut Sheet

struct AddShortcutSheet: View {
    @Binding var isPresented: Bool
    var onAdd: (CustomShortcutItem) -> Void

    @State private var name: String = ""
    @State private var selectedAction: String = "Copy Selection"
    @State private var recordedBinding = ShortcutBinding(key: "C", modifiers: ["⌘"])

    private let availableActions = [
        "Copy Selection",
        "Upload & Share Link",
        "Cancel Capture",
        "Capture Selected Region",
        "Capture Full Screen",
        "Capture Window",
        "Record Screen",
        "OCR Text from Screen",
        "Capture All Screens"
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("Add New Shortcut")
                .font(.headline)
                .padding(.top, 8)

            Form {
                TextField("Shortcut Name", text: $name, prompt: Text("e.g. Quick Copy / Cloud Upload"))

                Picker("Action", selection: $selectedAction) {
                    ForEach(availableActions, id: \.self) { act in
                        Text(act).tag(act)
                    }
                }

                HStack {
                    Text("Shortcut Key:")
                    Spacer()
                    ShortcutRecorderRow(
                        label: "",
                        icon: "command",
                        binding: $recordedBinding,
                        defaultBinding: recordedBinding
                    )
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add Shortcut") {
                    let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedAction : name
                    let item = CustomShortcutItem(name: finalName, action: selectedAction, binding: recordedBinding)
                    onAdd(item)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .frame(width: 440, height: 280)
        .padding()
    }
}

// MARK: - Storage & Cloud Tab

struct StorageSettingsTab: View {
    @EnvironmentObject var config: AppConfiguration
    @ObservedObject private var history = HistoryStore.shared
    @State private var s3AccessKeyID = ""
    @State private var s3SecretAccessKey = ""
    @State private var s3KeysSaved = false
    @State private var imgbbAPIKey = ""
    @State private var imgbbKeySaved = false
    @State private var testState: TestState = .idle
    @State private var usage = StorageUsage(cacheBytes: 0, thumbnailBytes: 0, savedBytes: 0, databaseBytes: 0)

    enum TestState: Equatable {
        case idle, running
        case success(URL)
        case failure(String)
    }

    private var destination: Binding<UploadDestination> {
        Binding(
            get: { config.uploadDestination },
            set: { config.uploadDestination = $0; testState = .idle }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Upload to", selection: destination) {
                    ForEach(UploadDestination.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Uploads")
            } footer: {
                Text(config.uploadDestination == .off
                     ? "Screenshots stay on this Mac. The Upload button asks you to pick a destination."
                     : "The Upload button (⌘U) uploads right away and copies the link to the clipboard.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            switch config.uploadDestination {
            case .imgbb: imgbbSection
            case .s3: s3Section
            case .off: EmptyView()
            }

            if config.uploadDestination != .off {
                Section(header: Text("Links")) {
                    Picker("Short link", selection: $config.linkShortener) {
                        ForEach(LinkShortener.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Delete after", selection: $config.uploadExpiry) {
                        ForEach(UploadExpiry.allCases) { Text($0.title).tag($0) }
                    }
                    if let note = linkNote {
                        Text(note).font(.caption).foregroundColor(.secondary)
                    }
                    testRow
                }
            }

            Section(header: Text("Local Storage Maintenance")) {
                StorageMeter(usage: usage, quotaBytes: Int64(config.cacheQuotaMB) * 1_048_576)
                Picker("Cache limit", selection: $config.cacheQuotaMB) {
                    Text("512 MB").tag(512)
                    Text("1 GB").tag(1024)
                    Text("2 GB").tag(2048)
                    Text("5 GB").tag(5120)
                    Text("Unlimited").tag(0)
                }
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(history.assets.count) captures in history")
                        Text("Cached captures live in Application Support; saved files in your folders are never deleted by cleanup.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Open Library") { AppCoordinator.shared.openLibrary() }
                    Button("Clean Up Cache") {
                        history.cleanUpCache(olderThanDays: 30)
                        usage = history.storageUsage()
                    }
                    .help("Remove cached captures older than 30 days and regenerate thumbnails on demand")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            usage = history.storageUsage()
            s3AccessKeyID = (try? KeychainStore.shared.value(for: KeychainStore.Account.s3AccessKeyID)) ?? ""
            s3KeysSaved = !s3AccessKeyID.isEmpty && ((try? KeychainStore.shared.value(for: KeychainStore.Account.s3SecretAccessKey)) ?? nil)?.isEmpty == false
            imgbbKeySaved = ((try? KeychainStore.shared.value(for: KeychainStore.Account.imgbbAPIKey)) ?? nil)?.isEmpty == false
        }
        .onChange(of: config.cacheQuotaMB) { _ in
            history.enforceCacheQuota()
            usage = history.storageUsage()
        }
    }

    // MARK: Provider sections

    private var imgbbSection: some View {
        Section(header: Text("ImgBB")) {
            HStack {
                SecureField("API key", text: $imgbbAPIKey, prompt: Text(imgbbKeySaved ? "Saved in Keychain" : "Paste your API key"))
                    .onSubmit(saveImgBBKey)
                Button("Save", action: saveImgBBKey)
                    .disabled(imgbbAPIKey.trimmingCharacters(in: .whitespaces).isEmpty)
                if imgbbKeySaved {
                    Button("Remove") {
                        KeychainStore.shared.remove(KeychainStore.Account.imgbbAPIKey)
                        imgbbKeySaved = false
                        testState = .idle
                    }
                }
            }
            HStack(spacing: 4) {
                Label(imgbbKeySaved ? "Key saved" : "No key yet", systemImage: imgbbKeySaved ? "checkmark.circle.fill" : "key")
                    .foregroundColor(imgbbKeySaved ? .green : .secondary)
                Spacer()
                Link("Get a free key", destination: URL(string: "https://api.imgbb.com/")!)
            }
            .font(.caption)
        }
    }

    private var s3Section: some View {
        Section(header: Text("Amazon S3 / S3-Compatible")) {
            TextField("Bucket", text: $config.s3Bucket, prompt: Text("my-screenshots"))
            TextField("Region", text: $config.s3Region, prompt: Text("us-east-1"))
            TextField("Endpoint", text: $config.s3Endpoint, prompt: Text("Leave empty for AWS · R2/B2/MinIO URL"))
            TextField("Public URL", text: $config.s3PublicBaseURL, prompt: Text("Optional · https://cdn.example.com"))
            TextField("Access key ID", text: $s3AccessKeyID)
            SecureField("Secret access key", text: $s3SecretAccessKey, prompt: Text(s3KeysSaved ? "Saved in Keychain" : ""))
                .onSubmit(saveS3Keys)
            HStack {
                Label(s3KeysSaved ? "Keys saved in Keychain" : "Keys not saved", systemImage: s3KeysSaved ? "checkmark.circle.fill" : "key")
                    .font(.caption)
                    .foregroundColor(s3KeysSaved ? .green : .secondary)
                Spacer()
                Button("Save Keys", action: saveS3Keys)
                    .disabled(s3AccessKeyID.trimmingCharacters(in: .whitespaces).isEmpty || s3SecretAccessKey.isEmpty)
                if s3KeysSaved {
                    Button("Remove Keys") {
                        KeychainStore.shared.remove(KeychainStore.Account.s3AccessKeyID)
                        KeychainStore.shared.remove(KeychainStore.Account.s3SecretAccessKey)
                        s3AccessKeyID = ""
                        s3SecretAccessKey = ""
                        s3KeysSaved = false
                        testState = .idle
                    }
                }
            }
            Text("The keys need s3:PutObject and s3:DeleteObject on the bucket. Without a public URL, links are presigned and stop working after 7 days at most.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var linkNote: String? {
        switch config.uploadDestination {
        case .imgbb: return config.uploadExpiry == .never ? "Images stay on ImgBB until you delete them from their delete page." : "ImgBB removes the image automatically."
        case .s3: return config.s3PublicBaseURL.isEmpty ? "Presigned links last at most 7 days." : nil
        default: return nil
        }
    }

    private var testRow: some View {
        HStack(spacing: 8) {
            Button("Test Upload") { runTest() }
                .disabled(testState == .running)
            switch testState {
            case .idle:
                EmptyView()
            case .running:
                ProgressView().controlSize(.small)
                Text("Uploading test image…").font(.caption).foregroundColor(.secondary)
            case .success(let url):
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                Link(url.absoluteString, destination: url)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            case .failure(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: Actions

    private func runTest() {
        // Unsaved typed keys count: save them first so the test uses what's on screen
        if !imgbbAPIKey.trimmingCharacters(in: .whitespaces).isEmpty { saveImgBBKey() }
        if !s3SecretAccessKey.isEmpty, !s3AccessKeyID.isEmpty { saveS3Keys() }
        testState = .running
        Task { @MainActor in
            do {
                testState = .success(try await UploadService.shared.testCurrentDestination())
            } catch {
                testState = .failure(error.localizedDescription)
            }
        }
    }

    private func saveImgBBKey() {
        let key = imgbbAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try KeychainStore.shared.set(key, for: KeychainStore.Account.imgbbAPIKey)
            imgbbAPIKey = ""
            imgbbKeySaved = true
            testState = .idle
        } catch {
            testState = .failure(error.localizedDescription)
        }
    }

    private func saveS3Keys() {
        let keyID = s3AccessKeyID.trimmingCharacters(in: .whitespaces)
        guard !keyID.isEmpty, !s3SecretAccessKey.isEmpty else { return }
        do {
            try KeychainStore.shared.set(keyID, for: KeychainStore.Account.s3AccessKeyID)
            try KeychainStore.shared.set(s3SecretAccessKey.trimmingCharacters(in: .whitespaces), for: KeychainStore.Account.s3SecretAccessKey)
            s3SecretAccessKey = ""
            s3KeysSaved = true
            testState = .idle
        } catch {
            testState = .failure(error.localizedDescription)
        }
    }
}

// MARK: - Privacy Tab

struct PrivacySettingsTab: View {
    @EnvironmentObject var config: AppConfiguration
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject var permissionManager = PermissionManager.shared

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    if permissionManager.isAuthorized {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Open System Settings…") { coordinator.openPrivacySettings() }
                            .buttonStyle(.borderedProminent)
                    }
                } label: {
                    SettingsRowLabel(
                        title: "Screen Recording",
                        subtitle: permissionManager.isAuthorized
                            ? "\(AppBranding.appName) can capture your screen."
                            : "Required to take screenshots and recordings."
                    )
                }

                if !permissionManager.isAuthorized {
                    LabeledContent {
                        HStack(spacing: 8) {
                            Button("Reset") { permissionManager.resetScreenCapturePermission() }
                            Button("Relaunch \(AppBranding.appName)") { permissionManager.relaunchApp() }
                        }
                    } label: {
                        SettingsRowLabel(
                            title: "Already allowed it?",
                            subtitle: "macOS applies the change after \(AppBranding.appName) restarts. Reset if the toggle looks on but captures still fail."
                        )
                    }
                }
            } header: {
                Text("Permissions")
            }

            Section {
                SettingsRowLabel(
                    title: "Redaction is permanent",
                    subtitle: "Blur (B) and Pixelate (X) are flattened into the pixels on export and upload, so shared files never contain the original. Uploads are re-encoded without metadata."
                )
            } header: {
                Text("Redaction & Security")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Diagnostics Tab

struct DiagnosticsTab: View {
    enum LevelFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case problems = "Warnings & Errors"
        var id: String { rawValue }
    }

    @State private var logs: [AppLogger.LogEntry] = []
    @State private var isLoading = true
    @State private var filter: LevelFilter = .all
    @State private var search = ""

    private var visibleLogs: [AppLogger.LogEntry] {
        logs.reversed().filter { entry in
            (filter == .all || [.notice, .error, .fault].contains(entry.level))
                && (search.isEmpty || entry.message.localizedCaseInsensitiveContains(search) || entry.category.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controls
            logList
            Label("Credentials, tokens and your home folder path are redacted. Showing this session's last hour.", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .task { await reload() }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Picker("Show", selection: $filter) {
                ForEach(LevelFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter messages", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.primary.opacity(0.06), in: Capsule())

            Spacer(minLength: 0)

            Group {
                Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh")
                Button { copyAll() } label: { Image(systemName: "doc.on.doc") }
                    .help("Copy visible entries")
                    .disabled(visibleLogs.isEmpty)
                Button {
                    AppLogger.shared.clearLogs()
                    logs = []
                } label: { Image(systemName: "trash") }
                    .help("Clear")
                    .disabled(logs.isEmpty)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
    }

    @ViewBuilder
    private var logList: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleLogs.isEmpty {
                ContentUnavailableView(
                    search.isEmpty ? "No Recent Activity" : "No Matches",
                    systemImage: search.isEmpty ? "waveform.path.ecg" : "magnifyingglass",
                    description: Text(search.isEmpty ? "Capture, record or upload something and its activity appears here." : "Try a different filter.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleLogs) { entry in
                            LogRow(entry: entry)
                            Divider().opacity(0.5)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.035), in: shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .clipShape(shape)
    }

    private func reload() async {
        isLoading = logs.isEmpty
        logs = await AppLogger.shared.loadRecentLogs()
        isLoading = false
    }

    private func copyAll() {
        let text = visibleLogs.reversed().map { entry in
            "\(entry.timestamp.formatted(.iso8601)) [\(entry.level.rawValue)] \(entry.category): \(entry.message)"
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct LogRow: View {
    let entry: AppLogger.LogEntry

    private var color: Color {
        switch entry.level {
        case .debug: return .gray
        case .info: return .blue
        case .notice: return .teal
        case .error: return .orange
        case .fault: return .red
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(entry.level.rawValue.capitalized)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 1.5)
                .background(color.opacity(0.14), in: Capsule())
                .frame(width: 58, alignment: .leading)
            Text(entry.category)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
                .lineLimit(1)
            Text(entry.message)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

// MARK: - About Tab

struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(nsImage: AppBranding.logo(size: 96))
                .resizable()
                .interpolation(.high)
                .foregroundStyle(Color.accentColor)
                .frame(width: 96, height: 96)
                .accessibilityLabel("\(AppBranding.appName) logo")

            Text(AppBranding.appName)
                .font(.title)
                .bold()

            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("A fast, menu-bar-first macOS screenshot, recording, and sharing utility.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Developer contact card
            VStack(spacing: 0) {
                AboutContactRow(symbol: "person.crop.circle", title: "Developer", value: AppBranding.developerName)
                Divider().padding(.leading, 40)
                AboutContactRow(symbol: "envelope", title: "Email", value: AppBranding.supportEmail) {
                    AppBranding.contactSupport()
                }
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .frame(maxWidth: 340)

            Button {
                AppBranding.contactSupport()
            } label: {
                Label("Contact Support", systemImage: "questionmark.bubble")
            }
            .controlSize(.large)
            .help("Email \(AppBranding.developerName) at \(AppBranding.supportEmail)")

            Spacer()

            HStack(spacing: 16) {
                Link("Privacy Policy", destination: AppBranding.privacyPolicyURL)
                Text("·").foregroundStyle(.tertiary)
                Link("Terms of Use", destination: AppBranding.termsOfUseURL)
            }
            .font(.callout)

            Text("© \(Calendar.current.component(.year, from: Date())) \(AppBranding.developerName)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One line of the About contact card; tappable when it has an action
private struct AboutContactRow: View {
    let symbol: String
    let title: String
    let value: String
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            if let action {
                Button(value, action: action)
                    .buttonStyle(.link)
            } else {
                Text(value)
                    .textSelection(.enabled)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
