import Foundation
import OSLog

/// 统一日志门面，避免到处初始化 Logger。
enum Log {
    static let app = Logger(subsystem: "com.aivideoplayer.app", category: "app")
}
