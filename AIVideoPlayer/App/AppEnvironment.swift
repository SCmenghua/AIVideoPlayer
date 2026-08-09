import Foundation
import Observation

/// 全局、应用级状态。刻意保持很小：目前只有 Tab 选择；
/// Phase 5 起持有 AI 字幕设置与字幕管线（全应用共享，浏览器状态卡与播放器共用）。
@MainActor
@Observable
final class AppEnvironment {
    var selectedTab: AppTab = .browser

    /// 超前识别设置（设置页与管线共享，UserDefaults 持久化）。
    let subtitleSettings: SubtitleSettings
    /// AI 字幕子系统（真实 WhisperKit 管线）。
    let subtitlePipeline: SubtitlePipeline
    /// 字幕叠加层显示设置（播放器与设置页共享，UserDefaults 持久化）。
    let subtitleDisplaySettings: SubtitleDisplaySettings

    /// 待播放的媒体请求（由远程文件等入口发起，Player 消费后清空）。
    private(set) var pendingPlayback: MediaItem?

    init() {
        let settings = SubtitleSettings()
        subtitleSettings = settings
        subtitlePipeline = SubtitlePipeline(settings: settings)
        subtitleDisplaySettings = SubtitleDisplaySettings()
    }

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
