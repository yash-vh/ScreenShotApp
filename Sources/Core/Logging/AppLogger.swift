import Foundation
import os
import OSLog

/// Unified logging facility for ScreenMint.
/// Wraps `os.Logger` with domain categories, sensitive data redaction, and in-memory log auditing.
public final class AppLogger: @unchecked Sendable {
    public static let shared = AppLogger()

    private let subsystem = "com.screenmint.mac"

    // Unified OS Loggers
    public let app: Logger
    public let capture: Logger
    public let editor: Logger
    public let storage: Logger
    public let recognition: Logger
    public let recording: Logger
    public let sharing: Logger

    // In-memory diagnostic ring buffer
    public struct LogEntry: Identifiable, Sendable {
        public let id = UUID()
        public let timestamp: Date
        public let category: String
        public let level: Level
        public let message: String

        public enum Level: String, Sendable {
            case debug = "DEBUG"
            case info = "INFO"
            case notice = "NOTICE"
            case error = "ERROR"
            case fault = "FAULT"
        }
    }

    private let lock = NSLock()
    private var inMemoryLogs: [LogEntry] = []
    private let maxInMemoryLogs = 200

    private init() {
        self.app = Logger(subsystem: subsystem, category: "App")
        self.capture = Logger(subsystem: subsystem, category: "Capture")
        self.editor = Logger(subsystem: subsystem, category: "Editor")
        self.storage = Logger(subsystem: subsystem, category: "Storage")
        self.recognition = Logger(subsystem: subsystem, category: "Recognition")
        self.recording = Logger(subsystem: subsystem, category: "Recording")
        self.sharing = Logger(subsystem: subsystem, category: "Sharing")
    }

    // MARK: - Redaction Utilities

    /// Redacts sensitive information such as access keys, tokens, or personal paths
    public static func redact(_ string: String) -> String {
        var result = string

        // Redact standard API keys / Bearer tokens
        let bearerRegex = try? NSRegularExpression(pattern: "(Bearer\\s+)[a-zA-Z0-9_\\-\\.]+", options: [.caseInsensitive])
        if let regex = bearerRegex {
            result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "$1[REDACTED]")
        }

        // Redact AWS secret access keys / credentials (format: secretKey=... or akid)
        let keyRegex = try? NSRegularExpression(pattern: "(key|secret|token|password)=([a-zA-Z0-9_\\-\\.\\/\\+]+)", options: [.caseInsensitive])
        if let regex = keyRegex {
            result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "$1=[REDACTED]")
        }

        // Redact user's home folder path
        let homeDir = NSHomeDirectory()
        if !homeDir.isEmpty && result.contains(homeDir) {
            result = result.replacingOccurrences(of: homeDir, with: "~")
        }

        return result
    }

    // MARK: - In-Memory Logging & Querying

    public func log(category: String, level: LogEntry.Level, message: String) {
        let safeMessage = Self.redact(message)
        let entry = LogEntry(timestamp: Date(), category: category, level: level, message: safeMessage)

        lock.lock()
        inMemoryLogs.append(entry)
        if inMemoryLogs.count > maxInMemoryLogs {
            inMemoryLogs.removeFirst(inMemoryLogs.count - maxInMemoryLogs)
        }
        lock.unlock()

        let osLog = Logger(subsystem: subsystem, category: category)
        switch level {
        case .debug:
            osLog.debug("\(safeMessage, privacy: .public)")
        case .info:
            osLog.info("\(safeMessage, privacy: .public)")
        case .notice:
            osLog.notice("\(safeMessage, privacy: .public)")
        case .error:
            osLog.error("\(safeMessage, privacy: .public)")
        case .fault:
            osLog.fault("\(safeMessage, privacy: .public)")
        }
    }

    public func getRecentLogs() -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return inMemoryLogs
    }

    public func clearLogs() {
        lock.lock()
        defer { lock.unlock() }
        inMemoryLogs.removeAll()
        clearedAt = Date()
    }

    /// Entries before this are hidden from `loadRecentLogs` (the system log itself can't be erased)
    private var clearedAt: Date?

    /// This process's ScreenMint entries from the unified system log, oldest first, redacted.
    /// Covers every `Logger` category (app, capture, sharing, …), not just the in-memory buffer.
    public func loadRecentLogs(within interval: TimeInterval = 3600, limit: Int = 500) async -> [LogEntry] {
        let since = max(Date().addingTimeInterval(-interval), lock.withLock { clearedAt } ?? .distantPast)
        let subsystem = self.subsystem
        let systemLogs = await Task.detached(priority: .userInitiated) { () -> [LogEntry] in
            guard let store = try? OSLogStore(scope: .currentProcessIdentifier),
                  let entries = try? store.getEntries(
                      at: store.position(date: since),
                      matching: NSPredicate(format: "subsystem == %@", subsystem)
                  ) else { return [] }
            var result: [LogEntry] = []
            for case let entry as OSLogEntryLog in entries where entry.date >= since {
                result.append(LogEntry(timestamp: entry.date, category: entry.category, level: LogEntry.Level(entry.level), message: Self.redact(entry.composedMessage)))
            }
            return result
        }.value

        let memoryLogs = getRecentLogs().filter { $0.timestamp >= since }
        var combined = systemLogs
        for mem in memoryLogs {
            if !combined.contains(where: { $0.message == mem.message }) {
                combined.append(mem)
            }
        }
        combined.sort { $0.timestamp < $1.timestamp }
        return Array(combined.suffix(limit))
    }
}

private extension AppLogger.LogEntry.Level {
    init(_ level: OSLogEntryLog.Level) {
        switch level {
        case .debug: self = .debug
        case .notice: self = .notice
        case .error: self = .error
        case .fault: self = .fault
        default: self = .info
        }
    }
}
