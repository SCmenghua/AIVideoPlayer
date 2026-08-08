import Foundation

/// WebDAV PROPFIND 响应的单个资源。
public struct WebDAVResource: Sendable, Equatable {
    public let href: String
    public let isCollection: Bool
    public let displayName: String?
    public let contentLength: Int64?
    public let lastModified: Date?

    public init(
        href: String,
        isCollection: Bool,
        displayName: String?,
        contentLength: Int64?,
        lastModified: Date?
    ) {
        self.href = href
        self.isCollection = isCollection
        self.displayName = displayName
        self.contentLength = contentLength
        self.lastModified = lastModified
    }
}

/// 解析 WebDAV 207 Multi-Status（PROPFIND 响应）。
/// 非 Sendable，仅在 WebDAVFileBrowser 内部同步使用。
final class WebDAVMultistatusParser: NSObject, XMLParserDelegate {
    private(set) var resources: [WebDAVResource] = []

    private var currentResource: ResourceBuilder?
    private var collectedCharacters = ""

    func parse(data: Data) throws -> [WebDAVResource] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw WebDAVError.invalidResponse
        }
        return resources
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch localName(elementName, qualifiedName: qName) {
        case "response":
            currentResource = ResourceBuilder()
        case "collection":
            currentResource?.isCollection = true
        default:
            break
        }
        collectedCharacters = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        collectedCharacters += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch localName(elementName, qualifiedName: qName) {
        case "href":
            currentResource?.href = collectedCharacters.trimmingCharacters(in: .whitespacesAndNewlines)
        case "displayname":
            currentResource?.displayName = collectedCharacters.trimmingCharacters(in: .whitespacesAndNewlines)
        case "getcontentlength":
            currentResource?.contentLength = Int64(collectedCharacters.trimmingCharacters(in: .whitespacesAndNewlines))
        case "getlastmodified":
            currentResource?.lastModified = WebDAVDateParser.date(from: collectedCharacters)
        case "response":
            if let resource = currentResource, !resource.href.isEmpty {
                resources.append(resource.finalize())
            }
            currentResource = nil
        default:
            break
        }
        collectedCharacters = ""
    }

    /// 兼容带命名空间前缀（d:response）与不带前缀（response）两种写法。
    private func localName(_ elementName: String, qualifiedName: String?) -> String {
        for candidate in [qualifiedName, elementName] {
            guard let candidate else { continue }
            if candidate.contains(":") {
                return candidate.split(separator: ":").last.map(String.init) ?? candidate
            }
        }
        return elementName
    }
}

private struct ResourceBuilder {
    var href = ""
    var isCollection = false
    var displayName: String?
    var contentLength: Int64?
    var lastModified: Date?

    func finalize() -> WebDAVResource {
        WebDAVResource(
            href: href,
            isCollection: isCollection,
            displayName: displayName,
            contentLength: contentLength,
            lastModified: lastModified
        )
    }
}

/// WebDAV 日期解析：兼容 RFC 1123 与 ISO 8601 常见格式。
enum WebDAVDateParser {
    static func date(from string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFractional.date(from: trimmed) { return date }

        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]
        if let date = isoPlain.date(from: trimmed) { return date }

        let rfc1123 = DateFormatter()
        rfc1123.locale = Locale(identifier: "en_US_POSIX")
        rfc1123.timeZone = TimeZone(identifier: "GMT")
        rfc1123.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return rfc1123.date(from: trimmed)
    }
}

/// WebDAV 操作错误。
public enum WebDAVError: LocalizedError, Sendable {
    case notConnected
    case invalidCredentials
    case serverError(statusCode: Int)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            "尚未连接服务器"
        case .invalidCredentials:
            "凭据无效或服务器拒绝访问"
        case .serverError(let statusCode):
            "服务器返回错误（HTTP \(statusCode)）"
        case .invalidResponse:
            "服务器响应无法解析"
        }
    }
}
