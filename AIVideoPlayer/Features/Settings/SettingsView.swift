import SwiftUI

/// 设置页：AI 字幕、字幕语言、翻译引擎、字幕显示、诊断与日志、隐私与关于。
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.md) {
                aiSubtitleCard
                subtitleLanguageCard
                translationCard
                subtitleDisplayCard
                diagnosticsCard
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
                        "AI Video Player · Phase 8.2（翻译引擎卡片 + 本地大模型 + API Key）",
                        "iOS 26 · Swift 6 · SwiftUI",
                    ]
                )
            }
            .padding(AppTheme.Spacing.md)
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggleSubtitlePipeline() {
        Task { await environment.subtitlePipeline.toggle() }
    }

    // MARK: - 翻译引擎（系统内置翻译 / 本地大模型 / API Key）（Phase 7）

    private var translationCard: some View {
        TranslationSettingsCard()
    }

    // MARK: - 诊断与日志（Phase 8.18 二级菜单）

    private var diagnosticsCard: some View {
        NavigationLink {
            DiagnosticsView()
        } label: {
            GlassCard(tint: .indigo) {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.indigo)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("诊断与日志")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("字幕记录 · 翻译记录 · 日志")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
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
                            toggleSubtitlePipeline()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    Text("识别状态：\(environment.subtitlePipeline.status.state.title)")
                        .font(.caption.weight(.medium))
                    Text("模型：\(environment.subtitlePipeline.status.isModelLoaded ? "已加载" : "未加载")"
                        + (environment.subtitlePipeline.status.language.map { " · 识别语言：\($0)" } ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("已转写 \(environment.subtitlePipeline.transcribedWindowCount) 个窗口 · 已产出 \(environment.subtitlePipeline.emittedSegmentCount) 条字幕 · 已翻译 \(environment.subtitlePipeline.translatedSegmentCount) 条")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("音频永远不会离开设备。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 字幕语言（Phase 8.6）

    private var subtitleLanguageCard: some View {
        SubtitleLanguageCard()
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

    // MARK: - 字幕显示（Phase 6）

    private var subtitleDisplayCard: some View {
        GlassCard(tint: .cyan) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "captions.bubble")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("字幕显示")
                            .font(.headline)
                        Text("播放器叠加层：字号与位置")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Picker("字号", selection: fontSizeBinding) {
                    ForEach(SubtitleFontSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    environment.subtitleDisplaySettings.resetPosition()
                } label: {
                    HStack {
                        Text("重置字幕位置")
                        Spacer()
                        Image(systemName: "arrow.counterclockwise")
                    }
                }
                .tint(.cyan)
            }
        }
    }

    private var fontSizeBinding: Binding<SubtitleFontSize> {
        Binding(
            get: { environment.subtitleDisplaySettings.fontSize },
            set: { environment.subtitleDisplaySettings.fontSize = $0 }
        )
    }
}