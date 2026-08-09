import Foundation

/// WebDAV 目录浏览实现（PROPFIND + Basic 认证）。
/// 会话状态（配置与凭据）由 actor 隔离；disconnect 清除内存中的凭据。
public actor WebDAVFileBrowser: RemoteFileBrowsing {
    private let session: URLSession
    private var profile: RemoteServerProfile?
    private var credentials: RemoteCredentials?

    public init(configuration: URLSessionConfiguration = .default) {
        self.session = URLSession(configuration: configuration)
    }

    public func connect(to profile: RemoteServerProfile, credentials: RemoteCredentials) async throws {
        self.profile = profile
        self.credentials = credentials
        // 用根目录 PROPFIND 验证凭据；失败即视为连接失败。
        do {
            _ = try await propfind(url: profile.rootURL)
        } catch {
            // 连接失败时清除内存中的会话状态，避免残留凭据被后续 listDirectory 使用。
            self.profile = nil
            self.credentials = nil
            throw error
        }
    }

    public func listDirectory(at url: URL) async throws -> [RemoteFile] {
        guard profile != nil, credentials != nil else {
            throw WebDAVError.notConnected
        }
        let resources = try await propfind(url: url)
        return mapResources(resources, requestURL: url)
    }

    public func disconnect() async {
        profile = nil
        credentials = nil
    }

    // MARK: - Private

    private func propfind(url: URL) async throws -> [WebDAVResource] {
        guard let credentials else { throw WebDAVError.notConnected }

        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.timeoutInterval = 30
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "Basic " + Self.basicAuth(username: credentials.username, password: credentials.password),
            forHTTPHeaderField: "Authorization"
        )
        request.httpBody = Self.propfindBody

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WebDAVError.invalidResponse
        }
        switch http.statusCode {
        case 200, 207:
            return try WebDAVMultistatusParser().parse(data: data)
        case 401, 403:
            throw WebDAVError.invalidCredentials
        default:
            throw WebDAVError.serverError(statusCode: http.statusCode)
        }
    }

    private func mapResources(_ resources: [WebDAVResource], requestURL: URL) -> [RemoteFile] {
        let normalizedRequest = Self.normalizedDirectoryURL(requestURL)
        return resources.compactMap { resource in
            guard let resourceURL = Self.resolveURL(resource.href, relativeTo: requestURL) else {
                return nil
            }
            // 排除请求目录自身。
            if Self.normalizedDirectoryURL(resourceURL) == normalizedRequest {
                return nil
            }
            let name: String
            if let displayName = resource.displayName, !displayName.isEmpty {
                name = displayName
            } else if !resourceURL.lastPathComponent.isEmpty {
                name = resourceURL.lastPathComponent
            } else {
                name = resource.href
            }
            return RemoteFile(
                name: name,
                url: resourceURL,
                kind: .infer(isCollection: resource.isCollection, url: resourceURL),
                connection: .webdav,
                size: resource.contentLength,
                modifiedAt: resource.lastModified
            )
        }
    }

    private static func resolveURL(_ href: String, relativeTo base: URL) -> URL? {
        URL(string: href, relativeTo: base)?.absoluteURL
    }

    private static func normalizedDirectoryURL(_ url: URL) -> String {
        var value = url.absoluteString
        if value.hasSuffix("/") {
            value.removeLast()
        }
        return value.lowercased()
    }

    private static func basicAuth(username: String, password: String) -> String {
        Data("\(username):\(password)".utf8).base64EncodedString()
    }

    private static let propfindBody = Data(
        """
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:">
          <d:prop>
            <d:resourcetype/>
            <d:displayname/>
            <d:getcontentlength/>
            <d:getlastmodified/>
          </d:prop>
        </d:propfind>
        """.utf8
    )
}
