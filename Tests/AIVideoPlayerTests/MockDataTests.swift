import Foundation
import Testing
@testable import AIVideoPlayer

/// Mock 数据健壮性：URL 必须能安全构造、必须为 https、且不含未编码的非 ASCII 字符。
struct MockDataTests {

    @Test func mockRemoteFileURLsAreValid() {
        #expect(!MockRemoteFiles.contents.isEmpty)
        for file in MockRemoteFiles.contents {
            #expect(file.url.scheme == "https")
            #expect(file.url.host != nil)
            #expect(file.url.absoluteString.unicodeScalars.allSatisfy { $0.isASCII })
        }
    }

    @Test func mockDirectoryURLsKeepChineseNames() {
        let folder = MockRemoteFiles.contents.first { $0.kind == .folder && $0.name == "电影" }
        #expect(folder != nil)
        #expect(folder?.url.path == "/dav/电影")
    }

    @Test func mockSampleMediaItemURLIsValid() {
        let item = MockRemoteFiles.sampleMediaItem
        #expect(item.url.scheme == "https")
        #expect(item.url.absoluteString.unicodeScalars.allSatisfy { $0.isASCII })
    }
}
