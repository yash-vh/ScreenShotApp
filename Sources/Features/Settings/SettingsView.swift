import SwiftUI

/// Modern macOS Settings window view with tabbed navigation
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
        case about = "About"

        public var id: String { rawValue }

        public var systemIcon: String {
            switch self {
            case .general: return "gearshape"
            case .capture: return "camera"
            case .recording: return "record.circle"
            case .shortcuts: return "command"
            case .storage: return "cloud"
            case .privacy: return "hand.raised"
            case .diagnostics: return "terminal"
            case .about: return "info.circle"
            }
        }
    }

    public init() {}

    public var body: some View {
        TabView(selection: $coordinator.settingsTab) {
            GeneralSettingsTab()
                .tabItem {
                    Label(Tab.general.rawValue, systemImage: Tab.general.systemIcon)
                }
                .tag(Tab.general)

            CaptureSettingsTab()
                .tabItem {
                    Label(Tab.capture.rawValue, systemImage: Tab.capture.systemIcon)
                }
                .tag(Tab.capture)

            RecordingSettingsTab()
                .tabItem {
                    Label(Tab.recording.rawValue, systemImage: Tab.recording.systemIcon)
                }
                .tag(Tab.recording)

            ShortcutsSettingsTab()
                .tabItem {
                    Label(Tab.shortcuts.rawValue, systemImage: Tab.shortcuts.systemIcon)
                }
                .tag(Tab.shortcuts)

            StorageSettingsTab()
                .tabItem {
                    Label(Tab.storage.rawValue, systemImage: Tab.storage.systemIcon)
                }
                .tag(Tab.storage)

            PrivacySettingsTab()
                .tabItem {
                    Label(Tab.privacy.rawValue, systemImage: Tab.privacy.systemIcon)
                }
                .tag(Tab.privacy)

            DiagnosticsTab()
                .tabItem {
                    Label(Tab.diagnostics.rawValue, systemImage: Tab.diagnostics.systemIcon)
                }
                .tag(Tab.diagnostics)

            AboutSettingsTab()
                .tabItem {
                    Label(Tab.about.rawValue, systemImage: Tab.about.systemIcon)
                }
                .tag(Tab.about)
        }
        .frame(minWidth: 720, minHeight: 520)
        .padding(20)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @EnvironmentObject var config: AppConfiguration

    var body: some View {
        Form {
            Section(header: Text("App Startup & Visibility").font(.headline)) {
                Toggle("Launch ScreenshotApp at system login", isOn: $config.launchAtLogin)
                Toggle("Show application icon in Dock", isOn: $config.showDockIcon)
                Text("When disabled, the app operates silently exclusively from the macOS menu bar.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Feedback & Alerts").font(.headline)) {
                Toggle("Play shutter sound on capture", isOn: $config.captureSettings.playCaptureSound)
            }
        }
        .formStyle(.grouped)
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
                    Picker("Save to:", selection: saveLocationBinding) {
                        ForEach(SaveLocation.allCases) { location in
                            Label(location.displayName, systemImage: location.systemImage).tag(location)
                        }
                    }

                    LabeledContent("Folder:") {
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
                Text("Save Location").font(.headline)
            } footer: {
                if config.captureSettings.saveToDisk {
                    Text("Screen recordings are saved to the same folder. The folder is created automatically.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("File Format & Naming").font(.headline)) {
                Picker("Format:", selection: $config.captureSettings.defaultFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                if config.captureSettings.defaultFormat == .jpeg {
                    LabeledContent("JPEG quality:") {
                        HStack {
                            Slider(value: $config.captureSettings.jpegQuality, in: 0.5...1.0, step: 0.05)
                            Text("\(Int(config.captureSettings.jpegQuality * 100))%")
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }

                TextField("File name prefix:", text: $config.captureSettings.fileNamePrefix, prompt: Text("Screenshot"))
                LabeledContent("Example:") {
                    Text(exampleFileName)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("After Capture").font(.headline)) {
                Toggle("Copy image to clipboard", isOn: $config.captureSettings.copyToClipboard)
                Toggle("Open in annotation editor", isOn: $config.captureSettings.openInEditor)
                Toggle("Recognize text automatically (OCR, on-device)", isOn: $config.captureSettings.runOcrAutomatically)
            }

            Section(header: Text("Selection").font(.headline)) {
                Toggle("Show magnifier loupe during region capture", isOn: $config.captureSettings.showMagnifier)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshFolderStatus)
        .onChange(of: config.captureSettings.saveLocation) { _ in refreshFolderStatus() }
        .onChange(of: config.captureSettings.customSaveDirectory) { _ in refreshFolderStatus() }
        .onChange(of: config.captureSettings.saveToDisk) { _ in refreshFolderStatus() }
    }

    /// Picking "Custom Folder…" without a folder yet opens the chooser straight away
    private var saveLocationBinding: Binding<SaveLocation> {
        Binding(
            get: { config.captureSettings.saveLocation },
            set: { location in
                if location == .custom, (config.captureSettings.customSaveDirectory ?? "").isEmpty {
                    chooseCustomFolder()
                } else {
                    config.captureSettings.saveLocation = location
                }
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
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = config.configuredSaveDirectory
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            config.captureSettings.customSaveDirectory = url.path
            config.captureSettings.saveLocation = .custom
        }
        refreshFolderStatus()
    }

    private func showInFinder() {
        let url = config.resolveLocalSaveDirectory()
        NSWorkspace.shared.activateFileViewerSelecting([url])
        refreshFolderStatus()
    }
}

// MARK: - Recording Tab

struct RecordingSettingsTab: View {
    @EnvironmentObject var config: AppConfiguration

    var body: some View {
        Form {
            Section(header: Text("Output").font(.headline)) {
                Picker("Save as:", selection: $config.recordingSettings.outputFormat) {
                    ForEach(RecordingOutputFormat.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)

                if config.recordingSettings.outputFormat == .mp4 {
                    Picker("Codec:", selection: $config.recordingSettings.codec) {
                        ForEach(RecordingCodec.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Frame rate:", selection: $config.recordingSettings.frameRate) {
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }
                } else {
                    Picker("GIF frame rate:", selection: $config.recordingSettings.gifFrameRate) {
                        Text("10 fps").tag(10)
                        Text("15 fps").tag(15)
                        Text("20 fps").tag(20)
                        Text("25 fps").tag(25)
                    }
                    Picker("GIF size:", selection: $config.recordingSettings.gifMaxPixelSize) {
                        Text("Small (480 px)").tag(480)
                        Text("Medium (800 px)").tag(800)
                        Text("Large (1280 px)").tag(1280)
                        Text("Original").tag(0)
                    }
                }
                LabeledContent("Saved to:") {
                    Text(config.captureSettings.saveToDisk
                         ? (config.configuredSaveDirectory.path as NSString).abbreviatingWithTildeInPath
                         : "Library only")
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if config.recordingSettings.outputFormat == .mp4 {
                Section(header: Text("Audio").font(.headline)) {
                    Toggle("Record microphone (voiceover)", isOn: $config.recordingSettings.recordMicrophone)
                    Toggle("Record system audio", isOn: $config.recordingSettings.recordSystemAudio)
                }
            }

            Section(header: Text("Pointer").font(.headline)) {
                Toggle("Show cursor", isOn: $config.recordingSettings.showCursor)
                if #available(macOS 15.0, *) {
                    Toggle("Highlight mouse clicks", isOn: $config.recordingSettings.showClicks)
                }
            }

            Section(header: Text("Safety").font(.headline)) {
                Picker("Stop when free disk space falls below:", selection: $config.recordingSettings.minimumFreeSpaceMB) {
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
            Section(header: Text("In-Place Capture & Actions").font(.headline)) {
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

            Section(header: Text("Global Screen Capture").font(.headline)) {
                ShortcutRecorderRow(
                    label: "Capture Selected Region",
                    icon: "crop",
                    binding: $config.captureSettings.shortcutRegion,
                    defaultBinding: ShortcutBinding(key: "4", modifiers: ["⇧", "⌘"])
                )

                ShortcutRecorderRow(
                    label: "Capture Full Screen",
                    icon: "macwindow",
                    binding: $config.captureSettings.shortcutFullScreen,
                    defaultBinding: ShortcutBinding(key: "3", modifiers: ["⇧", "⌘"])
                )

                ShortcutRecorderRow(
                    label: "Capture Window",
                    icon: "macwindow.on.rectangle",
                    binding: $config.captureSettings.shortcutWindow,
                    defaultBinding: ShortcutBinding(key: "5", modifiers: ["⇧", "⌘"])
                )

                ShortcutRecorderRow(
                    label: "Record Screen",
                    icon: "record.circle",
                    binding: $config.captureSettings.shortcutRecording,
                    defaultBinding: ShortcutBinding(key: "6", modifiers: ["⇧", "⌘"])
                )

                ShortcutRecorderRow(
                    label: "OCR Text from Screen",
                    icon: "text.viewfinder",
                    binding: $config.captureSettings.shortcutQuickOcr,
                    defaultBinding: ShortcutBinding(key: "7", modifiers: ["⇧", "⌘"])
                )

                VStack(alignment: .leading, spacing: 4) {
                    Label("⌥⌘3 / ⌥⌘4 / ⌥⌘5 / ⌥⌘6 / ⌥⌘7 always work as backups.", systemImage: "info.circle")
                    Text("macOS reserves ⇧⌘3, ⇧⌘4 and ⇧⌘5 for its own screenshot tool. To use them here, turn them off in System Settings › Keyboard › Keyboard Shortcuts › Screenshots.")
                        .foregroundColor(.secondary)
                    if !hotKeys.failedBindings.isEmpty {
                        Label("Unavailable (in use by another app): \(hotKeys.failedBindings.joined(separator: ", "))", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    }
                }
                .font(.caption)
            }

            Section(header: Text("User Custom Shortcuts").font(.headline)) {
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
        .onDisappear {
            stopRecording()
        }
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

                DispatchQueue.main.async {
                    self.binding = ShortcutBinding(key: key, modifiers: mods)
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
        "OCR Text from Screen"
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("Add New Shortcut")
                .font(.headline)
                .padding(.top, 8)

            Form {
                TextField("Shortcut Name:", text: $name, prompt: Text("e.g. Quick Copy / Cloud Upload"))

                Picker("Action:", selection: $selectedAction) {
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
    @State private var credentialStatus: String?
    @State private var imgbbAPIKey = ""
    @State private var imgbbKeySaved = false
    @State private var usage = StorageUsage(cacheBytes: 0, thumbnailBytes: 0, savedBytes: 0, databaseBytes: 0)

    var body: some View {
        Form {
            Section(header: Text("Storage Destination").font(.headline)) {
                Picker("Mode:", selection: $config.storageMode) {
                    ForEach(StorageMode.allCases, id: \.self) { mode in
                        HStack {
                            Image(systemName: mode.iconName)
                            Text(mode.title)
                        }.tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(config.storageMode.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if config.storageMode == .managedCloud {
                Section(header: Text("Free Share Link").font(.headline)) {
                    Picker("Service:", selection: $config.activeCloudProvider) {
                        Text(CloudProviderType.managedCloud.displayName).tag(CloudProviderType.managedCloud)
                        Text(CloudProviderType.imgbb.displayName).tag(CloudProviderType.imgbb)
                        Text(CloudProviderType.imgur.displayName).tag(CloudProviderType.imgur)
                    }

                    if config.activeCloudProvider == .imgbb {
                        HStack {
                            SecureField("ImgBB API Key:", text: $imgbbAPIKey, prompt: Text(imgbbKeySaved ? "Saved in Keychain" : "Paste your API key"))
                            Button("Save") { saveImgBBKey() }
                                .disabled(imgbbAPIKey.trimmingCharacters(in: .whitespaces).isEmpty)
                            if imgbbKeySaved {
                                Button("Remove") { removeImgBBKey() }
                            }
                        }
                        HStack(spacing: 4) {
                            Text(imgbbKeySaved ? "Key saved. Links point straight at the image." : "Free key, no account needed for viewers.")
                            Link("Get a key at api.imgbb.com", destination: URL(string: "https://api.imgbb.com/")!)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    } else if config.activeCloudProvider == .imgur {
                        TextField("Imgur Client-ID:", text: $config.imgurClientID, prompt: Text("from api.imgur.com/oauth2/addclient"))
                        Text("Imgur images are public and never expire. Imgur's API terms restrict commercial use.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        TextField("Service URL:", text: $config.shareServiceURL, prompt: Text("https://your-share-domain"))
                        Text("Links use 16-character random IDs and can be deleted at any time. Deploy the service from Services/share-worker.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if config.storageMode == .userOwned {
                Section(header: Text("My S3 / S3-Compatible Bucket").font(.headline)) {
                    TextField("Endpoint URL:", text: $config.s3Endpoint, prompt: Text("https://s3.us-east-1.amazonaws.com"))
                    TextField("Bucket Name:", text: $config.s3Bucket)
                    TextField("Region:", text: $config.s3Region)
                    TextField("Public Base URL (optional):", text: $config.s3PublicBaseURL, prompt: Text("https://cdn.example.com"))
                    TextField("Access Key ID:", text: $s3AccessKeyID)
                    SecureField("Secret Access Key:", text: $s3SecretAccessKey)
                    HStack {
                        Button("Save Keys to Keychain") { saveS3Keys() }
                            .disabled(s3AccessKeyID.isEmpty || s3SecretAccessKey.isEmpty)
                        Button("Remove Keys") { removeS3Keys() }
                        if let credentialStatus {
                            Text(credentialStatus).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Text("Without a public base URL, links are presigned and expire after at most 7 days.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if config.storageMode != .localOnly {
                Section(header: Text("Upload Behavior").font(.headline)) {
                    Picker("Link expires after:", selection: $config.uploadExpiry) {
                        ForEach(UploadExpiry.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Ask before uploading", isOn: $config.askBeforeUploading)
                }
            }

            Section(header: Text("Local Storage Maintenance").font(.headline)) {
                StorageMeter(usage: usage, quotaBytes: Int64(config.cacheQuotaMB) * 1_048_576)
                Picker("Cache limit:", selection: $config.cacheQuotaMB) {
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
            imgbbKeySaved = ((try? KeychainStore.shared.value(for: KeychainStore.Account.imgbbAPIKey)) ?? nil)?.isEmpty == false
        }
        .onChange(of: config.cacheQuotaMB) { _ in
            history.enforceCacheQuota()
            usage = history.storageUsage()
        }
    }

    private func saveS3Keys() {
        do {
            try KeychainStore.shared.set(s3AccessKeyID.trimmingCharacters(in: .whitespaces), for: KeychainStore.Account.s3AccessKeyID)
            try KeychainStore.shared.set(s3SecretAccessKey, for: KeychainStore.Account.s3SecretAccessKey)
            s3SecretAccessKey = ""
            credentialStatus = "Saved to Keychain"
        } catch {
            credentialStatus = error.localizedDescription
        }
    }

    private func saveImgBBKey() {
        let key = imgbbAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (try? KeychainStore.shared.set(key, for: KeychainStore.Account.imgbbAPIKey)) != nil else { return }
        imgbbAPIKey = ""
        imgbbKeySaved = true
    }

    private func removeImgBBKey() {
        KeychainStore.shared.remove(KeychainStore.Account.imgbbAPIKey)
        imgbbKeySaved = false
    }

    private func removeS3Keys() {
        KeychainStore.shared.remove(KeychainStore.Account.s3AccessKeyID)
        KeychainStore.shared.remove(KeychainStore.Account.s3SecretAccessKey)
        s3AccessKeyID = ""
        s3SecretAccessKey = ""
        credentialStatus = "Keys removed"
    }
}

// MARK: - Privacy Tab

struct PrivacySettingsTab: View {
    @EnvironmentObject var config: AppConfiguration
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject var permissionManager = PermissionManager.shared

    var body: some View {
        Form {
            Section(header: Text("System Permissions").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: permissionManager.isAuthorized ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(permissionManager.isAuthorized ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Screen Recording Permission")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(permissionManager.isAuthorized ? "Authorized" : "Permission Required or Restart Needed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if !permissionManager.isAuthorized {
                            Button("Open Settings") {
                                coordinator.openPrivacySettings()
                            }
                            Button("Relaunch App") {
                                permissionManager.relaunchApp()
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Reset Permission") {
                                permissionManager.resetScreenCapturePermission()
                            }
                        } else {
                            Text("Enabled")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }

                    if !permissionManager.isAuthorized {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Already enabled in System Settings?")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            Text("macOS requires ScreenshotApp to restart after granting Screen Recording access. If you already turned on the toggle in System Settings, click \"Relaunch App\" above to apply permissions immediately.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }

            Section(header: Text("Redaction & Security").font(.headline)) {
                Picker("Default Redaction Style:", selection: $config.captureSettings.defaultRedactionStyle) {
                    ForEach(DefaultRedactionStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }

                Text("Important: Redactions (blur and pixelation) are irreversibly rasterized into image pixels upon export. Hidden layers or original sensitive pixels are never retained in shared assets.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Diagnostics Tab

struct DiagnosticsTab: View {
    @State private var logs: [AppLogger.LogEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diagnostic Log Viewer")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    logs = AppLogger.shared.getRecentLogs()
                }
                Button("Clear") {
                    AppLogger.shared.clearLogs()
                    logs = []
                }
            }

            Text("Sensitive credentials, tokens, and home paths are automatically redacted.")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(logs) { entry in
                        HStack(alignment: .top) {
                            Text(entry.level.rawValue)
                                .font(.system(.caption, design: .monospaced))
                                .bold()
                                .foregroundColor(color(for: entry.level))
                                .frame(width: 55, alignment: .leading)

                            Text(entry.category)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .leading)

                            Text(entry.message)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(2)
                            Spacer()
                        }
                        Divider()
                    }
                }
                .padding(8)
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.textBackgroundColor)))
        }
        .onAppear {
            logs = AppLogger.shared.getRecentLogs()
        }
    }

    private func color(for level: AppLogger.LogEntry.Level) -> Color {
        switch level {
        case .debug: return .gray
        case .info: return .blue
        case .notice: return .cyan
        case .error: return .orange
        case .fault: return .red
        }
    }
}

// MARK: - About Tab

struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("ScreenshotApp")
                .font(.title)
                .bold()

            Text("Version 1.0.0 (Build 1)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("A fast, menu-bar-first macOS screenshot, recording, and sharing utility.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Divider().frame(width: 200)

            HStack(spacing: 20) {
                Link("Documentation", destination: URL(string: "https://github.com/screenshotapp/docs")!)
                Link("Privacy Policy", destination: URL(string: "https://screenshotapp.local/privacy")!)
            }
            .font(.caption)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
