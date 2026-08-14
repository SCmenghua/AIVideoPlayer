import SwiftUI

/// 设置页「字幕记录」调试卡片（Phase 8.5）：
/// 展示共享字幕记录中的已识别字幕（原文 + 译文 + 时间），
/// 用于在「识别已产出但播放器无字幕」时核对识别 / 翻译是否真的到达显示链路。
/// 记录为有界存储（最多保留最近 `SubtitleTranscriptStore.maxStoredSegments` 条）。
struct SubtitleTranscriptCard: View {
    let transcript: SubtitleTranscriptStore

    var body: some View {
        GlassCard(tint: .orange) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "text.bubble")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("字幕记录（调试）")
                            .font(.headline)
                        Text("已识别字幕的原文与译文，最多保留最近 \(SubtitleTranscriptStore.maxStoredSegments) 条")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        transcript.clear()
                    } label: {
                        Label("清空", systemImage: "trash")
                            .font(.caption.weight(.medium))
                    }
                    .tint(.orange)
                }

                if transcript.segments.isEmpty {
                    Text("暂无字幕记录：启用 AI 字幕并播放视频后，这里会列出识别结果。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, AppTheme.Spacing.xs)
                } else {
                    // Phase 8.17 优化：使用 LazyVStack + ScrollView，只渲染可见行
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(transcript.recentSegments, id: \.id) { segment in
                                transcriptRow(segment)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }

                if let preview = transcript.previewSegment {
                    Divider()
                    HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.xs) {
                        Text("识别预览")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text(preview.originalText)
                            .font(.caption)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func transcriptRow(_ segment: SubtitleSegment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Text(Self.timeText(segment.startTime))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let translated = segment.translatedText, !translated.isEmpty {
                    Text("已翻译")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                }
                Spacer(minLength: 0)
            }
            Text(segment.originalText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            if let translated = segment.translatedText, !translated.isEmpty {
                Text(translated)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
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
