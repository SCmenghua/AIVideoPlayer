import SwiftUI

/// Phase 4：网页 / 直链媒体提取结果列表。
/// 由 BrowserView 在点击“提取视频”后弹出；点击条目经 `AppEnvironment.requestPlayback` 播放。
/// 删除方法：移除按钮（AddressBarView.onExtractMedia）与本 sheet 即可回到纯浏览。
struct MediaExtractionSheet: View {
    let viewModel: BrowserViewModel
    let onPlay: (MediaItem) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("提取的视频")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.extractedMedia {
        case .loading:
            VStack(spacing: AppTheme.Spacing.sm) {
                ProgressView()
                Text("正在提取可播放媒体…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready(let items):
            List(items) { item in
                Button {
                    onPlay(item)
                    dismiss()
                } label: {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: item.kind.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .foregroundStyle(item.kind.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            Text(item.url.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "play.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.plain)
        case .empty:
            VStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "video.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("未找到可播放的媒体")
                    .font(.headline)
                Text("页面没有可提取的视频，或资源受保护（不绕过 DRM）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(AppTheme.Spacing.lg)
        case .error(let message):
            VStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("提取失败")
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                GlassIconButton(systemImage: "arrow.clockwise", title: "重试", tint: .blue) {
                    Task { await viewModel.extractMediaFromCurrentPage() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(AppTheme.Spacing.lg)
        case .cancelled:
            VStack(spacing: AppTheme.Spacing.sm) {
                Text("已取消")
                    .font(.headline)
                GlassIconButton(systemImage: "arrow.clockwise", title: "重试", tint: .blue) {
                    Task { await viewModel.extractMediaFromCurrentPage() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private extension MediaItem.Kind {
    var systemImage: String {
        switch self {
        case .video: "film.fill"
        case .audio: "music.note"
        }
    }

    var tint: Color {
        switch self {
        case .video: .purple
        case .audio: .orange
        }
    }
}
