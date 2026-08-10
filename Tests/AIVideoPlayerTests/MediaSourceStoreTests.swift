import Foundation
import Testing
@testable import AIVideoPlayer

struct MediaSourceStoreTests {

    @Test func mediaSourceStoreAddRemove() throws {
        let store = UserDefaultsMediaSourceStore(suiteName: "test.mediaSources.\(UUID().uuidString)")
        let source = MediaSource(name: "NAS", kind: .webDAV)

        try store.addSource(source)
        #expect(store.loadSources().count == 1)
        #expect(store.loadSources().first?.name == "NAS")

        try store.removeSource(id: source.id)
        #expect(store.loadSources().isEmpty)
    }

}
