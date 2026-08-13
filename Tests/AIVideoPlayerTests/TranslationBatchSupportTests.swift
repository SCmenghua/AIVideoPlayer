import Foundation
import Testing
@testable import AIVideoPlayer

struct TranslationBatchSupportTests {

    @Test func promptIncludesTargetAndCount() {
        let prompt = TranslationBatchPrompt.build(
            texts: ["你好", "世界"],
            targetLanguage: "en",
            context: nil
        )
        #expect(prompt.contains("2"))
        #expect(prompt.contains("English"))
        #expect(prompt.contains("你好"))
        #expect(prompt.contains("世界"))
    }

    @Test func parseJSONArray() throws {
        let result = try TranslationBatchResponse.parse(
            #"["Hello","World"]"#,
            expectedCount: 2
        )
        #expect(result == ["Hello", "World"])
    }

    @Test func parseLineDelimitedFallback() throws {
        let result = try TranslationBatchResponse.parse(
            "1. Hello\n2. World",
            expectedCount: 2
        )
        #expect(result == ["Hello", "World"])
    }

    @Test func parseMismatchedCountThrows() {
        #expect(throws: TranslationBatchError.self) {
            _ = try TranslationBatchResponse.parse(
                #"["Hello"]"#,
                expectedCount: 2
            )
        }
    }

    @Test func parseEmptyThrows() {
        #expect(throws: TranslationBatchError.self) {
            _ = try TranslationBatchResponse.parse("", expectedCount: 1)
        }
    }
}