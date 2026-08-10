import UIKit

/// 播放器全屏/方向策略（Phase 3，按架构文档 8.1.1）。
/// 全部横屏逻辑封装在本模块：其他页面永远不修改此策略，
/// 因此不受播放器横屏影响（未全屏时返回系统默认方向）。
/// 仅使用公开 API（supportedInterfaceOrientations + requestGeometryUpdate），
/// 禁止使用私有 API（如 UIDevice.setValue）。
@MainActor
public enum PlayerOrientationController {
    /// 当前是否处于播放器全屏横屏状态。
    private static var isFullscreenLandscape = false

    /// 当前是否处于横屏：优先读取真实界面方向，读取不到时回退到内部标志。
    public static var isLandscape: Bool {
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first {
            return scene.interfaceOrientation.isLandscape
        }
        return isFullscreenLandscape
    }

    /// AppDelegate 查询的方向掩码（应用级唯一入口）。
    public static var interfaceOrientationMask: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad {
            // iPad：保持多任务支持（Split View / Stage Manager），不强制横屏。
            return .all
        }
        return isFullscreenLandscape ? .allButUpsideDown : .portrait
    }

    /// 进入全屏：横屏视频默认请求横屏，竖屏视频保持竖屏。
    public static func enterFullscreen(prefersLandscape: Bool) {
        isFullscreenLandscape = prefersLandscape
        applyOrientation(landscape: prefersLandscape)
    }

    /// 退出全屏：恢复竖屏。
    public static func exitFullscreen() {
        isFullscreenLandscape = false
        applyOrientation(landscape: false)
    }

    /// 手动请求横屏全屏（自动旋转失败时的兜底选项）。
    public static func requestLandscape() {
        isFullscreenLandscape = true
        applyOrientation(landscape: true)
    }

    /// 手动请求恢复竖屏。
    public static func requestPortrait() {
        isFullscreenLandscape = false
        applyOrientation(landscape: false)
    }

    /// 应用目标方向：先刷新 supportedInterfaceOrientations，再请求几何更新。
    /// 横屏请求同时允许左右两个方向（避免单一方向掩码被系统拒绝）；
    /// 失败时延迟重试一次，覆盖首次请求时方向掩码尚未就绪的竞态。
    private static func applyOrientation(landscape: Bool) {
        let mask: UIInterfaceOrientationMask = landscape ? .landscape : .portrait

        // 关键步骤：通知系统重新读取 App 的方向掩码，否则首次请求会按旧掩码校验失败。
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .keyWindow?
            .rootViewController?
            .setNeedsUpdateOfSupportedInterfaceOrientations()

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            return
        }

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in
            // 首次请求可能因掩码刷新时序失败：延迟重试一次。
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard let retryScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first else { return }
                retryScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in
                    // 仍失败（系统锁定 / iPad 多任务等）：保持现状，不强制回退。
                }
            }
        }
    }
}
