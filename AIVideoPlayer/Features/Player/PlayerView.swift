import SwiftUI

/// 播放器占位页。Phase 3 接入 PlaybackEngine（AVPlayer）。
struct PlayerView: View {
    @State private var viewModel = PlayerViewModel()

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Spacer()

            Button {
                // Phase 3：经由 PlaybackEngine 控制播放。
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .frame(width: 88, height: 88)
                    .glassEffect(.regular.tint(.accent).interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("播放")

            VStack(spacing: AppTheme.Spacing.xxs) {
                Text(viewModel.state.title)
                    .font(.headline)
                Text("Phase 3 接入 AVPlayer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            GlassEffectContainer(spacing: AppTheme.Spacing.md) {
                HStack(spacing: AppTheme.Spacing.md) {
                    GlassIconButton(systemImage: "backward.fill", title: "后退", tint: .blue) {}
                    GlassIconButton(systemImage: "forward.fill", title: "快进", tint: .blue) {}
                }
            }
            .padding(.bottom, AppTheme.Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("播放器")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension PlayerViewModel.ScreenState {
    var title: String {
        switch self {
        case .noMediaSelected: "暂无播放内容"
        case .ready(let item): item.title
        }
    }
}
