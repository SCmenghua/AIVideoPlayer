import SwiftUI

/// 玻璃地址栏 + 导航按钮（后退/前进/刷新/收藏/历史/收藏面板）。
struct AddressBarView: View {
    @Bindable var viewModel: BrowserViewModel
    let onShowHistory: () -> Void
    let onShowBookmarks: () -> Void
    let onExtractMedia: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Button {
                viewModel.goHome()
            } label: {
                Image(systemName: "house.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .disabled(!viewModel.isWebContentVisible)
            .buttonStyle(.plain)
            .accessibilityLabel("返回主页")

            Button {
                viewModel.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
            }
            .disabled(!viewModel.canGoBack)
            .buttonStyle(.plain)

            Button {
                viewModel.goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
            }
            .disabled(!viewModel.canGoForward)
            .buttonStyle(.plain)

            Button {
                viewModel.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
            }
            .disabled(!viewModel.isWebContentVisible)
            .buttonStyle(.plain)

            // 玻璃地址栏
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("搜索或输入网址", text: $viewModel.addressText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { viewModel.submitAddress(viewModel.addressText) }
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                if !viewModel.addressText.isEmpty {
                    Button {
                        viewModel.addressText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空地址")
                }
            }
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)

            Button {
                viewModel.toggleBookmarkForCurrentPage()
            } label: {
                Image(systemName: viewModel.isCurrentPageBookmarked ? "star.fill" : "star")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(viewModel.isCurrentPageBookmarked ? .yellow : .secondary)
            }
            .disabled(viewModel.currentURL == nil)
            .buttonStyle(.plain)

            Button {
                onExtractMedia()
            } label: {
                Image(systemName: "film")
                    .font(.subheadline.weight(.semibold))
            }
            .disabled(!viewModel.isWebContentVisible)
            .buttonStyle(.plain)

            Menu {
                Button("历史", action: onShowHistory)
                Button("收藏", action: onShowBookmarks)
            } label: {
                Image(systemName: "book")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
        }
        .padding(AppTheme.Spacing.xs)
        .background(.bar)
    }
}
