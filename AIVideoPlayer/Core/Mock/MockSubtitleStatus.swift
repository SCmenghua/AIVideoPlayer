import Foundation

/// Phase 1 占位数据：AI 字幕状态。
public enum MockSubtitleStatus {
    public static let off = AISubtitleStatus(state: .off, isModelLoaded: false, language: nil)
    public static let ready = AISubtitleStatus(state: .ready, isModelLoaded: true, language: "en")
}
