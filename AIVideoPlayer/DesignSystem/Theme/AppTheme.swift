import SwiftUI

/// 设计令牌：所有视觉常量集中在这里，保证各页面一致。
enum AppTheme {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum CornerRadius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
    }

    /// Liquid Glass 色调。玻璃元素按语义选择 tint，
    /// 而不是让每个页面各自定义颜色。
    enum GlassTint {
        static let accent: Color = .accentColor
        static let blue: Color = .blue
        static let green: Color = .green
        static let orange: Color = .orange
        static let purple: Color = .purple
        static let red: Color = .red
    }
}
