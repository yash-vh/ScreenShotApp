import AppKit
import SwiftUI

/// History browser window: searchable thumbnail grid grouped by day, with type/date filters and storage tools.
@MainActor
public final class LibraryWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: LibraryWindowController?

    public static func present() {
        if shared == nil {
            let host = NSHostingController(rootView: LibraryView(store: .shared))
            let window = NSWindow(contentViewController: host)
            window.title = "Library"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.setContentSize(NSSize(width: 920, height: 620))
            window.contentMinSize = NSSize(width: 560, height: 380)
            window.setFrameAutosaveName("LibraryWindow")
            window.isReleasedWhenClosed = false
            window.center()
            let controller = LibraryWindowController(window: window)
            window.delegate = controller
            shared = controller
        }
        HistoryStore.shared.refreshAvailability()
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct LibraryView: View {
    @ObservedObject var store: HistoryStore
    @ObservedObject private var uploads = UploadService.shared
    @State private var query = HistoryQuery()
    @State private var selection = Set<UUID>()
    @State private var usage = StorageUsage(cacheBytes: 0, thumbnailBytes: 0, savedBytes: 0, databaseBytes: 0)
    @State private var pendingDeletion: Set<UUID> = []

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 16)]

    var body: some View {
        let results = store.search(query)
        VStack(spacing: 0) {
            filterBar
            Divider()
            if results.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                        ForEach(HistoryQuery.sections(for: results), id: \.title) { section in
                            Section {
                                ForEach(section.assets) { asset in
                                    LibraryTile(asset: asset, store: store, isSelected: selection.contains(asset.id))
                                        .onTapGesture(count: 2) { open(asset) }
                                        .onTapGesture { toggleSelection(asset.id) }
                                        .contextMenu { contextMenu(for: asset) }
                                        .onDrag { NSItemProvider(contentsOf: asset.originalFileURL) ?? NSItemProvider() }
                                }
                            } header: {
                                Text(section.title)
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                                    .background(.bar)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            Divider()
            storageBar
        }
        .frame(minWidth: 560, minHeight: 380)
        .onAppear { usage = store.storageUsage() }
        .onChange(of: store.assets) { _ in
            usage = store.storageUsage()
            selection.formIntersection(Set(store.assets.map(\.id)))
        }
        .confirmationDialog(
            pendingDeletion.count == 1 ? "Delete this capture?" : "Delete \(pendingDeletion.count) captures?",
            isPresented: Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } })
        ) {
            Button("Remove from Library") { store.remove(ids: pendingDeletion); pendingDeletion = [] }
            Button("Remove and Move Files to Trash", role: .destructive) { store.remove(ids: pendingDeletion, trashUserFiles: true); pendingDeletion = [] }
            Button("Cancel", role: .cancel) { pendingDeletion = [] }
        } message: {
            Text("Cached captures are always deleted. Files in your own folders are kept unless you move them to the Trash. Uploaded links stay online until you delete the upload.")
        }
    }

    // MARK: - Bars

    private var filterBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search titles, tags and text inside screenshots…", text: $query.text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
            Picker("Type", selection: $query.media) {
                ForEach(HistoryQuery.MediaFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(width: 130)
            Picker("Date", selection: $query.date) {
                ForEach(HistoryQuery.DateFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(width: 130)
            if !selection.isEmpty {
                Button(role: .destructive) { pendingDeletion = selection } label: {
                    Label("Delete \(selection.count)", systemImage: "trash")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .padding(.top, 22)
    }

    private var storageBar: some View {
        HStack(spacing: 12) {
            StorageMeter(usage: usage, quotaBytes: Int64(AppConfiguration.shared.cacheQuotaMB) * 1_048_576)
            Spacer()
            let missing = store.assets.filter { !$0.isAvailableLocally }.count
            if missing > 0 {
                Button("Remove \(missing) Missing") { store.pruneMissing() }
                    .help("Delete history records whose files were moved or deleted")
            }
            Menu("Clean Up…") {
                Button("Cached captures older than 7 days") { store.cleanUpCache(olderThanDays: 7) }
                Button("Cached captures older than 30 days") { store.cleanUpCache(olderThanDays: 30) }
                Button("All cached captures and thumbnails") { store.cleanUpCache() }
            }
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: store.assets.isEmpty ? "photo.on.rectangle.angled" : "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(store.assets.isEmpty ? "No captures yet" : "No matches")
                .font(.title3.weight(.semibold))
            Text(store.assets.isEmpty ? "Screenshots you take appear here, searchable by the text inside them." : "Try another search term or filter.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    @ViewBuilder
    private func contextMenu(for asset: ScreenshotAsset) -> some View {
        if asset.isAvailableLocally {
            Button("Open") { open(asset) }
            if asset.mediaType == .image {
                Button("Copy Image") { copy(asset) }
            } else {
                Button("Copy File") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([asset.originalFileURL as NSURL])
                }
            }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([asset.originalFileURL]) }
            if asset.mediaType == .image {
                Divider()
                Button("Upload & Copy Link") { UploadService.shared.requestUpload(assetId: asset.id) }
            }
        } else {
            Button("Locate File…") { locate(asset) }
        }
        let live = asset.uploadRecords.filter { $0.status == .completed && $0.shareURL != nil }
        if let latest = live.last, let url = latest.shareURL {
            Button("Copy Share Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
            Button("Open Share Link") { NSWorkspace.shared.open(url) }
            if latest.capabilities.supportsDelete, latest.providerType.isImplemented {
                Button("Delete Upload") { deleteUpload(asset: asset, record: latest) }
            }
        }
        if asset.uploadRecords.contains(where: { $0.status == .pending }) {
            Button("Retry Queued Upload") { Task { await UploadService.shared.retryPendingUploads() } }
        }
        Divider()
        Button("Delete…", role: .destructive) { pendingDeletion = [asset.id] }
    }

    private func toggleSelection(_ id: UUID) {
        if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = selection == [id] ? [] : [id]
        }
    }

    private func open(_ asset: ScreenshotAsset) {
        guard asset.isAvailableLocally else { return locate(asset) }
        NSWorkspace.shared.open(asset.originalFileURL)
    }

    private func copy(_ asset: ScreenshotAsset) {
        guard let image = NSImage(contentsOf: asset.originalFileURL) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        CaptureHUD.shared.show(title: "Copied to Clipboard", symbol: "doc.on.clipboard.fill", duration: 1.4)
    }

    private func locate(_ asset: ScreenshotAsset) {
        let panel = NSOpenPanel()
        panel.message = "Locate \(asset.originalFileURL.lastPathComponent)"
        panel.allowedContentTypes = [.image, .movie]
        panel.directoryURL = asset.originalFileURL.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.relocate(id: asset.id, to: url)
    }

    private func deleteUpload(asset: ScreenshotAsset, record: UploadRecord) {
        Task {
            do {
                try await UploadService.shared.deleteUpload(assetId: asset.id, recordId: record.id)
                CaptureHUD.shared.show(title: "Upload deleted", detail: "The link no longer works.", symbol: "trash.fill")
            } catch {
                CaptureHUD.shared.show(title: "Couldn't delete upload", detail: error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            }
        }
    }
}

private struct LibraryTile: View {
    let asset: ScreenshotAsset
    let store: HistoryStore
    let isSelected: Bool
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12))
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                } else {
                    Image(systemName: asset.isAvailableLocally ? asset.mediaType.systemIconName : "questionmark.folder")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 120)
            .overlay(alignment: .topTrailing) { badges.padding(6) }
            .overlay(alignment: .bottomLeading) {
                if let duration = asset.durationSeconds {
                    Label(RecordingCoordinator.format(duration), systemImage: asset.mediaType == .gif ? "play.square.stack" : "play.fill")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                        .padding(8)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5))
            .opacity(asset.isAvailableLocally ? 1 : 0.55)

            Text(asset.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Text("\(asset.dimensionsString) · \(asset.formattedFileSize) · \(asset.createdAt.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .help(asset.ocrText.map { String($0.prefix(300)) } ?? asset.originalFileURL.lastPathComponent)
        .task(id: asset.id) { thumbnail = await store.thumbnail(for: asset) }
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: 4) {
            if !asset.isAvailableLocally {
                badge("exclamationmark.triangle.fill", .orange, "File missing")
            }
            if asset.uploadRecords.contains(where: { $0.status == .pending }) {
                badge("icloud.slash", .yellow, "Upload queued")
            } else if asset.uploadRecords.contains(where: { $0.status == .completed }) {
                badge("icloud.fill", .blue, "Uploaded")
            }
        }
    }

    private func badge(_ symbol: String, _ color: Color, _ help: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(5)
            .background(Circle().fill(color))
            .help(help)
    }
}

/// Stacked bar showing cache / thumbnails / saved files against the cache quota
struct StorageMeter: View {
    let usage: StorageUsage
    let quotaBytes: Int64

    var body: some View {
        let format = { (bytes: Int64) in ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
        let fraction = quotaBytes > 0 ? min(1, Double(usage.reclaimableBytes) / Double(quotaBytes)) : 0
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: fraction)
                .tint(fraction > 0.9 ? .orange : .accentColor)
                .frame(width: 220)
            Text("Cache \(format(usage.cacheBytes)) · Thumbnails \(format(usage.thumbnailBytes)) · Saved \(format(usage.savedBytes))\(quotaBytes > 0 ? " · Limit \(format(quotaBytes))" : "")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
