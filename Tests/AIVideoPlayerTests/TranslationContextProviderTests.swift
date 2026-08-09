import Foundation
import Testing
@testable import AIVideoPlayer

@MainActor
struct TranslationContextProviderTests {

    @Test func recordsUpToMaxEntries() {
        let provider = TranslationContextProvider(maxEntries: 3)
        for index in 0..<5 {
            provider.record(original: "o\(index)", translated: "t\(index)")
        }

        #expect(provider.recentEntries.count == 3)
        #expect(provider.recentEntries.first?.originalText == "o2")
        #expect(provider.recentEntries.last?.originalText == "o4")
    }

    @Test func truncatesLongLines() {
        let provider = TranslationContextProvider(
            maxEntries: 10,
            maxCharactersPerEntry: 10,
            maxTotalCharacters: 1000
        )
        provider.record(
            original: String(repeating: "a", count: 50),
            translated: String(repeating: "b", count: 50)
        )

        let context = provider.makeContext()
        #expect(!context.isEmpty)
        #expect(context.text.count <= 10)
        #expect(context.text.hasPrefix("aaaaa"))
    }

    @Test func respectsTotalBudgetKeepingNewest() {
        let provider = TranslationContextProvider(
            maxEntries: 10,
            maxCharactersPerEntry: 100,
            maxTotalCharacters: 9
        )
        provider.record(original: "A", translated: "甲")
        provider.record(original: "B", translated: "乙")
        provider.record(original: "C", translated: "丙")

        let context = provider.makeContext()
        #expect(context.text.contains("C"))
        #expect(!context.text.contains("A"))
        #expect(!context.text.contains("B"))
    }

    @Test func emptyWhenNoEntries() {
        let provider = TranslationContextProvider()
        #expect(!provider.hasRecentEntries)
        #expect(provider.makeContext().isEmpty)
    }

    @Test func resetClearsHistory() {
        let provider = TranslationContextProvider()
        provider.record(original: "A", translated: "甲")
        provider.reset()
        #expect(!provider.hasRecentEntries)
        #expect(provider.makeContext().isEmpty)
    }
}
