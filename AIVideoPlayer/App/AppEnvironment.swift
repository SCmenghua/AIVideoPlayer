import Foundation
import Observation

/// 全局、应用级状态。刻意保持很小：目前只有 Tab 选择；
/// 登录 / 会话状态随 Phase 2 引入。
@MainActor
@Observable
final class AppEnvironment {
    var selectedTab: AppTab = .browser
}
