import Foundation
import Testing
import Translation
@testable import AIVideoPlayer

@MainActor
struct FastNMTTranslatorTests {

    @Test func metadata() {
        let translator = FastNMTTranslator()
        #expect(translator.providerID == .fastNMT)
        #expect(translator.displayName == TranslationProviderCatalog.fastNMT.displayName)
        #expect(translator.isFullyLocal)
        #expect(!translator.supportsContextPolish)
        #expect(translator.isReady)
    }

    @Test func translatesWhenLanguageInstalled() async throws {
        let translator = FastNMTTranslator(
            availabilityCheck: { _, _ in .installed },
            translateText: { text, _, _ in "你好" }
        )

        let result = try await translator.translate(
            "Hello", from: "en", to: "zh-Hans", context: nil
        )

        #expect(result == "你好")
    }

    @Test func throwsWhenLanguagePackMissing() async {
        let translator = FastNMTTranslator(
            availabilityCheck: { _, _ in .supported },
            translateText: { _, _, _ in "should not be called" }
        )

        do {
            _ = try await translator.translate("Hello", from: "en", to: "zh-Hans", context: nil)
            Issue.record("expected language pack error")
        } catch let error as FastNMTError {
            #expect(error == .languagePackNotInstalled)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func throwsWhenLanguagePairUnsupported() async {
        let translator = FastNMTTranslator(
            availabilityCheck: { _, _ in .unsupported },
            translateText: { _, _, _ in "should not be called" }
        )

        do {
            _ = try await translator.translate("Hello", from: "en", to: "zh-Hans", context: nil)
            Issue.record("expected unsupported error")
        } catch let error as FastNMTError {
            #expect(error == .unsupportedLanguagePair)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func throwsOnEmptyResult() async {
        let translator = FastNMTTranslator(
            availabilityCheck: { _, _ in .installed },
            translateText: { _, _, _ in "" }
        )

        do {
            _ = try await translator.translate("Hello", from: "en", to: "zh-Hans", context: nil)
            Issue.record("expected empty result error")
        } catch let error as FastNMTError {
            #expect(error == .emptyResult)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}
