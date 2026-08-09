import Foundation

/// Phase 4 的 `MediaExtractor` 生产实现。
///
/// 输入网页或直接媒体 URL，输出 `[MediaItem]`：
/// - 直接媒体文件（MP4 / MOV / WebM / MP3 / M4A 等）→ 单个 `MediaItem`，不发起网络请求；
/// - HLS（`.m3u8` / `.m3u`）→ 单个视频 `MediaItem`（AVPlayer 原生处理 master / variant 播放列表）；
/// - HTML 页面 → 提取 `<video>` / `<source src>` / `data-src`，解析相对地址与 HTML 实体并去重。
///
/// 不绕过 DRM：只提取普通 HTTP(S) 媒体地址；带 `encrypted` 等加密标记或非 HTTP(S)
/// 协议的资源一律跳过，不做任何解密或绕过。
///
/// URLSession 请求随调用方 Task 取消；解析过程通过 `Task.checkCancellation()` 响应取消。
public struct WebMediaExtractor: MediaExtractor {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func extractMedia(from url: URL) async throws -> [MediaItem] {
        try Task.checkCancellation()

        if url.isHTTP, let directItem = Self.directMediaItem(from: url) {
            return [directItem]
        }

        guard url.isHTTP else {
            throw MediaExtractionError.unsupportedURLScheme(url.scheme ?? "")
        }

        let (data, response) = try await session.data(from: url)
        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MediaExtractionError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MediaExtractionError.httpError(statusCode: httpResponse.statusCode)
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw MediaExtractionError.invalidHTML
        }

