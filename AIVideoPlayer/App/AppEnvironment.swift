import Foundation
import Observation

/// 全局、应用级状态。刻意保持很小：目前只有 Tab 选择；
/// 登录 / 会话状态随 Phase 2 引入。
@MainActor
@Observable
final class AppEnvironment {
    var selectedTab: AppTab = .browser

    /// 待播放的媒体请求（由远程文件等入口发起，Player 消费后清空）。
    private(set) var pendingPlayback: MediaItem?

    /// 请求播放并切换到 Player Tab。
    func requestPlayback(of item: MediaItem) {
        pendingPlayback = item
        selectedTab = .player
    }

    /// Player 消费待播放请求（一次性）。
    func consumePendingPlayback() -> MediaItem? {
        guard let item = pendingPlayback else { return nil }
        pendingPlayback = nil
        return item
    }
}
