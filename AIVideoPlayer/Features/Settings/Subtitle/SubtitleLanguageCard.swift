import SwiftUI

/// 设置页「字幕语言」卡片（Phase 8.6）：
/// 独立组件，与「字幕记录」同层级——
/// - 原语言：视频语音 / 识别与翻译源语言（自动检测 + 12 种语言）；
/// - 翻译语言：字幕译文输出语言（12 种语言）；
/// - 双语显示开关：开启时上行原文（小字）、下行译文（大字）；关闭时只显示译文。
/// 修改立即持久化并重建翻译引擎，保证选择真实生效。
struct SubtitleLanguageCard: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        GlassCard(tint: .teal) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                header
                sourcePicker
                targetPicker
                Divider()
                bilingualToggle
                note
            }
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "character.bubble")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text("字幕语言")
                    .font(.headline)
                Text("原语言（视频语音）→ 翻译语言（译文输出）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - 原语言

    private var sourcePicker: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("原语言")
                    .font(.subheadline.weight(.medium))
                Text("视频语音 / 识别与翻译源语言")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("原语言", selection: sourceBinding) {
                ForEach(TranslationSourceLanguageCatalog.all, id: \.code) { language in
                    Text(language.displayName).tag(language.code)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    private var sourceBinding: Binding<String> {
        Binding(
            get: { environment.translationSettings.sourceLanguageCode },
            set: { newValue in
                environment.translationSettings.sourceLanguageCode = newValue
                environment.subtitlePipeline.rebuildTranslationEngine()
            }
        )
    }

    // MARK: - 翻译语言

    private var targetPicker: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("翻译语言")
                    .font(.subheadline.weight(.medium))
                Text("字幕译文输出语言")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("翻译语言", selection: targetBinding) {
                ForEach(TranslationTargetLanguageCatalog.all, id: \.code) { language in
                    Text(language.displayName).tag(language.code)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    private var targetBinding: Binding<String> {
        Binding(
            get: { environment.translationSettings.targetLanguageCode },
            set: { newValue in
                environment.translationSettings.targetLanguageCode = newValue
                environment.subtitlePipeline.rebuildTranslationEngine()
            }
        )
    }

    // MARK: - 双语显示

    private var bilingualToggle: some View {
        Toggle(isOn: Binding(
            get: { environment.subtitleDisplaySettings.isBilingualEnabled },
            set: { environment.subtitleDisplaySettings.isBilingualEnabled = $0 }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("双语显示")
                    .font(.subheadline.weight(.medium))
                Text("开启：上行原文（小字）、下行译文（大字）；关闭：只显示译文")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(.teal)
    }

    private var note: some View {
        Text("原语言设为「自动检测」时由识别模型判断；手动指定后识别与翻译都以该语言为源。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
