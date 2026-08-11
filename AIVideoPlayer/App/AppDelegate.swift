import UIKit
import AVFoundation

/// 应用级方向策略桥接。
/// 只转发 Player 模块的方向策略，不包含任何业务逻辑。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        configureAudioSession()
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        PlayerOrientationController.interfaceOrientationMask
    }

    /// 配置音频会话：允许音频输出路由自动切换（蓝牙 ↔ 扬声器）。
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // playback 类别：播放音频，不录音。
            // 默认路由策略：音频输出会随系统自动切换（蓝牙连接时用蓝牙，断开时用扬声器）。
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            print("音频会话配置失败：\(error.localizedDescription)")
        }
    }
}
