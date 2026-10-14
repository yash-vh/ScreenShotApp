import SwiftUI

/// Modern macOS Settings window view with tabbed navigation
public struct SettingsView: View {
    @EnvironmentObject var config: AppConfiguration
    @EnvironmentObject var coordinator: AppCoordinator

    public enum Tab: String, CaseIterable, Identifiable {
        case general = "General"
        case capture = "Capture"
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
            case .shortcuts: return "command"
            case .storage: return "cloud"
            case .privacy: return "hand.raised"
            case .diagnostics: return "terminal"
            case .about: return "info.circle"
            }
        }
    }

    @State private var selectedTab: Tab = .general

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
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
        .frame(minWidth: 640, minHeight: 460)
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

    var body: some View {
        Form {
            Section(header: Text("Export Format").font(.headline)) {
                Picker("Format:", selection: $config.captureSettings.defaultFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                if config.captureSettings.defaultFormat == .jpeg {
                    HStack {
                        Text("JPEG Quality:")
                        Slider(value: $config.captureSettings.jpegQuality, in: 0.5...1.0, step: 0.05)
                        Text("\(Int(config.captureSettings.jpegQuality * 100))%")
                            .frame(width: 40)
                    }
                }
            }

            Section(header: Text("Post-Capture Behavior").font(.headline)) {
                Toggle("Copy image to clipboard", isOn: $config.captureSettings.copyToClipboard)
                Toggle("Open in annotation editor", isOn: $config.captureSettings.openInEditor)
                Toggle("Save automatically to disk", isOn: $config.captureSettings.saveToDisk)
                Toggle("Show magnifier loupe during region capture", isOn: $config.captureSettings.showMagnifier)
                Toggle("Automatically recognize text (OCR)", isOn: $config.captureSettings.runOcrAutomatically)
            }

            Section(header: Text("Save Destination").font(.headline)) {
                HStack {
                    Text("Directory:")
                    Text(config.resolveLocalSaveDirectory().path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose...") {
                        selectFolder()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            config.captureSettings.customSaveDirectory = url.path
        }
    }
}

// MARK: - Shortcuts Tab

struct ShortcutsSettingsTab: View {
    @EnvironmentObject var config: AppConfiguration

    var body: some View {
        Form {
            Section(header: Text("Global Shortcuts").font(.headline)) {
                ShortcutRow(label: "Capture Selected Region", binding: config.captureSettings.shortcutRegion)
                ShortcutRow(label: "Capture Full Screen", binding: config.captureSettings.shortcutFullScreen)
                ShortcutRow(label: "Capture Window", binding: config.captureSettings.shortcutWindow)
                ShortcutRow(label: "Record Screen", binding: config.captureSettings.shortcutRecording)
                ShortcutRow(label: "OCR Text from Screen", binding: config.captureSettings.shortcutQuickOcr)
            }
        }
        .formStyle(.grouped)
    }
}

struct ShortcutRow: View {
    let label: String
    let binding: ShortcutBinding

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(binding.displayString)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)))
        }
    }
}

// MARK: - Storage & Cloud Tab

struct StorageSettingsTab: View {
    @EnvironmentObject var config: AppConfiguration

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

            if config.storageMode == .userOwned {
                Section(header: Text("My Storage Provider").font(.headline)) {
                    Picker("Provider:", selection: $config.activeCloudProvider) {
                        ForEach(CloudProviderType.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }

                    if config.activeCloudProvider == .s3Compatible {
                        TextField("Endpoint URL (e.g. https://s3.amazonaws.com):", text: $config.s3Endpoint)
                        TextField("Bucket Name:", text: $config.s3Bucket)
                        TextField("Region:", text: $config.s3Region)
                    }
                }
            }

            Section(header: Text("Local Storage Maintenance").font(.headline)) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Local Cache & Files")
                        Text("Manage temporary export caches and disk space.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Clean Up Cache") {
                        // Handled in local storage coordinator
                    }
                }
            }
        }
        .formStyle(.grouped)
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
