import Foundation
import SwiftUI

/// 播放器控制栏（Liquid Glass：控制栏与播放按钮使用原生玻璃）。
struct PlayerControlsView: View {
    let viewModel: PlayerViewModel
    let onFullscreen: () -> Void
    let showsOrientationControls: Bool

    var body: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            seekBar

            HStack {
                Text(formatTime(viewModel.isScrubbing ? viewModel.seekTarget : viewModel.currentTime))
                Spacer()
                Text(viewModel.duration > 0 ? formatTime(viewModel.duration) : "--:--")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    replayButton
                    playButton
                    rateMenu
                    aspectButton
                    subtitleButton
                    volumeMenu
                    sizeMenu
                    reinitializeButton
                    if showsOrientationControls {
                        landscapeButton
                        portraitButton
                    }
                    fullscreenButton
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .glassEffect(.regular.tint(.blue), in: .rect(cornerRadius: AppTheme.CornerRadius.lg))
    }

    // MARK: - 进度

    private var seekBar: some View {
        Slider(
            value: Binding(
                get: { viewModel.isScrubbing ? viewModel.seekTarget : viewModel.currentTime },
                set: { viewModel.seekTarget = $0 }
            ),
            in: 0...max(viewModel.duration, 1),
            onEditingChanged: { editing in
                viewModel.isScrubbing = editing
                if !editing {
                    Task { await viewModel.seek(to: viewModel.seekTarget) }
                }
            }
        )
        .tint(.white)
        // 时长未知（未就绪 / HLS 未填充 seek 范围）时禁止拖动，
        // 避免 0...1 退化范围把任意拖动变成「从头重播」。
        .disabled(viewModel.duration <= 0)
    }

    // MARK: - 按钮

    private var replayButton: some View {
        Button {
            Task { await viewModel.seek(to: 0) }
        } label: {
            Image(systemName: "backward.end.fill")
                .font(.subheadline.weight(.semibold))
                .frame(width: 40, height: 40)
                .glassEffect(.regular.tint(.white).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("重新播放")
    }

    private var playButton: some View {
        Button {
            Task { await viewModel.togglePlayPause() }
        } label: {
            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 56, height: 56)
                .glassEffect(.regular.tint(.white).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.isPlaying ? "暂停" : "播放")
    }

    private var rateMenu: some View {
        Menu {
            ForEach([0.5 as Float, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in
                Button("\(value.formatted(.number.precision(.fractionLength(0...2))))x") {
                    Task { await viewModel.setRate(value) }
                }
            }
        } label: {
            Text("\(viewModel.rate.formatted(.number.precision(.fractionLength(0...2))))x")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassEffect(.regular.tint(.white).interactive(), in: .capsule)
        }
    }

    private var aspectButton: some View {
        Button {
            withAnimation(.snappy) {
                viewModel.setAspectMode(viewModel.aspectMode == .fit ? .fill : .fit)
            }
        } label: {
            Image(systemName: viewModel.aspectMode == .fit
                ? "rectangle.arrowtriangle.2.outward"
                : "rectangle.arrowtriangle.2.inward")
                .font(.subheadline.weight(.semibold))
                .frame(width: 40, height: 40)
                .glassEffect(.regular.tint(.white).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("切换画面比例")
    }

    private var subtitleButton: some View {
        Button {
            viewModel.toggleSubtitle()
        } label: {
            Image(systemName: viewModel.isSubtitleEnabled ? "captions.bubble.fill" : "captions.bubble")
                .font(.subheadline.weight(.semibold))
                .frame(width: 40, height: 40)
                .glassEffect(.regular.tint(viewModel.isSubtitleEnabled ? .green : .white).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("字幕")
    }

    private var volumeMenu: some View {
        Menu {
            Slider(
                value: Binding(
                    get: { viewModel.volume },
                    set: { value in
                        Task { await viewModel.setVolume(value) }
                    }
                ),
                in: 0...1
            )
            .frame(width: 160)
        } label: {
            Image(systemName: viewModel.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.subheadline.weight(.semibold))
                .frame(width: 40, height: 40)
                .glassEffect(.regular.tint(.white).interactive(), in: .circle)
        }
    }

    /// 画面大小滑块（缩放 0.5x...2.0x）。
    private var sizeMenu: some View {
        Menu {
            VStack(spacing: AppTheme.Spacing.xs) {
                Text("画面大小 \(viewModel.videoScale.formatted(.number.precision(.fractionLength(1))))x")
                    .font(.caption)
                Slider(
                    value: Binding(
                        get: { viewModel.videoScale },
                        set: { viewModel.videoScale = $0 }
                    ),
                    in: 0.5...2.0,
                    step: 0.05
                )
                .frame(width: 160)
            }
            .padding(AppTheme.Spacing.xs)
        } label: {
            Image(systemName: "viewfinder")
                .font(.subheadline.weight(.semibold))
                .frame(width: 40, height: 40)
                .glassEffect(.regular.tint(.white).interactive(), in: .circle)
        }
    }

    /// 手动横屏全屏（自动旋转失败时的兜底选项）。
    private var landscapeButton: some View {
        Button {
            PlayerOrientationController.requestLandscape()
        } label: {
            Image(systemName: "rotate.right")
                .font(.subheadline.weight(.semibold))
                .frame(width: 40, height: 40)
                .glassEffect(.regular.tint(.white).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("横屏全屏")
    }

    private var portraitButton: some View {
        Button {
            PlayerOrientationController.requestPortrait()
        } label: {
            Image(systemName: "rotate.left")
                .font(.subheadline.weight(.semibold))
                .frame(width: 40, height: 40)
                .glassEffect(.regular.tint(.white).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("竖屏全屏")
    }

    private var fullscreenButton: some View {
        Button(action: onFullscreen) {
            Image(systemName: viewModel.isFullScreen
                ? "arrow.down.right.and.arrow.up.left"
                : "arrow.up.left.and.arrow.down.right")
                .font(.subheadline.weight(.semibold))
                .frame(width: 40, height: 40)
                .glassEffect(.regular.tint(.white).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.isFullScreen ? "退出全屏" : "全屏")
    }

    /// 手动初始化：重新加载当前媒体（换片卡转圈 / 状态异常时手动恢复）。
    private var reinitializeButton: some View {
        Button {
            viewModel.reinitialize()
        } label: {
            Image(systemName: "arrow.clockwise.circle")
                .font(.subheadline.weight(.semibold))
                .frame(width: 40, height: 40)
                .glassEffect(.regular.tint(.white).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("重新初始化播放器")
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "00:00" }
        let total = Int(time)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
