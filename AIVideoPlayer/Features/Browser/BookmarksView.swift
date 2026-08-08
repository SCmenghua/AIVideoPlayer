import SwiftUI

/// 收藏面板。
struct BookmarksView: View {
    let viewModel: BrowserViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.bookmarks.isEmpty {
                    ContentUnavailableView("暂无收藏", systemImage: "star")
                } else {
                    List {
                        ForEach(viewModel.bookmarks) { bookmark in
                            Button {
                                viewModel.openBookmark(bookmark)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bookmark.title)
                                        .font(.body.weight(.medium))
                                        .lineLimit(1)
                                    Text(bookmark.url.absoluteString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    viewModel.removeBookmark(bookmark)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("收藏")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
