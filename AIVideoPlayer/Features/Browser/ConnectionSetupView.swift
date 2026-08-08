import SwiftUI

/// 新增/编辑远程服务器连接表单。
struct ConnectionSetupView: View {
    let viewModel: RemoteFilesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var serverURLText = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.md) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                            field("显示名称", text: $name, prompt: "例如：我的 NAS")
                            field("服务器地址", text: $serverURLText, prompt: "https://192.168.1.10/dav/", keyboard: .URL)
                            field("用户名", text: $username, prompt: "WebDAV 账号")
                            SecureField("密码", text: $password)
                                .textContentType(.password)
                        }
                    }

                    GlassCard(tint: .green) {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                            Label("隐私", systemImage: "lock.shield")
                                .font(.subheadline.weight(.semibold))
                            Text("密码仅保存在本机 Keychain；文件列表只在连接期间使用，不会上传到任何第三方服务。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let error = viewModel.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    GlassProminentButton(
                        title: isSaving ? "连接中…" : "保存并连接",
                        systemImage: isSaving ? nil : "link"
                    ) {
                        Task { await saveAndConnect() }
                    }
                    .disabled(!isValid || isSaving)
                }
                .padding(AppTheme.Spacing.md)
            }
            .navigationTitle("添加服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func field(
        _ title: String,
        text: Binding<String>,
        prompt: String,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private var serverURL: URL? {
        let trimmed = serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return nil
        }
        return url
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && serverURL != nil
            && !username.isEmpty
            && !password.isEmpty
    }

    private func saveAndConnect() async {
        guard let url = serverURL else { return }
        isSaving = true
        await viewModel.connect(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            rootURL: url,
            username: username,
            password: password
        )
        isSaving = false
        if viewModel.isConnected {
            dismiss()
        }
    }
}
