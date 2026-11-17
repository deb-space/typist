// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import Testing

@testable import TypistCore

@Suite struct SerialQueueTests {
    @Test func startsNothingWhenEmpty() {
        var queue = SerialQueue()
        #expect(queue.start() == nil)
        #expect(queue.running == nil)
    }

    @Test func givesOutOneIdAtATimeInOrder() {
        var queue = SerialQueue()
        queue.enqueue("a")
        queue.enqueue("b")
        #expect(queue.start() == "a")
        #expect(queue.running == "a")
        #expect(queue.start() == nil)
        #expect(queue.running == "a")
    }

    @Test func secondIdStartsAfterTheFirstFinishes() {
        var queue = SerialQueue()
        queue.enqueue("a")
        queue.enqueue("b")
        #expect(queue.start() == "a")
        queue.finish()
        #expect(queue.running == nil)
        #expect(queue.start() == "b")
        queue.finish()
        #expect(queue.start() == nil)
    }

    @Test func idAddedWhileRunningStartsAfterFinish() {
        var queue = SerialQueue()
        queue.enqueue("a")
        #expect(queue.start() == "a")
        queue.enqueue("b")
        #expect(queue.start() == nil)
        queue.finish()
        #expect(queue.start() == "b")
    }

    @Test func queueMovesOnAfterAMissingRecord() {
        var queue = SerialQueue()
        queue.enqueue("gone")
        queue.enqueue("b")
        #expect(queue.start() == "gone")
        queue.finish()
        #expect(queue.start() == "b")
    }

    @Test func sameIdCanRunAgainAfterFailing() {
        var queue = SerialQueue()
        queue.enqueue("a")
        #expect(queue.start() == "a")
        queue.finish()
        queue.enqueue("a")
        #expect(queue.start() == "a")
    }
}
