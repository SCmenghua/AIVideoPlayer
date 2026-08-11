import Foundation
import OSLog

/// 应用日志服务（Phase 8.13）：
/// - 支持多级日志（debug, info, warning, error）
/// - 持久化存储到文件系统
/// - 线程安全的写入
/// - 支持开关控制
/// - 非正常退出时数据安全
@Observable
public final class AppLogger: Sendable {
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

    private let logger = Logger(subsystem: "com.aiVideoPlayer", category: "AppLogger")
    private let fileURL: URL
    private let fileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.aiVideoPlayer.logger", qos: .utility)
    private let userDefaultsKey = "AppLogger.isEnabled"

    // MARK: - Init

    public init() {
        // 从 UserDefaults 读取开关状态，默认开启
        self.isEnabled = UserDefaults.standard.object(forKey: userDefaultsKey) as? Bool ?? true

        // 日志文件路径：Application Support/Logs/app.log
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let logsDir = base.appendingPathComponent("Logs", isDirectory: true)

        // 确保目录存在
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        self.fileURL = logsDir.appendingPathComponent("app.log")

        // 打开文件句柄（追加模式）
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        self.fileHandle = try? FileHandle(forWritingTo: fileURL)
        self.fileHandle?.seekToEndOfFile()

        // 统计现有日志条目数
        self.totalEntries = countExistingEntries()

        log(.info, category: "AppLogger", "日志服务启动，已有 \(totalEntries) 条日志")
    }

    deinit {
        try? fileHandle?.close()
    }

    // MARK: - Public API

    public func log(_ level: Level, category: String, _ message: String) {
        guard isEnabled else { return }

        let entry = Entry(level: level, category: category, message: message)

        // 写入 OSLog（用于 Xcode 调试）
        let osLogLevel: OSLogType = switch level {
        case .debug: .debug
        case .info: .info
        case .warning: .default
        case .error: .error
        }
        logger.log(level: osLogLevel, "[\(category)] \(message)")

        // 异步写入文件
        queue.async { [weak self] in
            self?.writeToFile(entry)
        }

        // 更新计数
        Task { @MainActor in
            self.totalEntries += 1
        }
    }

    public func setEnabled(_ enabled: Bool) {
        Task { @MainActor in
            self.isEnabled = enabled
            UserDefaults.standard.set(enabled, forKey: userDefaultsKey)
            log(.info, category: "AppLogger", "日志功能\(enabled ? "开启" : "关闭")")
        }
    }

    public func clear() {
        queue.async { [weak self] in
            guard let self else { return }

            // 关闭当前文件句柄
            try? self.fileHandle?.close()

            // 删除文件
            try? FileManager.default.removeItem(at: self.fileURL)

            // 重新创建空文件
            FileManager.default.createFile(atPath: self.fileURL.path, contents: nil)

            Task { @MainActor in
                self.totalEntries = 0
                self.log(.info, category: "AppLogger", "日志已清空")
            }
        }
    }

    public func exportLogs() -> URL {
        fileURL
    }

    // MARK: - Private

    private func writeToFile(_ entry: Entry) {
        guard let fileHandle else { return }

        // JSON Lines 格式：每行一个 JSON 对象
        if let data = try? JSONEncoder().encode(entry),
           var line = String(data: data, encoding: .utf8) {
            line += "\n"
            if let lineData = line.data(using: .utf8) {
                try? fileHandle.write(contentsOf: lineData)

                // 立即同步到磁盘（确保非正常退出时数据安全）
                fileHandle.synchronizeFile()
            }
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
