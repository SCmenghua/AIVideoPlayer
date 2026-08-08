import Foundation
import Observation

/// Phase 1 占位。Phase 2 加入 Keychain 凭据状态，
/// Phase 7 加入翻译服务配置。
@MainActor
@Observable
final class SettingsViewModel {
    private(set) var translationServiceConfigured = false
}
