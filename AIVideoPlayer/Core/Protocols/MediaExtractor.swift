import Foundation

/// 从网页或远程目录 URL 解析可播放媒体。
/// Phase 4 落地具体实现（HTML5 video / MP4 / HLS / M3U8）。
/// 不绕过 DRM。任务取消即取消提取。
public protocol MediaExtractor: Sendable {
    func extractMedia(from url: URL) async throws -> [MediaItem]
}
