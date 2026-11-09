// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import Testing

@testable import TypistCore

@Suite struct TextCleanupTests {
    let cleanup = TextCleanup()

    @Test(arguments: [
        ("Давай перенесём релиз на четверг. Продолжение следует...", "Давай перенесём релиз на четверг."),
        ("Продолжение следует…", ""),
        ("Хорошо. Субтитры создавал DimaTorzok", "Хорошо."),
        ("Let's ship it. Thanks for watching!", "Let's ship it."),
    ])
    func removesPhantomPhrases(input: String, expected: String) {
        #expect(cleanup.apply(to: input) == expected)
    }

    @Test func keepsAPlainThankYou() {
        #expect(cleanup.apply(to: "Thank you.") == "Thank you.")
        #expect(cleanup.apply(to: "Спасибо.") == "Спасибо.")
    }

    @Test(arguments: [
        ("Эм, давай созвонимся завтра.", "Давай созвонимся завтра."),
        ("Я думаю, ээ, что это сработает.", "Я думаю, что это сработает."),
        ("So, um, we should, uh, ship it.", "So, we should, ship it."),
        ("Хм.", ""),
    ])
    func removesFillers(input: String, expected: String) {
        #expect(cleanup.apply(to: input) == expected)
    }

    @Test func keepsWordsThatContainFillers() {
        #expect(cleanup.apply(to: "Эмиль сделал эмодзи, а Umberto — ummo.") == "Эмиль сделал эмодзи, а Umberto — ummo.")
    }

    @Test(arguments: [
        ("я я думаю, что это работает", "Я думаю, что это работает"),
        ("I, I think the the build is fine.", "I think the build is fine."),
        ("и и и потом", "И потом"),
    ])
    func removesStutters(input: String, expected: String) {
        #expect(cleanup.apply(to: input) == expected)
    }

    @Test func keepsIntentionalRepeats() {
        #expect(cleanup.apply(to: "Да да, very very good.") == "Да да, very very good.")
        #expect(cleanup.apply(to: "I know that that works.") == "I know that that works.")
    }

    @Test func appliesReplacementsAsWholeWordsIgnoringCase() {
        let cleanup = TextCleanup(replacements: [
            Replacement(from: "кубернетус", to: "Kubernetes"),
            Replacement(from: "хельм", to: "Helm"),
            Replacement(from: "докер компоуз", to: "Docker Compose"),
        ])
        #expect(
            cleanup.apply(to: "Надо поставить Кубернетус с хельм и докер компоуз.")
                == "Надо поставить Kubernetes с Helm и Docker Compose.")
        // Not inside other words.
        #expect(cleanup.apply(to: "Хельмут пришёл.") == "Хельмут пришёл.")
    }

    @Test func replacementTargetIsLiteral() {
        let cleanup = TextCleanup(replacements: [Replacement(from: "доллар", to: "$1 USD")])
        #expect(cleanup.apply(to: "Один доллар.") == "Один $1 USD.")
    }

    @Test func ignoresEmptyReplacements() {
        let cleanup = TextCleanup(replacements: [Replacement(from: "", to: "x"), Replacement(from: "a", to: " ")])
        #expect(cleanup.apply(to: "a test") == "A test")
    }

    @Test func leavesCleanTextAlone() {
        let text = "Давай перенесём релиз на четверг. QA closed one blocker, and the fix is in review."
        #expect(cleanup.apply(to: text) == text)
    }

    @Test func canBeTurnedOffPartly() {
        let cleanup = TextCleanup(removesFillers: false, removesStutters: false)
        #expect(cleanup.apply(to: "Эм, я я тут.") == "Эм, я я тут.")
    }
}
