// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import Foundation

/// Reads and writes the personal dictionary as JSON, with terms and snippets in separate lists:
///
///     {
///       "format": "typist-dictionary",
///       "version": 1,
///       "terms": [
///         { "heard_as": "кубернетус", "write_as": "Kubernetes" },
///         { "write_as": "Docker Compose" }
///       ],
///       "snippets": [
///         { "say": "мой адрес", "insert": "Улица Ленина, 1\nМосква" }
///       ]
///     }
///
/// `heard_as` is optional: a term without it only hints speech recognition.
public enum DictionaryFile {
    public static let format = "typist-dictionary"
    public static let version = 1

    public struct ImportError: Error, CustomStringConvertible {
        public let description: String
    }

    struct Document: Codable {
        var format: String?
        var version: Int?
        var terms: [Term]?
        var snippets: [Snippet]?
    }

    struct Term: Codable {
        var heardAs: String?
        var writeAs: String

        enum CodingKeys: String, CodingKey {
            case heardAs = "heard_as"
            case writeAs = "write_as"
        }
    }

    struct Snippet: Codable {
        var say: String
        var insert: String
    }

    public static func export(_ entries: [Replacement]) throws -> Data {
        let document = Document(
            format: format, version: version,
            terms: entries.filter { $0.kind == .term }.map {
                Term(heardAs: $0.from.isEmpty ? nil : $0.from, writeAs: $0.to)
            },
            snippets: entries.filter { $0.kind == .snippet }.map { Snippet(say: $0.from, insert: $0.to) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    public static func parse(_ data: Data) throws -> [Replacement] {
        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: data)
        } catch {
            throw ImportError(description: "not a Typist dictionary: \(describe(error))")
        }
        if let format = document.format, format != Self.format {
            throw ImportError(description: "this is a “\(format)” file, not a Typist dictionary")
        }
        if let version = document.version, version > Self.version {
            throw ImportError(description: "made by a newer Typist (version \(version))")
        }
        guard document.terms != nil || document.snippets != nil else {
            throw ImportError(description: "the file has neither “terms” nor “snippets”")
        }
        let terms = (document.terms ?? []).map { Replacement(kind: .term, from: $0.heardAs ?? "", to: $0.writeAs) }
        let snippets = (document.snippets ?? []).map { Replacement(kind: .snippet, from: $0.say, to: $0.insert) }
        return terms + snippets
    }

    private static func describe(_ error: any Error) -> String {
        switch error as? DecodingError {
        case .keyNotFound(let key, let context):
            "\(location(context.codingPath)) has no “\(key.stringValue)”"
        case .dataCorrupted(let context) where context.codingPath.isEmpty:
            "the file is not valid JSON"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            "\(location(context.codingPath)): \(context.debugDescription)"
        default:
            String(describing: error)
        }
    }

    /// "term 3" or "snippet 1" from a decoding path like terms[2].
    private static func location(_ path: [any CodingKey]) -> String {
        let list = path.first?.stringValue == "snippets" ? "snippet" : "term"
        return path.compactMap(\.intValue).first.map { "\(list) \($0 + 1)" } ?? "the file"
    }
}
