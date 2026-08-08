import SwiftUI

/// 浏览历史面板。
struct HistoryView: View {
    let viewModel: BrowserViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.history.isEmpty {
                    ContentUnavailableView("暂无历史记录", systemImage: "clock")
                } else {
                    List {
                        ForEach(viewModel.history) { entry in
                            Button {
                                viewModel.openHistoryEntry(entry)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                        .font(.body.weight(.medium))
                                        .lineLimit(1)
                                    Text(entry.url.absoluteString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                if !viewModel.history.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("清空") { viewModel.clearHistory() }
                    }
                }
            }
        }
    }
}
