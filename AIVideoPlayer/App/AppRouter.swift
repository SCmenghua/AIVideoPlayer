import Foundation

/// 顶级目的地。Phase 1 只负责 Tab 级导航；
/// 深层链接与播放器路由随后续 Phase 引入。
enum AppTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case browser
    case player
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .browser: "Browser"
        case .player: "Player"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .browser: "globe"
        case .player: "play.rectangle"
        case .settings: "gearshape"
        }
    }
}
