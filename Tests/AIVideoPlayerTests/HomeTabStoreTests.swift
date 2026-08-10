import Foundation
import Testing
@testable import AIVideoPlayer

struct HomeTabStoreTests {

    @Test func homeTabStoreAddRemove() throws {
        let store = UserDefaultsHomeTabStore(suiteName: "test.homeTabs.\(UUID().uuidString)")
        let url = try #require(URL(string: "https://example.com"))
        let tab = HomeTab(url: url, title: "Example")

        try store.addTab(tab)
        #expect(store.loadTabs().count == 1)
        #expect(store.loadTabs().first?.title == "Example")

        try store.removeTab(id: tab.id)
        #expect(store.loadTabs().isEmpty)
    }

    @Test func homeTabStoreDeduplicatesByURL() throws {
        let store = UserDefaultsHomeTabStore(suiteName: "test.homeTabs.\(UUID().uuidString)")
        let url = try #require(URL(string: "https://example.com"))

        try store.addTab(HomeTab(url: url, title: "First"))
        try store.addTab(HomeTab(url: url, title: "Second"))

        let tabs = store.loadTabs()
        #expect(tabs.count == 1)
        #expect(tabs.first?.title == "Second")
    }
}
