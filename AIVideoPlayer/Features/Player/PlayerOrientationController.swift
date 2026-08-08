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

    /// AppDelegate 查询的方向掩码（应用级唯一入口）。
    public static var interfaceOrientationMask: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad {
            // iPad：保持多任务支持（Split View / Stage Manager），不强制横屏。
            return .all
        }
        return isFullscreenLandscape ? .allButUpsideDown : .portrait
    }

    /// 进入全屏：允许横屏并请求旋转到横屏。
    public static func enterFullscreen() {
        isFullscreenLandscape = true
        requestRotation(.landscapeRight)
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
            // 部分场景（如 iPad 多任务）不支持强制旋转，回退系统标准旋转请求。
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}
