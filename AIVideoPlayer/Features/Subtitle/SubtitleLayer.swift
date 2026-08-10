import SwiftUI

/// 播放器字幕层（Phase 6 + Phase 8.0 修复）：
/// - 开关开启且管线就绪时渲染双语整句字幕（SubtitleOverlay）；
/// - 开关开启但引擎仍在加载 / 出错 / 已关闭时显示状态胶囊，
///   让用户明确知道识别引擎状态，避免「开了字幕却没反应」的困惑。
/// 双语空间：`SubtitleSegment.translatedText` 已就位，
/// Overlay 收到译文即在原文下方显示第二行，无需改动结构。
struct SubtitleLayer: View {
    let isEnabled: Bool
    let status: AISubtitleStatus
    let subtitleOverlay: SubtitleOverlayViewModel?
    let currentTime: TimeInterval

    var body: some View {
        Group {
            if isEnabled {
                switch status.state {
                case .off, .loading, .error:
                    SubtitleStatusPill(state: status.state)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, AppTheme.Spacing.lg)
                case .listening, .transcribing, .translating, .ready:
                    if let subtitleOverlay {
                        SubtitleOverlay(viewModel: subtitleOverlay, currentTime: currentTime)
                    }
                }
            }
        }
    }
}

/// 播放器内 AI 字幕状态胶囊：字幕开关开启但识别引擎未就绪时显示。
/// 状态文案 / 图标 / 颜色复用 AIState 的 UI 映射（SubtitleStatusCard.swift）。
struct SubtitleStatusPill: View {
    let state: AIState

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xxs) {
            Image(systemName: state.systemImage)
            Text(state.title)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xxs)
        .glassEffect(.regular.tint(state.tint), in: .capsule)
        .accessibilityLabel("字幕状态：\(state.title)")
    }
}
