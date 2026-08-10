import Foundation
import SwiftUI

/// 播放器控制栏（Liquid Glass：控制栏与播放按钮使用原生玻璃）。
struct PlayerControlsView: View {
    let viewModel: PlayerViewModel
    let onFullscreen: () -> Void
    let showsOrientationControls: Bool
    @Environment(AppEnvironment.self) private var environment

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
                    playButton
                    rateMenu
                    subtitleButton
                    if viewModel.isSubtitleEnabled {
                        languageMenu
                    }
                    sizeMenu
                    settingsMenu
                    if showsOrientationControls {
                        orientationButton
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

    /// 字幕语言选择（原语言 / 目标语言）：字幕开关打开后出现。
    private var languageMenu: some View {
        Menu {
            Picker("原语言", selection: Binding(
                get: { environment.translationSettings.sourceLanguageCode },
                set: { environment.translationSettings.sourceLanguageCode = $0 }
            )) {
                ForEach(environment.translationSettings.visibleSourceLanguages, id: \.code) { language in
                    Text(language.displayName).tag(language.code)
                }
            }

            Picker("目标语言", selection: Binding(
                get: { environment.translationSettings.targetLanguageCode },
                set: { environment.translationSettings.targetLanguageCode = $0 }
            )) {
                ForEach(environment.translationSettings.visibleTargetLanguages, id: \.code) { language in
                    Text(language.displayName).tag(language.code)
                }
            }
        } label: {
            Image(systemName: "character.bubble")
                .font(.subheadline.weight(.semibold))
                .frame(width: 40, height: 40)
                .glassEffect(.regular.tint(.orange).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("字幕语言")
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

    /// 设置二级菜单：收纳不常用的播放器控制项。
    private var settingsMenu: some View {
        Menu {
            Button {
                Task { await viewModel.seek(to: 0) }
            } label: {
                Label("重新播放", systemImage: "backward.end.fill")
            }

            Button {
                withAnimation(.snappy) {
                    viewModel.setAspectMode(viewModel.aspectMode == .fit ? .fill : .fit)
                }
            } label: {
                Label(
                    viewModel.aspectMode == .fit ? "切换为填充画面" : "切换为适应画面",
                    systemImage: "rectangle.arrowtriangle.2.outward"
                )
            }

            Button {
                viewModel.reinitialize()
            } label: {
                Label("重新初始化播放器", systemImage: "arrow.clockwise.circle")
            }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.subheadline.weight(.semibold))
                .frame(width: 40, height: 40)
                .glassEffect(.regular.tint(.white).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("播放器设置")
    }

    /// 横屏 / 竖屏切换（全屏内）：当前横屏则切回竖屏，当前竖屏则切为横屏。
    private var orientationButton: some View {
        Button {
            if PlayerOrientationController.isLandscape {
                PlayerOrientationController.requestPortrait()
            } else {
                PlayerOrientationController.requestLandscape()
            }
        } label: {
            Image(systemName: PlayerOrientationController.isLandscape
                ? "rotate.left"
                : "rotate.right")
                .font(.subheadline.weight(.semibold))
                .frame(width: 40, height: 40)
                .glassEffect(.regular.tint(.white).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PlayerOrientationController.isLandscape ? "切换为竖屏" : "切换为横屏")
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

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "00:00" }
        let total = Int(time)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
