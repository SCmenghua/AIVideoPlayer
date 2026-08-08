import AVFoundation
import SwiftUI

/// 视频显示比例。
enum VideoAspectMode: String, CaseIterable, Identifiable, Sendable {
    case fit
    case fill

    var id: Self { self }

    var title: String {
        switch self {
        case .fit: "适应"
        case .fill: "填充"
        }
    }

    var gravity: AVLayerVideoGravity {
        switch self {
        case .fit: .resizeAspect
        case .fill: .resizeAspectFill
        }
    }
}

/// 视频渲染层（架构红线唯一例外：只把 engine.player 绑定到 AVPlayerLayer，
/// 不做任何播放控制；控制全部走 ViewModel → PlaybackEngine）。
struct VideoLayerView: UIViewRepresentable {
    let player: AVPlayer?
    let aspectMode: VideoAspectMode

    func makeUIView(context: Context) -> VideoSurfaceView {
        VideoSurfaceView()
    }

    func updateUIView(_ view: VideoSurfaceView, context: Context) {
        view.player = player
        view.videoGravity = aspectMode.gravity
    }
}

/// 承载 AVPlayerLayer 的视图。
final class VideoSurfaceView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    private var playerLayer: AVPlayerLayer? {
        layer as? AVPlayerLayer
    }

    var player: AVPlayer? {
        get { playerLayer?.player }
        set { playerLayer?.player = newValue }
    }

    var videoGravity: AVLayerVideoGravity {
        get { playerLayer?.videoGravity ?? .resizeAspect }
        set { playerLayer?.videoGravity = newValue }
    }
}
