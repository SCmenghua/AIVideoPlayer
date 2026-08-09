import Foundation
import Observation

/// 超前识别（Lead-Ahead）设置，UserDefaults 持久化。
/// Phase 5：开关默认开启；领先窗口 2–10 秒，默认 3 秒。
@MainActor
@Observable
public final class SubtitleSettings {
    public static let defaultLeadAheadWindow: TimeInterval = 3
    public static let leadAheadWindowRange: ClosedRange<TimeInterval> = 2...10

    /// 超前识别开关（默认开启）。
    public var isLeadAheadEnabled: Bool {
        didSet { persist() }
    }

    /// 领先窗口 Δ 秒，范围 2–10，自动收敛到边界内。
    public var leadAheadWindow: TimeInterval {
        didSet {
            leadAheadWindow = Self.clamped(leadAheadWindow)
            persist()
        }
    }

    private static let enabledKey = "subtitle.leadAhead.enabled.v1"
    private static let windowKey = "subtitle.leadAhead.window.v1"
    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
        let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        if defaults.object(forKey: Self.enabledKey) == nil {
            defaults.set(true, forKey: Self.enabledKey)
        }
        self.isLeadAheadEnabled = defaults.bool(forKey: Self.enabledKey)

        let storedWindow = defaults.double(forKey: Self.windowKey)
        self.leadAheadWindow = storedWindow > 0
            ? Self.clamped(storedWindow)
            : Self.defaultLeadAheadWindow
    }

    private func persist() {
        let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        defaults.set(isLeadAheadEnabled, forKey: Self.enabledKey)
        defaults.set(leadAheadWindow, forKey: Self.windowKey)
    }

    private static func clamped(_ value: TimeInterval) -> TimeInterval {
        min(max(value, leadAheadWindowRange.lowerBound), leadAheadWindowRange.upperBound)
    }
}
