import Foundation
import Testing
@testable import AIVideoPlayer

struct WebDAVParserTests {

    @Test func parsesPrefixedMultistatus() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:multistatus xmlns:d="DAV:">
          <d:response>
            <d:href>/dav/</d:href>
            <d:propstat>
              <d:prop>
                <d:displayname>dav</d:displayname>
                <d:resourcetype><d:collection/></d:resourcetype>
              </d:prop>
            </d:propstat>
          </d:response>
          <d:response>
            <d:href>/dav/Big%20Buck%20Bunny.mp4</d:href>
            <d:propstat>
              <d:prop>
                <d:displayname>Big Buck Bunny.mp4</d:displayname>
                <d:getcontentlength>158008574</d:getcontentlength>
                <d:getlastmodified>Mon, 12 Aug 2024 10:20:30 GMT</d:getlastmodified>
              </d:prop>
            </d:propstat>
          </d:response>
        </d:multistatus>
        """

        let resources = try WebDAVMultistatusParser().parse(data: Data(xml.utf8))

        #expect(resources.count == 2)
        #expect(resources[0].isCollection)
        #expect(resources[0].displayName == "dav")
        #expect(resources[1].isCollection == false)
        #expect(resources[1].displayName == "Big Buck Bunny.mp4")
        #expect(resources[1].contentLength == 158_008_574)
        #expect(resources[1].lastModified != nil)
    }

    @Test func parsesUnprefixedElements() throws {
        let xml = """
        <?xml version="1.0"?>
        <multistatus xmlns="DAV:">
          <response>
            <href>/dav/folder/</href>
            <propstat>
              <prop>
                <resourcetype><collection/></resourcetype>
              </prop>
            </propstat>
          </response>
        </multistatus>
        """

        let resources = try WebDAVMultistatusParser().parse(data: Data(xml.utf8))

        #expect(resources.count == 1)
        #expect(resources[0].isCollection)
        #expect(resources[0].href == "/dav/folder/")
    }

    @Test func invalidXMLThrows() {
        #expect(throws: WebDAVError.self) {
            _ = try WebDAVMultistatusParser().parse(data: Data("<broken".utf8))
        }
    }
}
