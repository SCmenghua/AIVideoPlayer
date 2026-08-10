import SwiftUI

/// 漂浮在内容之上的玻璃卡片。
/// 适用于交互性容器，而不是页面背景；内容始终优先。
struct GlassCard<Content: View>: View {
    private let tint: Color?
    private let cornerRadius: CGFloat
    private let content: Content

    init(
        tint: Color? = nil,
        cornerRadius: CGFloat = AppTheme.CornerRadius.md,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        if let tint {
            content
                .padding(AppTheme.Spacing.md)
                .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .padding(AppTheme.Spacing.md)
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        }
    }
}

/// 状态胶囊（例如 READY / ERROR）。纯展示，不响应交互。
struct GlassBadge: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = .blue

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xxs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
            }
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xxs + 2)
        .glassEffect(.regular.tint(tint), in: .capsule)
    }
}

/// 玻璃图标按钮：对触摸做出反应，因此使用 `.interactive()`。
/// 多个玻璃按钮应放入 `GlassEffectContainer` 中统一管理。
struct GlassIconButton: View {
    let systemImage: String
    var title: String? = nil
    var tint: Color = .blue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppTheme.Spacing.xxs) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                if let title {
                    Text(title)
                        .font(.caption.weight(.medium))
                }
            }
            .frame(minWidth: 72)
            .padding(.vertical, AppTheme.Spacing.xs + 2)
            .padding(.horizontal, AppTheme.Spacing.md)
            .glassEffect(.regular.tint(tint).interactive(), in: .rect(cornerRadius: AppTheme.CornerRadius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title ?? systemImage)
    }
}

/// 使用系统 `.glassProminent` 按钮样式的强调操作。
struct GlassProminentButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.body.weight(.semibold))
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.sm)
        }
        .buttonStyle(.glassProminent)
    }
}

/// 胶囊形态的玻璃开关。响应触摸，因此使用 `.interactive()`。
struct GlassTogglePill: View {
    let isOn: Bool
    let onTitle: String
    let offTitle: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: isOn ? "waveform" : "waveform.slash")
                    .font(.subheadline.weight(.semibold))
                Text(isOn ? onTitle : offTitle)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.xs)
            .glassEffect(.regular.tint(tint).interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isOn)
    }
}
