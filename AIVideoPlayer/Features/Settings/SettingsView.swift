import SwiftUI

/// 设置页：Phase 1 只呈现架构与隐私承诺；具体开关随对应 Phase 落地。
struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.md) {
                sectionCard(
                    icon: "waveform",
                    tint: .blue,
                    title: "AI 字幕",
                    lines: [
                        "本地 WhisperKit 实时识别（Phase 5 接入）",
                        "视频与音频永远不会离开设备",
                    ]
                )
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
                        "AI Video Player · Phase 1 基础架构",
                        "iOS 26 · Swift 6 · SwiftUI",
                    ]
                )
            }
            .padding(AppTheme.Spacing.md)
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
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
