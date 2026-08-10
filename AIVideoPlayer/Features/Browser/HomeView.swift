import SwiftUI

/// 首页内容（Browser 未打开网页时显示）：AI 字幕状态 + 远程文件浏览。
struct HomeView: View {
    let browserViewModel: BrowserViewModel
    let remoteFilesViewModel: RemoteFilesViewModel
    let subtitleViewModel: SubtitleStatusViewModel?
    let onPlayMedia: (MediaItem) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                HomeTabsSection(viewModel: browserViewModel)

                if let subtitleViewModel {
                    SubtitleStatusCard(viewModel: subtitleViewModel)
                }
                RemoteFilesView(viewModel: remoteFilesViewModel, onPlayMedia: onPlayMedia)
            }
            .padding(AppTheme.Spacing.md)
        }
        .scrollDismissesKeyboard(.immediately)
    }
}
