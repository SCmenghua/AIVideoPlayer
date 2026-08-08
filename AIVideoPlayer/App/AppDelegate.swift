import UIKit

/// 应用级方向策略桥接。
/// 只转发 Player 模块的方向策略，不包含任何业务逻辑。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        PlayerOrientationController.interfaceOrientationMask
    }
}
