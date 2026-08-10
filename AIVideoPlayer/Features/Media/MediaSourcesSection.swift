import SwiftUI

/// 主页「媒体来源」区域：展示所有来源（网络 / 相册 / 文件），点击打开。
struct MediaSourcesSection: View {
    let viewModel: MediaSourcesViewModel
    let onPlayMedia: (MediaItem) -> Void

    @State private var showsAddSheet = false
    @State private var activeWebDAVSource: MediaSource?
    @State private var activePhotoSource: MediaSource?
    @State private var activeFilesSource: MediaSource?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("媒体来源")
                .font(.headline)

            if viewModel.sources.isEmpty {
                emptyState
            } else {
                GlassEffectContainer(spacing: AppTheme.Spacing.sm) {
                    VStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(viewModel.sources) { source in
                            sourceCard(source)
                        }
                        addCard
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showsAddSheet) {
            AddMediaSourceSheet(viewModel: viewModel)
        }
        .sheet(item: $activeWebDAVSource) { source in
            RemoteFilesSourceSheet(
                source: source,
                mediaSourcesViewModel: viewModel,
                onPlayMedia: onPlayMedia
            )
        }
        .sheet(item: $activePhotoSource) { _ in
            PhotoLibraryVideosView(onPlayMedia: onPlayMedia)
        }
        .sheet(item: $activeFilesSource) { _ in
            FilesMediaSourceView(viewModel: viewModel, onPlayMedia: onPlayMedia)
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            addCard
            Text("添加网络（WebDAV）、相册或文件来源后，可在这里直接浏览并播放视频")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var addCard: some View {
        Button {
            showsAddSheet = true
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                Text("添加媒体来源")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(AppTheme.Spacing.md)
            .glassEffect(.regular.tint(.blue).interactive(), in: .rect(cornerRadius: AppTheme.CornerRadius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("添加媒体来源")
    }

    private func sourceCard(_ source: MediaSource) -> some View {
        Button {
            open(source)
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: source.kind.systemImage)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(source.kind.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(AppTheme.Spacing.md)
            .glassEffect(.regular.tint(.blue).interactive(), in: .rect(cornerRadius: AppTheme.CornerRadius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开 \(source.name)")
        .contextMenu {
            Button(role: .destructive) {
                viewModel.removeSource(source)
            } label: {
                Label("删除媒体来源", systemImage: "trash")
            }
        }
    }

    private func open(_ source: MediaSource) {
        switch source.kind {
        case .webDAV:
            activeWebDAVSource = source
        case .photoLibrary:
            activePhotoSource = source
        case .files:
            activeFilesSource = source
        }
    }
}
