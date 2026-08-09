import SwiftUI

/// 云端 API 配置区：Base URL / API Key / Model + 测试连接 + 状态。
struct CloudProviderSettingsSection: View {
    @Bindable var viewModel: TranslationSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            TextField("Base URL", text: $viewModel.cloudBaseURLInput)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            SecureField("API Key", text: $viewModel.cloudAPIKeyInput)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            TextField("模型名称（如 deepseek-chat）", text: $viewModel.cloudModelNameInput)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button {
                viewModel.testCloudConnection()
            } label: {
                HStack(spacing: AppTheme.Spacing.xs) {
                    if viewModel.isCloudTesting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(viewModel.isCloudTesting ? "测试中…" : "测试连接")
                    Spacer()
                }
            }
            .disabled(!viewModel.isCloudInputComplete || viewModel.isCloudTesting)
            .tint(.orange)

            testResult

            if viewModel.settings.cloudPrivacyConsentAcknowledged {
                Text("已同意隐私提示：字幕文本将发送到你配置的翻译服务。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("启用前需确认：字幕文本将发送到你配置的翻译服务。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var testResult: some View {
        switch viewModel.cloudTestState {
        case .ready:
            Label("连接成功，可以启用", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .error(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        case .loading, .empty, .cancelled:
            EmptyView()
        }
    }
}
