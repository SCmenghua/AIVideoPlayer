import SwiftUI

/// 远程文件浏览：连接状态、目录导航与文件列表。
struct RemoteFilesView: View {
    let viewModel: RemoteFilesViewModel
    let onPlayMedia: (MediaItem) -> Void

    @State private var showsConnectionSetup = false

    var body: some View {
        Group {
            switch viewModel.connectionState {
            case .disconnected:
                disconnectedView
            case .connecting(let profile):
                VStack(spacing: AppTheme.Spacing.sm) {
                    ProgressView()
                    Text("正在连接 \(profile.name)…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            case .connected:
                connectedView
            }
        }
        .sheet(isPresented: $showsConnectionSetup) {
            ConnectionSetupView(viewModel: viewModel)
        }
    }

    // MARK: - 未连接

    private var disconnectedView: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("未连接远程服务器")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !viewModel.profiles.isEmpty {
                VStack(spacing: AppTheme.Spacing.xs) {
                    ForEach(viewModel.profiles) { profile in
                        profileQuickRow(profile)
                    }
                }
            }

            if let error = viewModel.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            GlassProminentButton(title: "添加服务器", systemImage: "plus") {
                showsConnectionSetup = true
            }
        }
        .frame(maxWidth: .infinity)
        .padding(AppTheme.Spacing.md)
        .glassEffect(.regular, in: .rect(cornerRadius: AppTheme.CornerRadius.lg))
    }

    private func profileQuickRow(_ profile: RemoteServerProfile) -> some View {
        Button {
            Task { await viewModel.reconnect(profile: profile) }
        } label: {
            HStack {
                Image(systemName: "server.rack")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.body.weight(.medium))
                    Text(profile.rootURL.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(AppTheme.Spacing.sm)
            .glassEffect(.regular.tint(.blue).interactive(), in: .rect(cornerRadius: AppTheme.CornerRadius.md))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("删除", role: .destructive) {
                Task { await viewModel.deleteProfile(profile) }
            }
        }
    }

    // MARK: - 已连接

    private var connectedView: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            header

            if !viewModel.directoryStack.isEmpty {
                breadcrumb
            }

            filesSection
        }
    }

    private var header: some View {
        HStack {
            if case .connected(let profile) = viewModel.connectionState {
                Text(profile.name)
                    .font(.headline)
                    .lineLimit(1)
            }
            Spacer()
            GlassIconButton(systemImage: "arrow.clockwise", title: "刷新", tint: .blue) {
                Task { await viewModel.refresh() }
            }
            GlassIconButton(systemImage: "rectangle.portrait.and.arrow.right", title: "断开", tint: .red) {
                Task { await viewModel.disconnect() }
            }
        }
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.xxs) {
                Button("根目录") {
                    Task { await viewModel.goToRoot() }
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.plain)

                ForEach(viewModel.directoryStack) { folder in
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Button(folder.name) {
                        // 跳转到该层级：截断栈并加载
                        Task {
                            await viewModel.jumpTo(folder: folder)
                        }
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var filesSection: some View {
        switch viewModel.files {
        case .loading:
            ProgressView("正在加载目录…")
                .frame(maxWidth: .infinity, minHeight: 140)
        case .empty:
            Text("此目录为空")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
            GlassEffectContainer(spacing: AppTheme.Spacing.xs) {
                ForEach(files) { file in
                    RemoteFileRow(file: file) {
                        if let media = viewModel.mediaItem(from: file) {
                            onPlayMedia(media)
                        } else {
                            Task { await viewModel.open(file) }
                        }
                    }
                }
            }
        }
    }
}
