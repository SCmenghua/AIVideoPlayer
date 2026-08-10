import SwiftUI

/// 设置页「翻译服务」卡片（Phase 7）：
/// Provider 选择 / 目标语言 / 云端配置与测试连接 / 本地模型下载 / 启用开关。
struct TranslationSettingsCard: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel: TranslationSettingsViewModel?

    var body: some View {
        Group {
            if let viewModel {
                card(viewModel)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = TranslationSettingsViewModel(
                    settings: environment.translationSettings,
                    downloadManager: environment.localModelDownloadManager
                )
            }
        }
    }

    private func card(_ vm: TranslationSettingsViewModel) -> some View {
        GlassCard(tint: .orange) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                header
                providerPicker(vm)
                sourceLanguagePicker(vm)
                targetLanguagePicker(vm)
                providerSection(vm)
                contextPolishToggle(vm)
                enableToggle(vm)
                if let message = vm.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(messageTint(vm))
                }
                privacyNote
            }
        }
        .onChange(of: vm.downloadManager.phase) { _, _ in
            vm.handleDownloadPhaseChange()
            rebuildPipeline()
        }
        .alert("隐私提示", isPresented: vm.consentPromptPresented) {
            Button("取消", role: .cancel) {
                vm.dismissConsentPrompt()
            }
            Button("同意并启用") {
                vm.confirmConsentAndEnable()
                rebuildPipeline()
            }
        } message: {
            Text("字幕文本将发送到你配置的翻译服务。请仅在信任该服务时启用。")
        }
    }

    private func messageTint(_ vm: TranslationSettingsViewModel) -> Color {
        vm.settings.isEnabled ? .secondary : .red
    }

    private func rebuildPipeline() {
        Task { await environment.subtitlePipeline.rebuildAfterSettingsChange() }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "globe")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("翻译服务")
                    .font(.headline)
                Text("可替换翻译引擎（Fast NMT / 本地 LLM / 云端 API）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - 选择

    private func providerPicker(_ vm: TranslationSettingsViewModel) -> some View {
        Picker("翻译引擎", selection: Binding(
            get: { vm.settings.selectedProviderID },
            set: { newValue in
                vm.settings.selectedProviderID = newValue
                vm.statusMessage = nil
                rebuildPipeline()
            }
        )) {
            ForEach(TranslationProviderCatalog.all, id: \.id) { provider in
                Text(provider.displayName).tag(provider.id)
            }
        }
        .pickerStyle(.menu)
    }

    private func sourceLanguagePicker(_ vm: TranslationSettingsViewModel) -> some View {
        Picker("原语言", selection: Binding(
            get: { vm.settings.sourceLanguageCode },
            set: { newValue in
                vm.settings.sourceLanguageCode = newValue
                rebuildPipeline()
            }
        )) {
            ForEach(TranslationSourceLanguageCatalog.all, id: \.code) { language in
                Text(language.displayName).tag(language.code)
            }
        }
        .pickerStyle(.menu)
    }

    private func targetLanguagePicker(_ vm: TranslationSettingsViewModel) -> some View {
        Picker("目标语言", selection: Binding(
            get: { vm.settings.targetLanguageCode },
            set: { newValue in
                vm.settings.targetLanguageCode = newValue
                rebuildPipeline()
            }
        )) {
            ForEach(TranslationTargetLanguageCatalog.all, id: \.code) { language in
                Text(language.displayName).tag(language.code)
            }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private func providerSection(_ vm: TranslationSettingsViewModel) -> some View {
        switch vm.settings.selectedProviderID {
        case .fastNMT:
            providerInfo(vm.currentProviderDescriptor)
        case .localLLM:
            LocalLLMSettingsSection(viewModel: vm)
        case .cloudLLM:
            CloudProviderSettingsSection(viewModel: vm)
        }
    }

    private func providerInfo(_ descriptor: TranslationProviderDescriptor) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Label(
                descriptor.isFullyLocal ? "完全本地，文本不出设备" : "云端服务（启用前需隐私提示）",
                systemImage: descriptor.isFullyLocal ? "lock.fill" : "cloud"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(descriptor.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 开关

    @ViewBuilder
    private func contextPolishToggle(_ vm: TranslationSettingsViewModel) -> some View {
        if vm.currentProviderDescriptor.supportsContextPolish {
            Toggle(isOn: Binding(
                get: { vm.settings.isContextPolishEnabled },
                set: { newValue in
                    vm.settings.isContextPolishEnabled = newValue
                    rebuildPipeline()
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("剧情理解润色")
                        .font(.subheadline.weight(.medium))
                    Text("结合最近字幕上下文翻译并润色（自动压缩，仅本地 / 云端 LLM）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.orange)
        }
    }

    private func enableToggle(_ vm: TranslationSettingsViewModel) -> some View {
        Toggle(isOn: Binding(
            get: { vm.settings.isEnabled },
            set: { _ in
                vm.toggleEnabled()
                rebuildPipeline()
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("启用翻译")
                    .font(.subheadline.weight(.medium))
                Text("final 字幕翻译后显示译文（原文 + 译文）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(.orange)
    }

    private var privacyNote: some View {
        Text("云端 Provider 启用后，字幕文本将发送到你配置的翻译服务；本地 Provider 文本不出设备。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
