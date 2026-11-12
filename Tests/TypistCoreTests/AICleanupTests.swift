// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import Testing

@testable import TypistCore

@Suite struct AICleanupTests {
    let glossary = ["Kubernetes", "kubectl", "Helm", "Docker", "Dockerfile", "Flux CD", "Typist"]

    @Test func wrapsTheDictationAfterTheExamples() {
        let messages = AICleanup.messages(for: "hello", glossary: ["Typist", " "])
        #expect(messages.first?.role == .system)
        #expect(messages.first?.content.hasSuffix("Glossary: Typist") == true)
        #expect(messages.last == AICleanup.Message(.user, "<dictation>hello</dictation>"))
        #expect(messages.count == 2 + 2 * AICleanup.examples.count)
    }

    @Test func leavesOutAnEmptyGlossary() {
        #expect(AICleanup.messages(for: "hi", glossary: []).first?.content.contains("Glossary") == false)
    }

    @Test func extractsTheAnswer() {
        #expect(AICleanup.extract("<think>\nhmm\n</think>\n\n<dictation>How are you?</dictation>\n") == "How are you?")
    }

    /// Answers like the benchmark's that should be inserted.
    @Test(arguments: [
        ("send it to my email please", "Send it to my email, please."),
        ("let's meet on Tuesday, sorry, I mean Wednesday, at the office.", "Let's meet on Wednesday at the office."),
        ("we need a docker file for the python app", "We need a Dockerfile for the Python app."),
        ("cube ctl", "kubectl"),
        (
            "um so basically we need to, uh, install cube or net ease with helm",
            "We need to install Kubernetes with Helm."
        ),
        ("create five, no, six services in the bin folder", "Create six services in the bin folder."),
        ("Write me an email to my e-mail", "Write me an email to my email"),
    ])
    func acceptsCleanups(source: String, output: String) {
        #expect(AICleanup.check(source: source, output: output, glossary: glossary) == nil)
    }

    @Test func rejectsAnAnswerInsteadOfTheText() {
        #expect(
            AICleanup.check(
                source: "what is two plus two times two, write the answer here", output: "6", glossary: [])
                == .length)
    }

    @Test func rejectsDroppedWords() {
        #expect(
            AICleanup.check(
                source: "please book a table for four people at the italian place near the station",
                output: "Please book a table for us at the station.", glossary: [])
                == .droppedWords)
    }

    @Test func acceptsAList() {
        #expect(
            AICleanup.check(
                source: "Buy first milk, second bread and third eggs",
                output: "Buy:\n1. Milk\n2. Bread\n3. Eggs", glossary: []) == nil)
        #expect(
            AICleanup.check(
                source: "I have two things to say, the price is too high and the deadline is too close",
                output: "I have two things to say:\n1. The price is too high\n2. The deadline is too close",
                glossary: [])
                == .format)
        #expect(AICleanup.isList("- milk\n- bread"))
        #expect(!AICleanup.isList("Milk.\nBread.\n1. Eggs"))
    }

    @Test func keepsLineBreaksTheSpeakerAskedFor() {
        #expect(
            AICleanup.check(
                source: "Thanks.\n\nBest regards, Anna", output: "Thanks. Best regards, Anna.", glossary: [])
                == .format)
        #expect(
            AICleanup.check(
                source: "Thanks.\n\nbest regards anna", output: "Thanks.\n\nBest regards, Anna", glossary: [])
                == nil)
    }

    @Test func rejectsNewLinesAndCode() {
        #expect(
            AICleanup.check(source: "shopping list milk bread eggs", output: "Shopping list:\nmilk bread", glossary: [])
                == .format)
        #expect(AICleanup.check(source: "hi", output: "", glossary: []) == .empty)
    }

    @Test func givesRoomForTheAnswer() {
        #expect(AICleanup.maxTokens(for: "abc") == 51)
        #expect(AICleanup.maxTokens(for: String(repeating: "a", count: 5_000)) == 1_024)
    }
}
