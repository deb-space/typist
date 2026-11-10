// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import Foundation
import Testing

@testable import TypistCore

@Suite struct DictionaryTests {
    @Test func countsUses() {
        let kubernetes = Replacement(from: "кубернетус", to: "Kubernetes")
        let helm = Replacement(from: "хельм", to: "Helm")
        let result = TextCleanup(replacements: [kubernetes, helm])
            .applyCountingUses(to: "Кубернетус и ещё раз кубернетус.")
        #expect(result.text == "Kubernetes и ещё раз Kubernetes.")
        #expect(result.uses == [kubernetes.id: 2])
    }

    @Test func expandsSnippetsWithNewlines() {
        let snippet = Replacement(kind: .snippet, from: "мой адрес", to: "Улица Ленина, 1\nМосква")
        #expect(TextCleanup(replacements: [snippet]).apply(to: "Мой адрес") == "Улица Ленина, 1\nМосква")
    }

    @Test func insertsDictionaryTextExactlyAsWritten() {
        let cleanup = TextCleanup(replacements: [
            Replacement(from: "моя почта", to: "name@gmail.com"),
            Replacement(from: "айфон", to: "iPhone"),
        ])
        #expect(cleanup.apply(to: "Напиши мне на моя почта.") == "Напиши мне на name@gmail.com.")
        #expect(cleanup.apply(to: "айфон сел.") == "iPhone сел.")
    }

    @Test func doesNotCapitalizeAfterAPeriodInsideAWord() {
        #expect(
            TextCleanup().apply(to: "открой example.com и версию v1.2 сейчас")
                == "Открой example.com и версию v1.2 сейчас")
        #expect(TextCleanup().apply(to: "готово. теперь дальше") == "Готово. Теперь дальше")
    }

    @Test func decodesEntriesSavedBeforeKinds() throws {
        let json = #"[{"id":"2A2EBF5E-0000-4000-8000-000000000001","from":"хельм","to":"Helm"}]"#
        let entries = try JSONDecoder().decode([Replacement].self, from: Data(json.utf8))
        #expect(entries.first?.kind == .term)
    }

    @Test func fileRoundTripsSnippetsWithNewlinesAndQuotes() throws {
        let entries = [
            Replacement(kind: .term, from: "кубернетус", to: "Kubernetes"),
            Replacement(kind: .term, from: "", to: "Docker Compose"),
            Replacement(kind: .snippet, from: "подпись", to: "С уважением,\n\"deb-space\""),
        ]
        let parsed = try DictionaryFile.parse(DictionaryFile.export(entries))
        #expect(parsed.map(\.kind) == entries.map(\.kind))
        #expect(parsed.map(\.from) == entries.map(\.from))
        #expect(parsed.map(\.to) == entries.map(\.to))
    }

    @Test func fileKeepsTermsAndSnippetsInSeparateLists() throws {
        let entries = [
            Replacement(kind: .snippet, from: "мой адрес", to: "Улица Ленина, 1"),
            Replacement(kind: .term, from: "хельм", to: "Helm"),
        ]
        let json = try #require(String(data: DictionaryFile.export(entries), encoding: .utf8))
        #expect(json.contains(#""terms""#) && json.contains(#""snippets""#))
        #expect(json.contains(#""say" : "мой адрес""#))
        #expect(!json.contains(#""kind""#))
    }

    @Test func fileAcceptsOnlyOneListAndTermsWithoutHeardAs() throws {
        let json = #"{"terms":[{"heard_as":"хельм","write_as":"Helm"},{"write_as":"Kubernetes"}]}"#
        let parsed = try DictionaryFile.parse(Data(json.utf8))
        #expect(parsed.map(\.to) == ["Helm", "Kubernetes"])
        #expect(parsed.map(\.from) == ["хельм", ""])
        #expect(parsed.allSatisfy { $0.kind == .term })
    }

    @Test func fileRejectsOtherFiles() {
        #expect(throws: DictionaryFile.ImportError.self) { try DictionaryFile.parse(Data("not json".utf8)) }
        #expect(throws: DictionaryFile.ImportError.self) {
            try DictionaryFile.parse(Data(#"{"format":"something-else","entries":[]}"#.utf8))
        }
        #expect(throws: DictionaryFile.ImportError.self) {
            try DictionaryFile.parse(Data(#"{"terms":[{"heard_as":"a"}]}"#.utf8))
        }
        #expect(throws: DictionaryFile.ImportError.self) { try DictionaryFile.parse(Data("{}".utf8)) }
    }
}
