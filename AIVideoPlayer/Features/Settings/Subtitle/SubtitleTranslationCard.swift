import SwiftUI

/// 设置页「翻译记录」卡片（Phase 8.7）：
/// 独立组件，展示已成功翻译的字幕记录（原文 + 译文 + 时间），
/// 与「字幕记录」共享同一数据源（仅过滤带译文的条目）。
/// 用于确认系统翻译是否真的被调用并产出译文，以及查看最近一次翻译失败原因。
struct SubtitleTranslationCard: View {
    let transcript: SubtitleTranscriptStore
    let pipeline: SubtitlePipeline

    var body: some View {
        GlassCard(tint: .green) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                header

                if let error = pipeline.lastTranslationError {
                    Label("最近一次翻译失败：\(error)", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                let translated = transcript.segments.filter {
                    !$0.isPartial && !($0.translatedText ?? "").isEmpty
                }
                if translated.isEmpty {
                    Text("暂无翻译记录：启用 AI 字幕并播放视频后，成功翻译的句子会显示在这里。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, AppTheme.Spacing.xs)
                } else {
                    // Phase 8.17 优化：使用 LazyVStack + ScrollView，只渲染可见行
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            let recent = Array(translated.suffix(20).reversed())
                            ForEach(recent, id: \.id) { segment in
                                translationRow(segment)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "character.bubble.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("翻译记录")
                    .font(.headline)
                Text("已成功翻译 \(pipeline.translatedSegmentCount) 条 · 最近 20 条可见")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func translationRow(_ segment: SubtitleSegment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Self.timeText(segment.startTime))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(segment.originalText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(segment.translatedText ?? "")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func timeText(_ time: TimeInterval) -> String {
        let totalSeconds = max(0, Int(time))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
