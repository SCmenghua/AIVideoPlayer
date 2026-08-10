import SwiftUI

/// 播放器（Phase 3 + Phase 6）：AVPlayer 渲染 + 玻璃控制栏 + 全屏横屏
/// （架构文档 8.1.1）+ 双语整句字幕叠加层（SubtitleOverlay）。
struct PlayerView: View {
    @State private var viewModel = PlayerViewModel()
    @State private var subtitleOverlay: SubtitleOverlayViewModel?
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var viewModel = viewModel

        Group {
            if viewModel.currentItem == nil {
                emptyState
            } else {
                playerContent
            }
        }
        .fullScreenCover(isPresented: $viewModel.isFullScreen) {
            FullscreenPlayerView(viewModel: viewModel, subtitleOverlay: subtitleOverlay)
                .onDisappear {
                    PlayerOrientationController.exitFullscreen()
                }
        }
        .navigationTitle("播放器")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.attachSubtitlePipeline(environment.subtitlePipeline)
            viewModel.startObserving()
            let overlay: SubtitleOverlayViewModel
            if let existing = subtitleOverlay {
                overlay = existing
            } else {
                let newOverlay = SubtitleOverlayViewModel(
                    segments: environment.subtitlePipeline.segments,
                    displaySettings: environment.subtitleDisplaySettings
                )
                subtitleOverlay = newOverlay
                overlay = newOverlay
            }

            // 字幕流消费与播放加载并行；宿主视图消失时二者都被取消。
            async let consumeSubtitles: Void = overlay.consume()
            if let pending = environment.consumePendingPlayback() {
                viewModel.load(pending)
            }
            await consumeSubtitles
        }
        .onChange(of: environment.pendingPlayback) { _, _ in
            if let pending = environment.consumePendingPlayback() {
                viewModel.load(pending)
            }
        }
        .onChange(of: viewModel.currentItem) { _, _ in
            // 换片：清空旧视频的时间线与当前字幕，避免残留。
            guard let subtitleOverlay else { return }
            Task { await subtitleOverlay.reset() }
        }
        .onChange(of: environment.subtitlePipeline.isActive) { _, isActive in
            // 管线关闭：清空当前字幕，避免显示过期内容。
            guard !isActive, let subtitleOverlay else { return }
            Task { await subtitleOverlay.reset() }
        }
    }

    // MARK: - 空状态（含调试入口）

    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("暂无播放内容")
                .font(.headline)
            Text("从远程文件选择视频，或使用下方调试入口")
                .font(.caption)
                .foregroundStyle(.secondary)

            // MARK: 调试入口（仅开发调试用）
            // 用途：无远程服务器时快速验证播放器。
            // 删除方法：移除本按钮（及上方"或使用下方调试入口"文案）即可，
            // 正式入口为「远程文件视频行 → AppEnvironment.requestPlayback」，
            // 与本按钮无关，删除不影响播放链路。
            GlassProminentButton(title: "播放示例媒体（调试）", systemImage: "play.circle") {
                viewModel.load(MockRemoteFiles.sampleMediaItem)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 播放内容

    private var playerContent: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VideoLayerView(player: viewModel.player, aspectMode: viewModel.aspectMode)
                .scaleEffect(viewModel.videoScale)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.snappy) {
                        viewModel.isControlsVisible.toggle()
                    }
                }

            if viewModel.isSubtitleEnabled,
               environment.subtitlePipeline.isActive,
               let subtitleOverlay {
                SubtitleOverlay(viewModel: subtitleOverlay, currentTime: viewModel.currentTime)
            }

            if viewModel.isControlsVisible {
                VStack {
                    Spacer()
                    PlayerControlsView(
                        viewModel: viewModel,
                        onFullscreen: {
                            viewModel.isFullScreen = true
                            Task {
                                let prefersLandscape = await viewModel.resolveLandscapeForFullscreen()
                                PlayerOrientationController.enterFullscreen(
                                    prefersLandscape: prefersLandscape
                                )
                            }
                        },
                        showsOrientationControls: false
                    )
                    .padding(AppTheme.Spacing.sm)
                }
                .transition(.move(edge: .bottom))
            }

            if case .loading = viewModel.playbackState {
                ProgressView()
                    .tint(.white)
            }

            if case .failed(let message) = viewModel.playbackState {
                VStack(spacing: AppTheme.Spacing.sm) {
                    Text("播放失败")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    GlassIconButton(systemImage: "arrow.clockwise", title: "重试", tint: .red) {
                        viewModel.reinitialize()
                    }
                }
                .padding(AppTheme.Spacing.lg)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(viewModel.isControlsVisible ? .visible : .hidden, for: .navigationBar)
    }
}

/// 全屏播放器（隐藏状态栏与系统覆盖层；Tab Bar / Navigation Bar 由 fullScreenCover 天然隐藏）。
private struct FullscreenPlayerView: View {
    let viewModel: PlayerViewModel
    let subtitleOverlay: SubtitleOverlayViewModel?
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VideoLayerView(player: viewModel.player, aspectMode: viewModel.aspectMode)
                .scaleEffect(viewModel.videoScale)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.snappy) {
                        viewModel.isControlsVisible.toggle()
                    }
                }

            if viewModel.isSubtitleEnabled,
               environment.subtitlePipeline.isActive,
               let subtitleOverlay {
                SubtitleOverlay(viewModel: subtitleOverlay, currentTime: viewModel.currentTime)
            }

            if viewModel.isControlsVisible {
                VStack {
                    Spacer()
                    PlayerControlsView(
                        viewModel: viewModel,
                        onFullscreen: {
                            viewModel.isFullScreen = false
                            PlayerOrientationController.exitFullscreen()
                        },
                        showsOrientationControls: true
                    )
                    .padding(AppTheme.Spacing.sm)
                }
                .transition(.move(edge: .bottom))
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}
