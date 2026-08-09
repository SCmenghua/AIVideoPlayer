import CoreGraphics
import Foundation
import Observation

/// 字幕显示字号（Phase 6）。
public enum SubtitleFontSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    public var id: Self { self }

    public var title: String {
        switch self {
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        }
    }

    /// 原文字号。
    public var originalPointSize: CGFloat {
        switch self {
        case .small: 15
        case .medium: 18
        case .large: 22
        }
    }

    /// 译文字号（略小于原文，形成层级）。
    public var translationPointSize: CGFloat {
        originalPointSize * 0.85
    }
}

/// 字幕叠加层显示设置（Phase 6），UserDefaults 持久化：
/// 字号与字幕中心点归一化位置（相对播放画面 0...1）。
/// 由 AppEnvironment 全局共享：播放器叠加层与设置页使用同一实例。
@MainActor
@Observable
public final class SubtitleDisplaySettings {
    public static let defaultFontSize: SubtitleFontSize = .medium
    /// 字幕中心点默认位置：水平居中、偏下。
    public static let defaultPosition = CGPoint(x: 0.5, y: 0.78)
    /// 归一化位置边界（避免字幕被拖出画面）。
    public static let positionRange: ClosedRange<CGFloat> = 0.08...0.92

    public var fontSize: SubtitleFontSize {
        didSet { persist() }
    }

    /// 字幕中心点归一化位置（相对播放画面，0...1）。
    public private(set) var normalizedPosition: CGPoint

    private static let fontSizeKey = "subtitle.display.fontSize.v1"
    private static let positionXKey = "subtitle.display.positionX.v1"
    private static let positionYKey = "subtitle.display.positionY.v1"
    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
        let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard

        if let raw = defaults.string(forKey: Self.fontSizeKey),
           let stored = SubtitleFontSize(rawValue: raw) {
            self.fontSize = stored
        } else {
            self.fontSize = Self.defaultFontSize
        }

        if defaults.object(forKey: Self.positionXKey) != nil,
           defaults.object(forKey: Self.positionYKey) != nil {
            let x = Self.clamped(defaults.double(forKey: Self.positionXKey))
            let y = Self.clamped(defaults.double(forKey: Self.positionYKey))
            self.normalizedPosition = CGPoint(x: x, y: y)
        } else {
            self.normalizedPosition = Self.defaultPosition
        }
    }

    /// 更新归一化位置（自动收敛到边界内）并持久化。
    public func setPosition(_ position: CGPoint) {
        normalizedPosition = CGPoint(
            x: Self.clamped(position.x),
            y: Self.clamped(position.y)
        )
        persist()
    }

    /// 重置为默认位置。
    public func resetPosition() {
        normalizedPosition = Self.defaultPosition
        persist()
    }

    // MARK: - Private

    private func persist() {
        let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        defaults.set(fontSize.rawValue, forKey: Self.fontSizeKey)
        defaults.set(normalizedPosition.x, forKey: Self.positionXKey)
        defaults.set(normalizedPosition.y, forKey: Self.positionYKey)
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, positionRange.lowerBound), positionRange.upperBound)
    }
}
