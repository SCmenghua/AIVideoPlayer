import SwiftUI

/// 首页内容（Browser 未打开网页时显示）：标签页 + AI 字幕状态 + 媒体来源。
struct HomeView: View {
    let browserViewModel: BrowserViewModel
    let subtitleViewModel: SubtitleStatusViewModel?
    let mediaSourcesViewModel: MediaSourcesViewModel
    let onPlayMedia: (MediaItem) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                HomeTabsSection(viewModel: browserViewModel)

                if let subtitleViewModel {
                    SubtitleStatusCard(viewModel: subtitleViewModel)
                }
                MediaSourcesSection(viewModel: mediaSourcesViewModel, onPlayMedia: onPlayMedia)
            }
            .padding(AppTheme.Spacing.md)
        }
        .scrollDismissesKeyboard(.immediately)
    }
}
