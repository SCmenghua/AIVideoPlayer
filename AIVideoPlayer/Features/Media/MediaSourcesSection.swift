import SwiftUI

/// 主页「媒体来源」区域：展示所有来源（网络 / 相册），点击打开。
struct MediaSourcesSection: View {
    let viewModel: MediaSourcesViewModel
    let onPlayMedia: (MediaItem) -> Void

    @State private var showsAddSheet = false
    @State private var activeWebDAVSource: MediaSource?
    @State private var activePhotoSource: MediaSource?
    @State private var activeFilesSource: MediaSource?
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Text("媒体来源")
                    .font(.headline)
                Spacer()
                if !viewModel.sources.isEmpty {
                    Button(isEditing ? "完成" : "编辑") {
                        withAnimation(.snappy) {
                            isEditing.toggle()
                        }
                    }
                    .font(.subheadline)
                    .buttonStyle(.plain)
                }
            }

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
            // 文件来源 Phase 7.13 下线：先展示占位页；后期恢复导入能力时
            // 替换为文件导入视图（FilesMediaSourceView）。
            FilesSourceUnavailableView()
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            addCard
            Text("添加网络（WebDAV）或相册来源后，可在这里直接浏览并播放视频")
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
        HStack(spacing: AppTheme.Spacing.sm) {
            if isEditing {
                Button {
                    viewModel.removeSource(source)
                    if viewModel.sources.isEmpty {
                        isEditing = false
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除媒体来源 \(source.name)")
            }

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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive) {
                    viewModel.removeSource(source)
                } label: {
                    Label("删除媒体来源", systemImage: "trash")
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .glassEffect(.regular.tint(.blue).interactive(), in: .rect(cornerRadius: AppTheme.CornerRadius.md))
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

/// 文件来源占位页（Phase 7.13 起下线）。
/// 后期恢复文件导入时，将本视图替换为实际的文件选择与列表视图。
private struct FilesSourceUnavailableView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "文件来源暂不可用",
                systemImage: "folder",
                description: Text("文件导入功能已在当前版本移除，后续版本将重新支持从文件 App 导入视频。")
            )
            .navigationTitle("文件视频")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
