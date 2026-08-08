import Foundation

/// Phase 1 占位数据。Phase 2 用 WebDAV / SMB / FTP 的真实列表替换。
public enum MockRemoteFiles {
    public static let contents: [RemoteFile] = [
        RemoteFile(
            name: "电影",
            url: makeURL("https://nas.example.local/dav/电影"),
            kind: .folder,
            connection: .webdav,
            modifiedAt: date(daysAgo: 2)
        ),
        RemoteFile(
            name: "剧集",
            url: makeURL("https://nas.example.local/dav/剧集"),
            kind: .folder,
            connection: .webdav,
            modifiedAt: date(daysAgo: 4)
        ),
        RemoteFile(
            name: "纪录片",
            url: makeURL("https://nas.example.local/dav/纪录片"),
            kind: .folder,
            connection: .webdav,
            modifiedAt: date(daysAgo: 9)
        ),
        RemoteFile(
            name: "Big Buck Bunny",
            url: makeURL("https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"),
            kind: .video,
            connection: .webdav,
            size: 158_008_574,
            modifiedAt: date(daysAgo: 1)
        ),
        RemoteFile(
            name: "Elephants Dream",
            url: makeURL("https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4"),
            kind: .video,
            connection: .webdav,
            size: 169_189_118,
            modifiedAt: date(daysAgo: 1)
        ),
        RemoteFile(
            name: "For Bigger Blazes",
            url: makeURL("https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4"),
            kind: .video,
            connection: .smb,
            size: 2_595_446,
            modifiedAt: date(daysAgo: 6)
        ),
    ]

    /// 播放器占位页使用的示例媒体。
    public static let sampleMediaItem = MediaItem(
        title: "Big Buck Bunny",
        url: makeURL("https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"),
        kind: .video,
        source: .remote
    )

    private static func date(daysAgo: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
    }

    /// 安全构造 Mock URL：先对非 ASCII 字符做百分号编码（使用 URL 允许字符集），
    /// 再构造。若仍失败说明是编程错误，以显式断言终止，绝不强制解包。
    private static func makeURL(_ string: String) -> URL {
        let encoded = string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? string
        guard let url = URL(string: encoded) else {
            preconditionFailure("无法构造 Mock URL：\(string)")
        }
        return url
    }
}
