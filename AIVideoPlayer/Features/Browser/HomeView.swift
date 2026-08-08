import SwiftUI

/// 首页内容（Browser 未打开网页时显示）：AI 字幕状态 + 远程文件浏览。
struct HomeView: View {
    let remoteFilesViewModel: RemoteFilesViewModel
    let subtitleViewModel: SubtitleStatusViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                SubtitleStatusCard(viewModel: subtitleViewModel)
                RemoteFilesView(viewModel: remoteFilesViewModel)
            }
            .padding(AppTheme.Spacing.md)
        }
        .scrollDismissesKeyboard(.immediately)
    }
}
