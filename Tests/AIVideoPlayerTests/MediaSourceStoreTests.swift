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

    @Test func pickedFileStoreAddRemove() throws {
        let store = UserDefaultsPickedFileStore(suiteName: "test.pickedFiles.\(UUID().uuidString)")
        let file = PickedVideoFile(name: "clip.mov", bookmarkData: Data([1, 2, 3]))

        try store.addFile(file)
        #expect(store.loadFiles().count == 1)
        #expect(store.loadFiles().first?.name == "clip.mov")

        try store.removeFile(id: file.id)
        #expect(store.loadFiles().isEmpty)
    }
}
