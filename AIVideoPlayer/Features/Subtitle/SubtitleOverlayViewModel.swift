import CoreGraphics
import Foundation
import Observation

/// 播放器字幕叠加层 ViewModel（Phase 6）：
/// - 消费共享 SubtitlePipeline 的 segments 流，写入 SubtitleEngine 时间线；
/// - 播放光标变化时查询当前句子（整句一次性出现，final 优先）；
/// - 拖动位移换算为归一化坐标，与字号一起经 SubtitleDisplaySettings 持久化。
@MainActor
@Observable
final class SubtitleOverlayViewModel {
    private(set) var activeSegment: SubtitleSegment?

    let displaySettings: SubtitleDisplaySettings

    private let timeline: any SubtitleEngine
    private let segments: AsyncStream<SubtitleSegment>

    init(
        segments: AsyncStream<SubtitleSegment>,
        timeline: any SubtitleEngine = SubtitleTimeline(),
        displaySettings: SubtitleDisplaySettings = SubtitleDisplaySettings()
    ) {
        self.segments = segments
        self.timeline = timeline
        self.displaySettings = displaySettings
    }

    var fontSize: SubtitleFontSize { displaySettings.fontSize }
    var normalizedPosition: CGPoint { displaySettings.normalizedPosition }

    /// 持续消费字幕流；随宿主视图 `.task` 生命周期自动取消。
    func consume() async {
        for await segment in segments {
            await timeline.append(segment)
        }
    }

    /// 播放光标更新：按时间线对齐，整句一次性出现。
    func updatePlaybackTime(_ time: TimeInterval) {
        activeSegment = timeline.segment(at: time)
    }

    /// 换片 / 管线关闭时清空时间线与当前字幕。
    func reset() async {
        await timeline.removeAll()
        activeSegment = nil
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