        let pageTitle = Self.pageTitle(from: html)
        let sources = Self.videoSources(in: html, baseURL: url)
        return sources.map { source in
            MediaItem(
                title: pageTitle ?? source.title ?? Self.title(from: url),
                url: source.url,
                kind: source.kind,
                source: .web
            )
        }
    }

    // MARK: - 直链媒体

    private static func directMediaItem(from url: URL) -> MediaItem? {
        guard let kind = mediaKind(from: url) else { return nil }
        return MediaItem(title: title(from: url), url: url, kind: kind, source: .web)
    }

    private static func mediaKind(from url: URL) -> MediaItem.Kind? {
        switch url.pathExtension.lowercased() {
        case "mp4", "mov", "m4v", "mkv", "avi", "webm", "m3u8", "m3u":
            return .video
        case "mp3", "m4a", "wav", "aac", "flac":
            return .audio
        default:
            return nil
        }
    }

    // MARK: - HTML5 video 提取

    private static func videoSources(in html: String, baseURL: URL) -> [VideoSource] {
        var sources: [VideoSource] = []
        var seen: Set<String> = []

        for block in videoBlocks(in: html) {
            guard let openTagEnd = block.firstIndex(of: ">") else { continue }
            let openTag = String(block[block.startIndex...openTagEnd])
            let attributes = Self.attributes(in: openTag)
            guard !isDRMMarked(tag: openTag, attributes: attributes) else { continue }

            let posterTitle = attributes["poster"].flatMap { Self.title(from: $0, relativeTo: baseURL) }
            var candidates: [(value: String, title: String?)] = []

            for key in ["src", "data-src"] {
                if let value = attributes[key] {
                    candidates.append((value, posterTitle))
                }
            }

            for sourceTag in sourceTags(in: block) {
                let sourceAttributes = Self.attributes(in: sourceTag)
                guard !isDRMMarked(tag: sourceTag, attributes: sourceAttributes) else { continue }
                let sourceTitle = sourceAttributes["poster"]
                    .flatMap { Self.title(from: $0, relativeTo: baseURL) } ?? posterTitle
                for key in ["src", "data-src"] {
                    if let value = sourceAttributes[key] {
                        candidates.append((value, sourceTitle))
                    }
                }
            }

            for candidate in candidates {
                guard let absoluteURL = Self.makeURL(from: candidate.value, relativeTo: baseURL),
                      absoluteURL.isHTTP else {
                    continue
                }
                let key = absoluteURL.absoluteString
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                sources.append(
                    VideoSource(
                        url: absoluteURL,
                        kind: mediaKind(from: absoluteURL) ?? .video,
                        title: candidate.title
                    )
                )
            }
        }
        return sources
    }

    /// 找出所有 `<video ...> ... </video>` 片段；未闭合时延伸到文末。
    private static func videoBlocks(in html: String) -> [String] {
        var blocks: [String] = []
        var searchStart = html.startIndex

        while searchStart < html.endIndex,
              let openStart = html[searchStart...].range(of: "<video", options: .caseInsensitive) {
            let blockStart = openStart.lowerBound
            let afterOpenTag = openStart.upperBound
            guard let tagEnd = html[afterOpenTag...].firstIndex(of: ">") else { break }
            let afterTag = html.index(after: tagEnd)
            let closeRange = html[afterTag...].range(of: "</video>", options: .caseInsensitive)
            let blockEnd = closeRange?.upperBound ?? html.endIndex
            blocks.append(String(html[blockStart..<blockEnd]))
            searchStart = blockEnd
        }
        return blocks
    }

    /// 找出一段 `<video>` 块内所有 `<source ...>` 标签文本。
    private static func sourceTags(in block: String) -> [String] {
        var tags: [String] = []
        var searchStart = block.startIndex

        while searchStart < block.endIndex,
              let openStart = block[searchStart...].range(of: "<source", options: .caseInsensitive) {
            let tagStart = openStart.lowerBound
            let afterOpen = openStart.upperBound
            guard let tagEnd = block[afterOpen...].firstIndex(of: ">") else { break }
            tags.append(String(block[tagStart...tagEnd]))
            searchStart = block.index(after: tagEnd)
        }
        return tags
    }

    /// 解析标签属性（双引号 / 单引号），属性名统一小写。
    private static func attributes(in tag: String) -> [String: String] {
        var result: [String: String] = [:]
        for pattern in [doubleQuotedAttributePattern, singleQuotedAttributePattern] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let nsTag = tag as NSString
            regex.enumerateMatches(in: tag, range: NSRange(location: 0, length: nsTag.length)) { match, _, _ in
                guard let match else { return }
                let name = nsTag.substring(with: match.range(at: 1)).lowercased()
                let value = nsTag.substring(with: match.range(at: 2))
                if result[name] == nil {
                    result[name] = value
                }
            }
        }
        return result
    }

    /// 不绕过 DRM：带 `encrypted` / `eme` / `drm` 标记的视频块或来源不提取。
    /// 同时识别无值的布尔属性形式（如 `<video encrypted>`）。
    private static func isDRMMarked(tag: String, attributes: [String: String]) -> Bool {
        let hasAttributeValue = attributes.keys.contains { key in
            key == "encrypted" || key == "eme" || key.contains("drm")
        }
        if hasAttributeValue { return true }

        let lowercasedTag = tag.lowercased()
        let booleanMarkers = [
            #"encrypted(\s|=|>)"#,
            #"data-drm"#,
        ]
        return booleanMarkers.contains { pattern in
            lowercasedTag.range(of: pattern, options: .regularExpression) != nil
        }
    }

    // MARK: - URL 与标题辅助

    private static func makeURL(from rawValue: String, relativeTo baseURL: URL) -> URL? {
        let decoded = decodeHTMLEntities(rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !decoded.isEmpty else { return nil }
        return URL(string: decoded, relativeTo: baseURL)?.absoluteURL
    }

    private static func title(from rawValue: String, relativeTo baseURL: URL) -> String? {
        guard let url = makeURL(from: rawValue, relativeTo: baseURL) else { return nil }
        return title(from: url)
    }

    private static func title(from url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        let fileName = (name.isEmpty ? url.lastPathComponent : name)
            .removingPercentEncoding ?? url.absoluteString
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (url.host ?? url.absoluteString) : trimmed
    }

    private static func pageTitle(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<title\b[^>]*>(.*?)</title>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let nsHTML = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: nsHTML.length)) else {
            return nil
        }
        let rawTitle = nsHTML.substring(with: match.range(at: 1))
        let stripped = rawTitle.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let trimmed = decodeHTMLEntities(stripped).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        for (entity, replacement) in htmlEntities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        guard let regex = try? NSRegularExpression(pattern: #"&#(\d+);"#) else { return result }
        let nsResult = result as NSString
        let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsResult.length)).reversed()
        let expanded = NSMutableString(string: result)
        for match in matches {
            guard let code = Int(nsResult.substring(with: match.range(at: 1))),
                  let scalar = Unicode.Scalar(code) else {
                continue
            }
            expanded.replaceCharacters(in: match.range, with: String(scalar))
        }
        return expanded as String
    }

    // MARK: - 常量

    private static let doubleQuotedAttributePattern = #"([a-zA-Z][a-zA-Z0-9-]*)\s*=\s*"([^"]*)""#
    private static let singleQuotedAttributePattern = #"([a-zA-Z][a-zA-Z0-9-]*)\s*=\s*'([^']*)'"#

    private static let htmlEntities: [(String, String)] = [
        ("&amp;", "&"),
        ("&lt;", "<"),
        ("&gt;", ">"),
        ("&quot;", "\""),
        ("&apos;", "'"),
        ("&#39;", "'"),
        ("&nbsp;", " "),
    ]

    private struct VideoSource {
        let url: URL
        let kind: MediaItem.Kind
        let title: String?
    }
}

/// `MediaExtractor` 提取失败的错误。
public enum MediaExtractionError: LocalizedError, Sendable {
    case unsupportedURLScheme(String)
    case invalidResponse
    case httpError(statusCode: Int)
    case invalidHTML

    public var errorDescription: String? {
        switch self {
        case .unsupportedURLScheme(let scheme):
            "不支持的 URL 协议：\(scheme)"
        case .invalidResponse:
            "服务器返回了无效响应"
        case .httpError(let statusCode):
            "服务器返回错误（HTTP \(statusCode)）"
        case .invalidHTML:
            "无法解析页面内容"
        }
    }
}

private extension URL {
    var isHTTP: Bool {
        guard let scheme else { return false }
        let normalized = scheme.lowercased()
        return normalized == "http" || normalized == "https"
    }
}
