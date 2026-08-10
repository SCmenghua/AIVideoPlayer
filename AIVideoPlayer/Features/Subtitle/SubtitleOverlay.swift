import SwiftUI

/// 播放器字幕叠加层（Phase 6 → 8.6）：
/// - 整句按播放光标对齐一次性出现；
/// - 双语显示开启：上行原文（小字号）、下行译文（大字号）；
///   关闭：只显示译文一行（译文缺失时显示原文）；
/// - 原生 Liquid Glass 玻璃条；
/// - DragGesture 拖动调整位置，归一化坐标经 SubtitleDisplaySettings 持久化。
struct SubtitleOverlay: View {
    let viewModel: SubtitleOverlayViewModel
    let currentTime: TimeInterval

    @State private var containerSize: CGSize = .zero
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let segment = viewModel.activeSegment {
                    subtitleBubble(segment)
                        .position(
                            x: viewModel.normalizedPosition.x * proxy.size.width + dragOffset.width,
                            y: viewModel.normalizedPosition.y * proxy.size.height + dragOffset.height
                        )
                        .gesture(dragGesture)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.snappy, value: viewModel.activeSegment)
            .onAppear {
                containerSize = proxy.size
                viewModel.updatePlaybackTime(currentTime)
            }
            .onChange(of: proxy.size) { _, newSize in
                containerSize = newSize
            }
            .onChange(of: currentTime) { _, newTime in
                viewModel.updatePlaybackTime(newTime)
            }
        }
    }

    private func subtitleBubble(_ segment: SubtitleSegment) -> some View {
        VStack(spacing: AppTheme.Spacing.xxs) {
            if let translated = segment.translatedText, !translated.isEmpty {
                if viewModel.isBilingualEnabled {
                    // 双语：上行原文（约译文一半大小），下行译文（主行）。
                    Text(segment.originalText)
                        .font(.system(size: viewModel.fontSize.originalPointSize, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .multilineTextAlignment(.center)
                    Text(translated)
                        .font(.system(size: viewModel.fontSize.translationPointSize, weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                } else {
                    // 单语：只显示译文。
                    Text(translated)
                        .font(.system(size: viewModel.fontSize.translationPointSize, weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
            } else {
                // 译文缺失：只显示原文（主行字号）。
                Text(segment.originalText)
                    .font(.system(size: viewModel.fontSize.translationPointSize, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.sm)
        .glassEffect(.regular.tint(.black), in: .rect(cornerRadius: AppTheme.CornerRadius.md))
        .accessibilityLabel("字幕：\(segment.originalText)")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                viewModel.move(by: value.translation, in: containerSize)
                withAnimation(.snappy) {
                    dragOffset = .zero
                }
            }
    }
}
