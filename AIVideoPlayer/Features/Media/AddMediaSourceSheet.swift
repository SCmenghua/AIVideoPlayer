import SwiftUI

/// 添加媒体来源：选择类型（网络 WebDAV / 相册 / 文件）并填写对应配置。
struct AddMediaSourceSheet: View {
    let viewModel: MediaSourcesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var kind: MediaSourceKind = .webDAV
    @State private var name = ""
    @State private var serverURLText = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("来源类型") {
                    Picker("类型", selection: $kind) {
                        // 文件来源已下线（Phase 7.13），不参与添加；恢复时移除此过滤。
                        ForEach(MediaSourceKind.allCases.filter { $0 != .files }) { kind in
                            Label(kind.title, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("名称（可选）") {
                    TextField("默认使用类型名称", text: $name)
                }

                switch kind {
                case .webDAV:
                    Section("WebDAV 服务器") {
                        TextField("服务器地址", text: $serverURLText)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("用户名", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("密码", text: $password)
                            .textContentType(.password)
                    }
                    Section {
                        Label("密码仅保存在本机 Keychain；保存时会验证服务器连接。", systemImage: "lock.shield")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .photoLibrary:
                    Section {
                        Label("将读取系统相册中的视频，供内置播放器播放。", systemImage: "photo.on.rectangle.angled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .files:
                    // 文件来源已下线：此分支不可达（选择器已过滤），保留以备后期恢复。
                    Section {
                        Label("文件来源已下线，后续版本将重新支持。", systemImage: "folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = viewModel.lastError {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("添加媒体来源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中…" : "保存") {
                        save()
                    }
                    .disabled(!isValid || isSaving)
                }
            }
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
        switch kind {
        case .webDAV:
            return serverURL != nil && !username.isEmpty && !password.isEmpty
        case .photoLibrary, .files:
            return true
        }
    }

    private func save() {
        switch kind {
        case .webDAV:
            guard let url = serverURL else { return }
            isSaving = true
            Task {
                let ok = await viewModel.addWebDAVSource(
                    name: name,
                    rootURL: url,
                    username: username,
                    password: password
                )
                isSaving = false
                if ok {
                    dismiss()
                }
            }
        case .photoLibrary:
            viewModel.addPhotoLibrarySource(name: name)
            dismiss()
        case .files:
            // 文件来源已下线（Phase 7.13）：保留调用占位，恢复时重新启用。
            viewModel.addFilesSource(name: name)
            dismiss()
        }
    }
}
