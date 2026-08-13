import Foundation
import Observation

/// 全局、应用级状态。刻意保持很小：目前只有 Tab 选择；
/// Phase 5 起持有 AI 字幕记录与字幕管线（全应用共享，浏览器状态卡与播放器共用）。
@MainActor
@Observable
final class AppEnvironment {
    var selectedTab: AppTab = .browser

    /// AI 字幕记录（播放器 Overlay 与设置页「字幕记录」共享，有界保留最近条目）。
    let subtitleTranscript: SubtitleTranscriptStore
    /// 翻译设置（设置页与字幕管线共享，UserDefaults 持久化；API Key 走 Keychain）。
    let translationSettings: TranslationSettings
    /// AI 字幕子系统（真实 WhisperKit 管线）。
    let subtitlePipeline: SubtitlePipeline
    /// 本地大模型下载管理（设置页使用）。
    let localModelDownloadManager: LocalModelDownloadManager
    /// 翻译服务设置 ViewModel（设置页「翻译引擎」卡片直接使用，Phase 9.1 修复卡片不显示）。
    let translationSettingsViewModel: TranslationSettingsViewModel
    /// 字幕叠加层显示设置（播放器与设置页共享，UserDefaults 持久化）。
    let subtitleDisplaySettings: SubtitleDisplaySettings
    /// 应用日志服务（Phase 8.13：记录应用运行状态，支持导出与清空）。
    let logger: AppLogger

    /// 待播放的媒体请求（由远程文件等入口发起，Player 消费后清空）。
    private(set) var pendingPlayback: MediaItem?

    init() {
        let logger = AppLogger()
        self.logger = logger
        Log.appLogger = logger
        logger.log(.info, category: "App", "应用启动")

        let transcript = SubtitleTranscriptStore()
        subtitleTranscript = transcript
        let translationSettings = TranslationSettings()
        self.translationSettings = translationSettings
        subtitlePipeline = SubtitlePipeline(
            transcript: transcript,
            translationSettings: translationSettings
        )
        localModelDownloadManager = LocalModelDownloadManager(
            descriptor: LocalModelCatalog.gemma4E2B
        )
        translationSettingsViewModel = TranslationSettingsViewModel(
            settings: translationSettings,
            downloadManager: localModelDownloadManager
        )
        subtitleDisplaySettings = SubtitleDisplaySettings()

        logger.log(.info, category: "App", "应用环境初始化完成")
    }

    /// 请求播放并切换到 Player Tab。
    func requestPlayback(of item: MediaItem) {
        logger.log(.info, category: "Playback", "请求播放: \(item.title)")
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
