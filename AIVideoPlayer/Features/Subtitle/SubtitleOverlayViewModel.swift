import CoreGraphics
import Foundation
import Observation

/// 播放器字幕叠加层 ViewModel（Phase 8.5 重构）：
/// - 直接读取共享 `SubtitleTranscriptStore`，按播放光标查询当前句子
///   （整句一次性出现，final 优先；存储有界，final 到达时收敛 partial）；
/// - 不再消费单次迭代的 AsyncStream：播放器 Tab 反复进出 / 全屏切换后
///   显示链路不会因流的单次迭代语义失效而丢失字幕；
/// - 拖动位移换算为归一化坐标，与字号一起经 SubtitleDisplaySettings 持久化。
@MainActor
@Observable
final class SubtitleOverlayViewModel {
    private(set) var currentTime: TimeInterval = 0

    let displaySettings: SubtitleDisplaySettings
    private let transcript: SubtitleTranscriptStore

    init(
        transcript: SubtitleTranscriptStore,
        displaySettings: SubtitleDisplaySettings = SubtitleDisplaySettings()
    ) {
        self.transcript = transcript
        self.displaySettings = displaySettings
    }

    /// 当前应显示的字幕（随播放光标与字幕记录变化自动刷新）。
    var activeSegment: SubtitleSegment? {
        transcript.segment(at: currentTime)
    }

    var fontSize: SubtitleFontSize { displaySettings.fontSize }
    var isBilingualEnabled: Bool { displaySettings.isBilingualEnabled }
    var normalizedPosition: CGPoint { displaySettings.normalizedPosition }

    /// 播放光标更新：按字幕记录对齐，整句一次性出现。
    func updatePlaybackTime(_ time: TimeInterval) {
        currentTime = time
    }

    /// 换片 / 管线关闭时清空字幕记录与当前字幕。
    func reset() {
        transcript.clear()
        currentTime = 0
    }

    /// 拖动结束：把位移换算成新的归一化位置（边界收敛）并持久化。
    func move(by translation: CGSize, in containerSize: CGSize) {
        guard containerSize.width > 0, containerSize.height > 0 else { return }
        let current = displaySettings.normalizedPosition
        displaySettings.setPosition(
            CGPoint(
                x: current.x + translation.width / containerSize.width,
                y: current.y + translation.height / containerSize.height
            )
        )
    }
}
