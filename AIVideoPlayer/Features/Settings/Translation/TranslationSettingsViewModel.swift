import Foundation
import Observation
import SwiftUI

/// 翻译服务设置 ViewModel（Phase 7）：Provider 选择、云端配置与测试连接、
/// 本地模型下载管理、启用校验。
@MainActor
@Observable
final class TranslationSettingsViewModel {
    let settings: TranslationSettings
    let downloadManager: LocalModelDownloadManager

    /// 云端表单（提交前不落盘）。
    var cloudBaseURLInput: String
    var cloudModelNameInput: String
    var cloudAPIKeyInput: String

    private(set) var cloudTestState: LoadState<Void> = .empty
    var statusMessage: String?
    private(set) var showConsentPrompt = false

    private let apiKeyStore: any APIKeyStoring
    private let providerFactory: @MainActor (TranslationSettings) -> (any TranslationEngine)?
    private var cloudTestTask: Task<Void, Never>?

    init(
        settings: TranslationSettings,
        downloadManager: LocalModelDownloadManager,
        apiKeyStore: any APIKeyStoring = KeychainAPIKeyStore(),
        providerFactory: @escaping @MainActor (TranslationSettings) -> (any TranslationEngine)? = {
            TranslationProviderFactory.make(settings: $0)
        }
    ) {
        self.settings = settings
        self.downloadManager = downloadManager
        self.apiKeyStore = apiKeyStore
        self.providerFactory = providerFactory
        self.cloudBaseURLInput = settings.cloudBaseURL
        self.cloudModelNameInput = settings.cloudModelName
        self.cloudAPIKeyInput = (try? apiKeyStore.loadAPIKey()) ?? ""
    }

    var currentProviderDescriptor: TranslationProviderDescriptor {
        TranslationProviderCatalog.descriptor(for: settings.selectedProviderID)
    }

    var isCurrentProviderReady: Bool {
        switch settings.selectedProviderID {
        case .fastNMT:
            true
        case .localLLM:
            downloadManager.isModelDownloaded
        case .cloudLLM:
            isCloudInputComplete
        }
    }

    var isCloudInputComplete: Bool {
        !cloudBaseURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !cloudModelNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !cloudAPIKeyInput.isEmpty
    }

    var isCloudTesting: Bool {
        if case .loading = cloudTestState {
            return true
        }
        return false
    }

    var consentPromptPresented: Binding<Bool> {
        Binding(
            get: { self.showConsentPrompt },
            set: { newValue in
                if !newValue {
                    self.dismissConsentPrompt()
                }
            }
        )
    }

    private var unreadyReason: String? {
        switch settings.selectedProviderID {
        case .fastNMT:
            nil
        case .localLLM:
            "请先下载本地大模型（\(downloadManager.modelSizeLabel)）。"
        case .cloudLLM:
            "请先完成云端配置并通过「测试连接」。"
        }
    }

    func toggleEnabled() {
        let enable = !settings.isEnabled
        if enable, !isCurrentProviderReady {
            statusMessage = unreadyReason
            return
        }
        settings.isEnabled = enable
        statusMessage = nil
    }

    // MARK: - 云端

    func testCloudConnection() {
        cloudTestTask?.cancel()
        cloudTestTask = Task { [weak self] in
            guard let self else { return }
            cloudTestState = .loading
            do {
                // 表单先落到设置与 Keychain，测试连接才能读到配置。
                settings.cloudBaseURL = cloudBaseURLInput
                settings.cloudModelName = cloudModelNameInput
                try apiKeyStore.saveAPIKey(cloudAPIKeyInput)
                guard let engine = providerFactory(settings)
                    as? (any TranslationEngine & TranslationConnectionTesting)
                else {
                    throw TranslationSettingsError.testConnectionUnavailable
                }
                try await engine.testConnection()
                cloudTestState = .ready(())
                statusMessage = nil
                if settings.cloudPrivacyConsentAcknowledged {
                    settings.isEnabled = true
                } else {
                    showConsentPrompt = true
                }
            } catch {
                cloudTestState = .error(
                    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
            }
        }
    }

    func confirmConsentAndEnable() {
        settings.cloudPrivacyConsentAcknowledged = true
        settings.isEnabled = true
        showConsentPrompt = false
        statusMessage = nil
    }

    func dismissConsentPrompt() {
        showConsentPrompt = false
    }

    // MARK: - 本地模型

    var downloadPhase: LocalModelDownloadManager.Phase {
        downloadManager.phase
    }

    var downloadProgressTitle: String? {
        switch downloadManager.phase {
        case .downloading(let file, let fraction):
            "正在下载 \(file)（\(Int(fraction * 100))%）"
        case .verifying:
            "正在校验模型文件…"
        case .completed:
            "下载完成"
        case .failed(let message):
            "下载失败：\(message)"
        case .cancelled:
            "下载已取消"
        case .idle:
            nil
        }
    }

    func startDownload() {
        downloadManager.start()
        statusMessage = nil
    }

    func cancelDownload() {
        downloadManager.cancel()
    }

    func retryDownload() {
        downloadManager.start()
        statusMessage = nil
    }

    func deleteModel() async {
        do {
            try await downloadManager.deleteModel()
            if settings.localModelDownloadedID == downloadManager.descriptor.id {
                settings.localModelDownloadedID = nil
            }
            if settings.selectedProviderID == .localLLM {
                settings.isEnabled = false
            }
            statusMessage = nil
        } catch {
            statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func handleDownloadPhaseChange() {
        if downloadManager.phase == .completed {
            settings.localModelDownloadedID = downloadManager.descriptor.id
            statusMessage = "模型下载完成，可以启用本地大模型。"
        }
    }
}

/// 翻译设置错误。
enum TranslationSettingsError: LocalizedError, Sendable {
    case testConnectionUnavailable

    var errorDescription: String? {
        switch self {
        case .testConnectionUnavailable:
            "当前 Provider 不支持测试连接。"
        }
    }
}
