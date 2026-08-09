import SwiftUI

/// AI 字幕状态卡：首页上的浮动玻璃交互层。
/// 展示 Mock 管线状态，并提供玻璃开关。
struct SubtitleStatusCard: View {
    let viewModel: SubtitleStatusViewModel

    var body: some View {
        GlassCard(tint: viewModel.status.state.tint) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: viewModel.status.state.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(viewModel.status.state.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI 实时字幕")
                            .font(.headline)
                        Text(viewModel.status.state.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    GlassBadge(text: viewModel.status.state.badgeText, tint: viewModel.status.state.tint)
                }

                if viewModel.status.state.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }

                if viewModel.isActive {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("识别引擎：WhisperKit（本地内置）")
                        Text("模型状态：\(viewModel.status.isModelLoaded ? "已加载" : "未加载")")
                        if let language = viewModel.status.language {
                            Text("识别语言：\(language)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                HStack {
                    Spacer()
                    GlassTogglePill(
                        isOn: viewModel.isActive,
                        onTitle: "关闭",
                        offTitle: "启用",
                        tint: viewModel.status.state.tint
                    ) {
                        withAnimation(.snappy) {
                            viewModel.toggle()
                        }
                    }
                }
            }
            .animation(.snappy, value: viewModel.status.state)
        }
    }
}

// MARK: - AIState UI 映射

extension AIState {
    var title: String {
        switch self {
        case .off: "已关闭"
        case .loading: "模型加载中"
        case .listening: "聆听中"
        case .transcribing: "转写中"
        case .translating: "翻译中"
        case .ready: "就绪"
        case .error: "错误"
        }
    }

    var badgeText: String {
        switch self {
        case .off: "OFF"
        case .loading: "LOADING"
        case .listening: "LISTENING"
        case .transcribing: "TRANSCRIBING"
        case .translating: "TRANSLATING"
        case .ready: "READY"
        case .error: "ERROR"
        }
    }

    var systemImage: String {
        switch self {
        case .off: "waveform.slash"
        case .loading: "arrow.triangle.2.circlepath"
        case .listening: "waveform"
        case .transcribing: "text.bubble"
        case .translating: "character.bubble"
        case .ready: "checkmark.seal"
        case .error: "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .off: .gray
        case .loading, .listening, .transcribing, .translating: .blue
        case .ready: .green
        case .error: .red
        }
    }

    var isBusy: Bool {
        switch self {
        case .loading, .listening, .transcribing, .translating: true
        case .off, .ready, .error: false
        }
    }
}
