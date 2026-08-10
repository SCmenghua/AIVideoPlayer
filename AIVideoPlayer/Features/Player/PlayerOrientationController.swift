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

    /// 当前是否处于横屏（供全屏控制栏的横/竖屏切换按钮判断方向）。
    public static var isLandscape: Bool {
        isFullscreenLandscape
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
        requestRotation(prefersLandscape ? .landscapeRight : .portrait)
    }

    /// 退出全屏：恢复竖屏。
    public static func exitFullscreen() {
        isFullscreenLandscape = false
        requestRotation(.portrait)
    }

    /// 手动请求横屏全屏（自动旋转失败时的兜底选项）。
    public static func requestLandscape() {
        isFullscreenLandscape = true
        requestRotation(.landscapeRight)
    }

    /// 手动请求恢复竖屏。
    public static func requestPortrait() {
        isFullscreenLandscape = false
        requestRotation(.portrait)
    }

    private static func requestRotation(_ orientation: UIInterfaceOrientation) {
        let mask: UIInterfaceOrientationMask
        switch orientation {
        case .landscapeLeft: mask = .landscapeLeft
        case .landscapeRight: mask = .landscapeRight
        default: mask = .portrait
        }

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            return
        }

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in
            // 旋转请求失败（如系统锁定或 iPad 多任务）时不做强制回退；
            // 全屏控制栏已提供手动「横屏/竖屏」按钮作为兜底。
        }
    }
}
