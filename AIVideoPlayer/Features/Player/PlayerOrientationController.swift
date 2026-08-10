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
    /// 失败或方向未变化时延迟重试，覆盖掩码刷新与全屏转场的竞态。
    private static func applyOrientation(landscape: Bool) {
        let mask: UIInterfaceOrientationMask = landscape ? .landscape : .portrait

        // 关键步骤：通知系统重新读取 App 的方向掩码，否则首次请求会按旧掩码校验失败。
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .keyWindow?
            .rootViewController?
            .setNeedsUpdateOfSupportedInterfaceOrientations()

        requestOrientation(mask: mask, attemptsLeft: 2)
    }

    private static func requestOrientation(mask: UIInterfaceOrientationMask, attemptsLeft: Int) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in
            // 请求失败（掩码刷新时序 / 系统限制）：短暂延迟后重试。
            guard attemptsLeft > 0 else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                requestOrientation(mask: mask, attemptsLeft: attemptsLeft - 1)
            }
        }

        // 请求成功但方向未变（如全屏转场期间被忽略）：延迟校验后仍不符则重试。
        guard attemptsLeft > 0 else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first else { return }
            let isLandscapeNow = scene.interfaceOrientation.isLandscape
            let targetLandscape = mask.contains(.landscape)
            if isLandscapeNow != targetLandscape {
                requestOrientation(mask: mask, attemptsLeft: attemptsLeft - 1)
            }
        }
    }
}
