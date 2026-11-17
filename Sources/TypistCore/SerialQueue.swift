// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

/// Hands out ids one at a time: the next one is given only after the one in progress is finished.
public struct SerialQueue: Sendable {
    private var waiting: [String] = []
    /// The id handed out and not yet finished.
    public private(set) var running: String?

    public init() {}

    public mutating func enqueue(_ id: String) {
        waiting.append(id)
    }

    /// The next id to work on, or nil while one is running or nothing waits.
    public mutating func start() -> String? {
        guard running == nil, !waiting.isEmpty else { return nil }
        let id = waiting.removeFirst()
        running = id
        return id
    }

    /// Frees the queue for the next id. Call it for every id `start` returned, success or not.
    public mutating func finish() {
        running = nil
    }
}
