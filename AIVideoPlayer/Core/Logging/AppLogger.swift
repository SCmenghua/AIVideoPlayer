import Foundation
import OSLog

/// 应用日志服务（Phase 8.13 引入，Phase 8.18 重构）：
/// - 支持多级日志（debug / info / warning / error）；
/// - 内存环形缓冲（最多 500 条），供「诊断与日志」页面实时展示；
/// - 异步后台落盘，不做逐行 fsync（避免高频日志造成磁盘争抢）；
/// - 支持开关、导出与清空。
@MainActor
@Observable
public final class AppLogger {
    public enum Level: String, Codable, Sendable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
    }

    public struct Entry: Codable, Identifiable, Sendable {
        public let id: UUID
        public let timestamp: Date
        public let level: Level
        public let category: String
        public let message: String

        public init(id: UUID = UUID(), timestamp: Date = Date(), level: Level, category: String, message: String) {
            self.id = id
            self.timestamp = timestamp
            self.level = level
            self.category = category
            self.message = message
        }
    }

    // MARK: - State

    public private(set) var isEnabled: Bool
    public private(set) var totalEntries: Int = 0
    /// 内存中的最近日志（最新追加在末尾），UI 展示用。
    public private(set) var entries: [Entry] = []

    private let logger = Logger(subsystem: "com.aiVideoPlayer", category: "AppLogger")
    private let fileURL: URL
    private let userDefaultsKey = "AppLogger.isEnabled"
    private static let maxInMemoryEntries = 500

    // MARK: - Init

    public init() {
        self.isEnabled = UserDefaults.standard.object(forKey: userDefaultsKey) as? Bool ?? true

        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let logsDir = base.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        self.fileURL = logsDir.appendingPathComponent("app.log")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        self.totalEntries = countExistingEntries()
        log(.info, category: "App", "日志服务启动，已有 \(totalEntries) 条日志")
    }

    // MARK: - Public API

    public func log(_ level: Level, category: String, _ message: String) {
        guard isEnabled else { return }

        let entry = Entry(level: level, category: category, message: message)

        // OSLog（Xcode / Console 调试可见）。
        let osLogLevel: OSLogType = switch level {
        case .debug: .debug
        case .info: .info
        case .warning: .default
        case .error: .error
        }
        logger.log(level: osLogLevel, "[\(category)] \(message)")

        // 内存环形缓冲。
        entries.append(entry)
        if entries.count > Self.maxInMemoryEntries {
            entries.removeFirst(entries.count - Self.maxInMemoryEntries)
        }
        totalEntries += 1

        // 异步落盘（后台，不阻塞主线程；不做逐行 fsync，依赖系统刷盘）。
        let url = fileURL
        Task.detached(priority: .utility) {
            Self.appendToFile(entry, at: url)
        }
    }

    public func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: userDefaultsKey)
        log(.info, category: "App", "日志功能\(enabled ? "开启" : "关闭")")
    }

    public func clear() {
        entries.removeAll(keepingCapacity: true)
        totalEntries = 0
        let url = fileURL
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: url)
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
    }

    public func exportLogs() -> URL {
        fileURL
    }

    // MARK: - Private

    /// 后台写入一行 JSON Lines 日志；每次打开文件句柄写入后立即关闭，
    /// 避免跨线程共享 FileHandle，也不需要逐行 fsync。
    nonisolated private static func appendToFile(_ entry: Entry, at url: URL) {
        guard let data = try? JSONEncoder().encode(entry),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        guard let lineData = line.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: lineData)
        } else {
            // 文件尚未存在时先创建再写入。
            FileManager.default.createFile(atPath: url.path, contents: nil)
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: lineData)
        }
    }

    private func countExistingEntries() -> Int {
        guard let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8) else {
            return 0
        }
        return content.components(separatedBy: "\n").filter { !$0.isEmpty }.count
    }
}