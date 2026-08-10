import SwiftUI

/// 主页「标签页」区域：用户手动添加的网页快捷入口（独立于收藏）。
struct HomeTabsSection: View {
    let viewModel: BrowserViewModel

    @State private var showsAddTab = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("标签页")
                .font(.headline)

            if viewModel.tabs.isEmpty {
                emptyHint
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassEffectContainer(spacing: AppTheme.Spacing.sm) {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            ForEach(viewModel.tabs) { tab in
                                tabCard(tab)
                            }
                            addTile
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showsAddTab) {
            AddHomeTabSheet(viewModel: viewModel)
        }
    }

    private var emptyHint: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            addTile
            Text("点击 + 添加常用网页；打开网页后，点地址栏左侧的主页按钮可随时回到这里")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var addTile: some View {
        Button {
            showsAddTab = true
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                Text("添加标签页")
                    .font(.caption)
            }
            .frame(width: 120, height: 72)
            .glassEffect(.regular.tint(.blue).interactive(), in: .rect(cornerRadius: AppTheme.CornerRadius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("添加标签页")
    }

    private func tabCard(_ tab: HomeTab) -> some View {
        Button {
            viewModel.openHomeTab(tab)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "safari")
                    .font(.title3)
                    .foregroundStyle(.tint)
                Text(tab.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(tab.url.host ?? tab.url.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 120, height: 72, alignment: .leading)
            .padding(AppTheme.Spacing.sm)
            .glassEffect(.regular.tint(.blue).interactive(), in: .rect(cornerRadius: AppTheme.CornerRadius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开 \(tab.title)")
        .contextMenu {
            Button(role: .destructive) {
                viewModel.removeHomeTab(tab)
            } label: {
                Label("删除标签页", systemImage: "trash")
            }
        }
    }
}

/// 添加标签页表单：名称可选，网址必填（自动补 https://）。
private struct AddHomeTabSheet: View {
    let viewModel: BrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var urlString = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("名称（可选）") {
                    TextField("例如：视频站", text: $title)
                }
                Section("网址") {
                    TextField("例如：example.com", text: $urlString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("添加标签页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        viewModel.addHomeTab(title: title, urlString: urlString)
                        dismiss()
                    }
                    .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
