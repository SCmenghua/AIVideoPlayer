import SwiftUI

/// Browser Tab 根视图：玻璃地址栏 + 内容区。
/// 未打开网页时显示首页内容（AI 字幕状态 + 远程文件）；加载网页后显示 WKWebView。
struct BrowserView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var webViewModel = BrowserViewModel()
    @State private var remoteFilesViewModel = RemoteFilesViewModel()
    @State private var subtitleViewModel: SubtitleStatusViewModel?

    @State private var showsHistory = false
    @State private var showsBookmarks = false
    @State private var showsMediaExtraction = false

    var body: some View {
        VStack(spacing: 0) {
            AddressBarView(
                viewModel: webViewModel,
                onShowHistory: { showsHistory = true },
                onShowBookmarks: { showsBookmarks = true },
                onExtractMedia: {
                    showsMediaExtraction = true
                    Task { await webViewModel.extractMediaFromCurrentPage() }
                }
            )

            content
        }
        .navigationTitle("浏览器")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsHistory) {
            HistoryView(viewModel: webViewModel)
        }
        .sheet(isPresented: $showsBookmarks) {
            BookmarksView(viewModel: webViewModel)
        }
        .sheet(isPresented: $showsMediaExtraction) {
            MediaExtractionSheet(viewModel: webViewModel) { media in
                environment.requestPlayback(of: media)
            }
        }
        .task {
            let viewModel = SubtitleStatusViewModel(provider: environment.subtitlePipeline)
            subtitleViewModel = viewModel
            await viewModel.observe()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch webViewModel.navigationState {
        case .idle:
            HomeView(
                remoteFilesViewModel: remoteFilesViewModel,
                subtitleViewModel: subtitleViewModel,
                onPlayMedia: { environment.requestPlayback(of: $0) }
            )
        case .loading, .ready:
            WebViewRepresentable(viewModel: webViewModel)
                .ignoresSafeArea(edges: .bottom)
        case .failed(let url, let message):
            VStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("无法打开页面")
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                GlassIconButton(systemImage: "arrow.clockwise", title: "重试", tint: .blue) {
                    webViewModel.load(url)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(AppTheme.Spacing.lg)
        }
    }
}
