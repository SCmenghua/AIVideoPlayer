import SwiftUI

/// WebDAV 媒体来源浏览：打开时自动重连对应服务器并列出目录。
struct RemoteFilesSourceSheet: View {
    let source: MediaSource
    let mediaSourcesViewModel: MediaSourcesViewModel
    let onPlayMedia: (MediaItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var remoteViewModel = RemoteFilesViewModel()
    @State private var profile: RemoteServerProfile?

    var body: some View {
        NavigationStack {
            Group {
                if let profile {
                    RemoteFilesView(viewModel: remoteViewModel, onPlayMedia: onPlayMedia)
                } else {
                    ContentUnavailableView(
                        "服务器配置缺失",
                        systemImage: "server.rack",
                        description: Text("该媒体来源对应的服务器配置已被删除。")
                    )
                }
            }
            .navigationTitle(source.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .task {
            guard profile == nil else { return }
            profile = mediaSourcesViewModel.profile(for: source)
            if let profile, !remoteViewModel.isConnected {
                await remoteViewModel.reconnect(profile: profile)
            }
        }
    }
}
