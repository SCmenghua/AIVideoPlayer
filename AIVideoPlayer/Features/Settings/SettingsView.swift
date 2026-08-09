import SwiftUI

/// 设置页：Phase 1 只呈现架构与隐私承诺；具体开关随对应 Phase 落地。
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.md) {
                aiSubtitleCard
                sectionCard(
                    icon: "globe",
                    tint: .orange,
                    title: "翻译服务",
                    lines: [
                        viewModel.translationServiceConfigured ? "已配置" : "未配置（Phase 7）",
                        "启用后，字幕文本将发送到你配置的翻译服务",
                    ]
                )
                sectionCard(
                    icon: "lock.shield",
                    tint: .green,
                    title: "隐私",
                    lines: [
                        "远程账号密码仅保存在本机 Keychain（Phase 2）",
                        "不收集视频、字幕、浏览历史或服务器文件列表",
                    ]
                )
                sectionCard(
                    icon: "info.circle",
                    tint: .purple,
                    title: "关于",
                    lines: [
                        "AI Video Player · Phase 5（WhisperKit 实时识别）",
                        "iOS 26 · Swift 6 · SwiftUI",
                    ]
                )
            }
            .padding(AppTheme.Spacing.md)
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - AI 字幕（Phase 5）

    private var aiSubtitleCard: some View {
        GlassCard(tint: .blue) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "waveform")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI 实时字幕")
                            .font(.headline)
                        Text("本地 WhisperKit，模型已内置")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    GlassTogglePill(
                        isOn: environment.subtitlePipeline.isActive,
                        onTitle: "关闭",
                        offTitle: "启用",
                        tint: .blue
                    ) {
                        withAnimation(.snappy) {
                            Task<Void, Never> { await environment.subtitlePipeline.toggle() }
                        }
                    }
                }

                Toggle(
                    isOn: Binding(
                        get: { environment.subtitleSettings.isLeadAheadEnabled },
                        set: { newValue in
                            environment.subtitleSettings.isLeadAheadEnabled = newValue
                            Task { await environment.subtitlePipeline.rebuildAfterSettingsChange() }
                        }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("超前识别（AI 先听一步）")
                            .font(.subheadline.weight(.medium))
                        Text("关闭后回到逐词实时路径")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("领先窗口：\(Int(environment.subtitleSettings.leadAheadWindow)) 秒")
                        .font(.subheadline)
                    Slider(
                        value: Binding(
                            get: { environment.subtitleSettings.leadAheadWindow },
                            set: { newValue in
                                environment.subtitleSettings.leadAheadWindow = newValue
                                Task { await environment.subtitlePipeline.rebuildAfterSettingsChange() }
                            }
                        ),
                        in: SubtitleSettings.leadAheadWindowRange,
                        step: 1
                    )
                    .tint(.blue)
                    Text("播放器先预读 Δ 秒音频，Whisper 提前转写；识别与翻译延迟被超前窗口吸收（2–10 秒）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("音频永远不会离开设备。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sectionCard(icon: String, tint: Color, title: String, lines: [String]) -> some View {
        GlassCard(tint: tint) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    Text(title)
                        .font(.headline)
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}
