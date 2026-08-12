import SwiftUI

/// 诊断与日志二级菜单（Phase 8.18）：
/// 集中展示「字幕记录 / 翻译记录 / 日志」，三个功能各自独立开关，
/// 默认关闭记录卡片，避免常驻观察高频数据造成 UI 开销。
struct DiagnosticsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                transcriptSection
                translationSection
                logSection
            }
            .padding(AppTheme.Spacing.md)
        }
        .navigationTitle("诊断与日志")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 字幕记录

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Toggle("显示字幕记录", isOn: transcriptBinding)
                .font(.subheadline.weight(.medium))
                .tint(.orange)
            Text("查看识别产出的原文 / 译文，确认识别结果是否到达显示链路。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if environment.subtitleDisplaySettings.showTranscriptCard {
                SubtitleTranscriptCard(transcript: environment.subtitleTranscript)
            }
        }
    }

    // MARK: - 翻译记录

    private var translationSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Toggle("显示翻译记录", isOn: translationBinding)
                .font(.subheadline.weight(.medium))
                .tint(.green)
            Text("查看已成功翻译的字幕，确认翻译服务是否被真正调用。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if environment.subtitleDisplaySettings.showTranslationCard {
                SubtitleTranslationCard(
                    transcript: environment.subtitleTranscript,
                    pipeline: environment.subtitlePipeline
                )
            }
        }
    }

    // MARK: - 日志

    private var logSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Toggle("启用日志记录", isOn: logBinding)
                .font(.subheadline.weight(.medium))
                .tint(.indigo)
            Text("记录应用运行与字幕 / 翻译流水线状态，用于定位问题。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if environment.logger.isEnabled {
                AppLogList(logger: environment.logger)
            }
        }
    }

    // MARK: - Bindings

    private var transcriptBinding: Binding<Bool> {
        Binding(
            get: { environment.subtitleDisplaySettings.showTranscriptCard },
            set: { environment.subtitleDisplaySettings.showTranscriptCard = $0 }
        )
    }

    private var translationBinding: Binding<Bool> {
        Binding(
            get: { environment.subtitleDisplaySettings.showTranslationCard },
            set: { environment.subtitleDisplaySettings.showTranslationCard = $0 }
        )
    }

    private var logBinding: Binding<Bool> {
        Binding(
            get: { environment.logger.isEnabled },
            set: { environment.logger.setEnabled($0) }
        )
    }
}