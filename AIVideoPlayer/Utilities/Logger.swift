import Foundation
import OSLog

/// 统一日志门面，避免到处初始化 Logger。
/// Phase 8.13：集成 AppLogger，支持持久化、导出与清空。
@MainActor
enum Log {
    static let app = AppLoggerWrapper(subsystem: "com.aivideoplayer.app", category: "app")

    /// 由 AppEnvironment 初始化时设置，用于持久化日志。
    nonisolated(unsafe) static var appLogger: AppLogger?
}

/// OSLog + AppLogger 双写包装器。
struct AppLoggerWrapper {
    private let osLogger: Logger
    private let category: String

    init(subsystem: String, category: String) {
        self.osLogger = Logger(subsystem: subsystem, category: category)
        self.category = category
    }

    func debug(_ message: String) {
        osLogger.debug("\(message)")
        if let logger = Log.appLogger {
            Task { @MainActor in
                logger.log(.debug, category: category, message)
            }
        }
    }

    func info(_ message: String) {
        osLogger.info("\(message)")
        if let logger = Log.appLogger {
            Task { @MainActor in
                logger.log(.info, category: category, message)
            }
        }
    }

    func warning(_ message: String) {
        osLogger.warning("\(message)")
        if let logger = Log.appLogger {
            Task { @MainActor in
                logger.log(.warning, category: category, message)
            }
        }
    }

    func error(_ message: String) {
        osLogger.error("\(message)")
        if let logger = Log.appLogger {
            Task { @MainActor in
                logger.log(.error, category: category, message)
            }
        }
    }
}
