import Foundation
import SwiftUI

/// 首页（Browser 标签根视图）。
/// Phase 2 将 Mock 地址栏与文件列表替换为 WKWebView + 真实远程浏览。
struct HomeView: View {
    @State private var viewModel = BrowserViewModel()
    @State private var subtitleViewModel = SubtitleStatusViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                MockAddressBar()
                SubtitleStatusCard(viewModel: subtitleViewModel)
                remoteFilesSection
            }
            .padding(AppTheme.Spacing.md)
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("首页")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.refresh() }
        .task { await subtitleViewModel.observe() }
        .refreshable { await viewModel.refresh() }
    }

    // MARK: - 远程文件区

    @ViewBuilder
    private var remoteFilesSection: some View {
        switch viewModel.remoteFiles {
        case .loading:
            ProgressView("正在加载远程文件…")
                .frame(maxWidth: .infinity, minHeight: 140)
        case .empty:
            VStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "folder")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("暂无远程文件")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 140)
        case .error(let message):
            VStack(spacing: AppTheme.Spacing.sm) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                GlassIconButton(systemImage: "arrow.clockwise", title: "重试", tint: .red) {
                    Task { await viewModel.refresh() }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 140)
        case .cancelled:
            Text("已取消")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 140)
        case .ready(let files):
            fileList(files)
        }
    }

    private func fileList(_ files: [RemoteFile]) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            HStack {
                Text("远程文件")
                    .font(.headline)
                Spacer()
                GlassEffectContainer(spacing: AppTheme.Spacing.xs) {
                    GlassBadge(text: "\(files.count)", systemImage: "externaldrive", tint: .blue)
                    GlassIconButton(systemImage: "arrow.clockwise", title: "刷新", tint: .blue) {
                        Task { await viewModel.refresh() }
                    }
                }
            }

            // 多个玻璃行放入同一个容器：支持合并与性能优化。
            GlassEffectContainer(spacing: AppTheme.Spacing.xs) {
                ForEach(files) { file in
                    RemoteFileRow(file: file)
                }
            }
        }
    }
}

/// Phase 1 占位地址栏（纯 UI，不可交互）。Phase 2 接入 WKWebView。
private struct MockAddressBar: View {
    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text("搜索或输入网址（Phase 2 开放）")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
        .glassEffect(.regular, in: .capsule)
        .accessibilityLabel("地址栏（即将开放）")
    }
}

/// 远程文件玻璃行。响应点击，因此使用 `.interactive()`。
private struct RemoteFileRow: View {
    let file: RemoteFile

    var body: some View {
        Button {
            // Phase 2：进入目录 / 把媒体 URL 交给播放器。
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: file.kind.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(file.kind.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(file.metadataText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(AppTheme.Spacing.sm)
            .glassEffect(.regular.tint(file.kind.tint).interactive(), in: .rect(cornerRadius: AppTheme.CornerRadius.md))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - UI 映射

private extension RemoteFile.Kind {
    var systemImage: String {
        switch self {
        case .folder: "folder.fill"
        case .video: "film.fill"
        case .audio: "music.note"
        case .image: "photo.fill"
        case .document: "doc.fill"
        case .other: "questionmark.folder"
        }
    }

    var tint: Color {
        switch self {
        case .folder: .blue
        case .video: .purple
        case .audio: .orange
        case .image: .green
        case .document, .other: .gray
        }
    }
}

private extension RemoteFile.Connection {
    var displayName: String {
        switch self {
        case .webdav: "WebDAV"
        case .smb: "SMB"
        case .ftp: "FTP"
        case .local: "本机"
        }
    }
}

private extension RemoteFile {
    var metadataText: String {
        let connectionLabel = connection.displayName
        if let size, size > 0 {
            return "\(connectionLabel) · \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))"
        }
        return connectionLabel
    }
}
