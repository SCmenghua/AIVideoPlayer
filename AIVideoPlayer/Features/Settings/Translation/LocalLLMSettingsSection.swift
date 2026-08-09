import SwiftUI

/// 本地大模型配置区：模型信息、下载 / 取消 / 重试 / 删除。
struct LocalLLMSettingsSection: View {
    @Bindable var viewModel: TranslationSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.downloadManager.descriptor.displayName)
                        .font(.subheadline.weight(.medium))
                    Text("\(viewModel.downloadManager.modelSizeLabel) · 完全离线")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge
            }

            if let title = viewModel.downloadProgressTitle {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            switch viewModel.downloadManager.phase {
            case .downloading:
                ProgressView(value: downloadFraction)
                    .tint(.orange)
                Button("取消下载", role: .cancel) {
                    viewModel.cancelDownload()
                }
                .tint(.orange)
            case .failed:
                Button("重试下载") {
                    viewModel.retryDownload()
                }
                .tint(.orange)
            case .cancelled:
                Button("继续下载") {
                    viewModel.retryDownload()
                }
                .tint(.orange)
            case .idle:
                if !viewModel.downloadManager.isModelDownloaded {
                    Button("下载模型") {
                        viewModel.startDownload()
                    }
                    .tint(.orange)
                }
            case .verifying, .completed:
                EmptyView()
            }

            if viewModel.downloadManager.isModelDownloaded {
                Button("删除已下载模型", role: .destructive) {
                    Task { await viewModel.deleteModel() }
                }
                .tint(.orange)
            }
        }
    }

    private var downloadFraction: Double {
        switch viewModel.downloadManager.phase {
        case .downloading(_, let fraction):
            fraction
        case .idle, .verifying, .completed, .failed, .cancelled:
            0
        }
    }

    private var statusBadge: some View {
        Group {
            if viewModel.downloadManager.isModelDownloaded {
                GlassBadge(text: "已下载", systemImage: "checkmark", tint: .green)
            } else if viewModel.downloadManager.phase.isBusy {
                GlassBadge(text: "下载中", systemImage: "arrow.down.circle", tint: .orange)
            } else {
                GlassBadge(text: "未下载", tint: .gray)
            }
        }
    }
}
