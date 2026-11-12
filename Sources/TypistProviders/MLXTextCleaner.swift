// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers
import TypistCore

/// Cleans up dictated text with a small language model running on this Mac's GPU (MLX).
///
/// The model is downloaded once, loaded on demand and can be unloaded to give its memory back.
public actor MLXTextCleaner {
    public enum State: Sendable, Equatable {
        case idle
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    public enum CleanerError: Error, CustomStringConvertible {
        case notLoaded
        case timedOut
        public var description: String {
            switch self {
            case .notLoaded: "the language model is not loaded"
            case .timedOut: "the language model took too long"
            }
        }
    }

    public let repo: String
    private let download: HuggingFaceDownload
    private var container: ModelContainer?
    private var isPreparing = false
    private var prefix = PromptPrefix()

    /// Where a model is kept under `modelsDirectory`.
    public static func folder(of repo: String, in modelsDirectory: URL) -> URL {
        modelsDirectory.appending(path: "llm/\(repo)", directoryHint: .isDirectory)
    }

    public static func isDownloaded(_ repo: String, revision: String, in modelsDirectory: URL) -> Bool {
        HuggingFaceDownload(repo: repo, revision: revision, folder: folder(of: repo, in: modelsDirectory)).isComplete
    }

    public init(repo: String, revision: String, modelsDirectory: URL) {
        self.repo = repo
        download = HuggingFaceDownload(
            repo: repo, revision: revision, folder: Self.folder(of: repo, in: modelsDirectory))
    }

    public var isLoaded: Bool { container != nil }

    /// Downloads the model if needed and loads it. Later calls wait for the first one.
    public func prepare(onState: @escaping @Sendable (State) -> Void) async throws {
        while isPreparing { try await Task.sleep(for: .milliseconds(200)) }
        if container != nil {
            onState(.ready)
            return
        }
        isPreparing = true
        defer { isPreparing = false }
        do {
            if !download.isComplete {
                onState(.downloading(0))
                try await download.run { onState(.downloading($0)) }
            }
            onState(.loading)
            // Freed buffers are kept for reuse up to this size; the default keeps gigabytes.
            Memory.cacheLimit = 256 * 1024 * 1024
            container = try await LLMModelFactory.shared.loadContainer(
                from: download.folder, using: TransformersTokenizerLoader())
            onState(.ready)
        } catch {
            onState(.failed(String(describing: error)))
            throw error
        }
    }

    /// Frees the model's memory. The next ``prepare(onState:)`` loads it from disk again.
    public func unload() {
        guard !isPreparing else { return }
        container = nil
        prefix = PromptPrefix()
        Memory.clearCache()
    }

    /// The model's cleanup of `text`, not yet checked with ``AICleanup/check(source:output:glossary:)``.
    public func clean(_ text: String, glossary: [String], timeout: Duration) async throws -> String {
        guard let container else { throw CleanerError.notLoaded }
        let messages = AICleanup.messages(for: text, glossary: glossary)
        // The same prompt with another dictation shows where the dictation starts.
        let probe = AICleanup.messages(for: "~", glossary: glossary)
        let parameters = GenerateParameters(maxTokens: AICleanup.maxTokens(for: text), temperature: 0)
        let prefix = prefix
        let stream = try await container.perform { context in
            try await Self.generate(messages, probe: probe, prefix: prefix, parameters: parameters, context: context)
        }
        let deadline = ContinuousClock.now + timeout
        var output = ""
        for await generation in stream {
            if case .chunk(let piece) = generation { output += piece }
            // Stopping the loop cancels the stream and generation with it.
            if ContinuousClock.now > deadline { throw CleanerError.timedOut }
        }
        return AICleanup.extract(output)
    }

    /// Starts generating, reusing the model's state after the system prompt and examples.
    ///
    /// Every dictation is sent with the same long beginning, about 90% of the prompt, and
    /// running it through the model took longer than the answer. So that beginning is run once,
    /// its key-value cache kept, and each dictation starts from a copy. The cache is only reused
    /// when the prompt starts with exactly the same tokens, so the answer is the same as without it.
    private static func generate(
        _ messages: [AICleanup.Message], probe: [AICleanup.Message], prefix: PromptPrefix,
        parameters: GenerateParameters, context: ModelContext
    ) async throws -> AsyncStream<Generation> {
        let input = try await context.processor.prepare(input: userInput(messages))
        let tokens = input.text.tokens.asArray(Int.self)
        if !prefix.matches(tokens) {
            let other = try await context.processor.prepare(input: userInput(probe)).text.tokens.asArray(Int.self)
            // Stop a few tokens early: tokens next to the dictation can merge with its first word.
            let length = zip(tokens, other).prefix { $0 == $1 }.count - 4
            if length >= 32 {
                let cache = try context.model.newCache(parameters: parameters)
                let output = context.model(
                    LMInput.Text(tokens: MLXArray(Array(tokens[..<length])))[text: .newAxis], cache: cache,
                    state: nil)
                eval(cache.flatMap(\.state))
                prefix.store(tokens: Array(tokens[..<length]), cache: cache, state: output.state)
            }
        }
        if let (count, cache, state) = prefix.copy(), tokens.count > count, prefix.matches(tokens) {
            let rest = LMInput(tokens: MLXArray(Array(tokens[count...])))
            return try MLXLMCommon.generate(
                input: rest, cache: cache, state: state, parameters: parameters, context: context)
        }
        return try MLXLMCommon.generate(input: input, parameters: parameters, context: context)
    }

    private static func userInput(_ messages: [AICleanup.Message]) -> UserInput {
        let chat: [Chat.Message] = messages.map { message in
            switch message.role {
            case .system: .system(message.content)
            case .user: .user(message.content)
            case .assistant: .assistant(message.content)
            }
        }
        // Qwen models think aloud unless told not to; other templates ignore the flag.
        return UserInput(chat: chat, additionalContext: ["enable_thinking": false])
    }
}

/// The model's state after the shared beginning of the prompt. Used only inside the model
/// container's serial access, which is what makes the unchecked Sendable safe.
private final class PromptPrefix: @unchecked Sendable {
    private var tokens: [Int] = []
    private var cache: [KVCache] = []
    private var state: LMOutput.State?

    func matches(_ prompt: [Int]) -> Bool {
        !tokens.isEmpty && prompt.starts(with: tokens)
    }

    func store(tokens: [Int], cache: [KVCache], state: LMOutput.State?) {
        self.tokens = tokens
        self.cache = cache
        self.state = state
    }

    /// A copy to generate from: generation appends to the cache it is given.
    func copy() -> (count: Int, cache: [KVCache], state: LMOutput.State?)? {
        guard !tokens.isEmpty else { return nil }
        return (tokens.count, cache.map { $0.copy() }, state)
    }
}

/// Loads tokenizers with Hugging Face's swift-transformers.
struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(try await AutoTokenizer.from(modelFolder: directory))
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]], tools: [[String: any Sendable]]?, additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
