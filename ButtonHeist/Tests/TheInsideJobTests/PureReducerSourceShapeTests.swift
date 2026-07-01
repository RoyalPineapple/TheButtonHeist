import ButtonHeistTestSupport
import Foundation
import Testing

@Suite struct PureReducerSourceShapeTests {
    private static let brainsRoot = "ButtonHeist/Sources/TheInsideJob/TheBrains"

    private let repository = SourceShapeRepository(filePath: #filePath)

    @Test func `predicate wait reducer is value typed and effect free once introduced`() throws {
        let reducer = try repository.requiredFile(relativePath: "\(Self.brainsRoot)/PredicateWaitReducer.swift")

        try expectEffectFreeReducerSource(reducer)
        try reducer.requireDeclarations([
            .type("PredicateWaitReducer", conformingTo: ["Sendable", "Equatable"]),
            .type("PredicateWaitState", conformingTo: ["Sendable", "Equatable"]),
            .type("PredicateWaitObservation", conformingTo: ["Sendable", "Equatable"]),
            .type("PredicateWaitEvent", conformingTo: ["Sendable", "Equatable"]),
            .type("PredicateWaitDecision", conformingTo: ["Sendable", "Equatable"]),
        ])

        let reducerType = try reducer.requiredBlock(
            .structure("PredicateWaitReducer"),
            message:
            "\(reducer.relativePath) should declare PredicateWaitReducer as a value type"
        )
        let decisionType = try reducer.requiredBlock(
            .enumeration("PredicateWaitDecision"),
            message:
            "\(reducer.relativePath) should declare PredicateWaitDecision as a value type"
        )

        #expect(try reducerType.containsMatch(#"\bfunc\s+reduce\s*\("#))
        #expect(try reducerType.containsMatch(#"\bfunc\s+decision\s*\("#))
        #expect(
            try reducerType.containsMatch(#"\bevaluation[.]met\b"#),
            "PredicateWaitReducer should own direct expectation.met branching"
        )
        #expect(decisionType.contents.contains("case poll("))
        #expect(decisionType.contents.contains("case satisfied("))
        #expect(decisionType.contents.contains("case failed("))
    }

    @Test func `predicate polling reducer is value typed and effect free`() throws {
        let reducer = try repository.requiredFile(relativePath: "\(Self.brainsRoot)/PredicatePollingReducer.swift")
        let source = try repository.requiredFile(relativePath: "\(Self.brainsRoot)/PredicateWait.swift")
        let pollingEngine = try source.requiredBlock(
            .structure("PredicatePollingEngine"),
            message:
            "PredicateWait.swift should keep PredicatePollingEngine as the async effect interpreter"
        )

        try expectEffectFreeReducerSource(reducer)
        try reducer.requireDeclarations([
            .type("PredicatePollingReducer", conformingTo: ["Sendable", "Equatable"]),
            .type("PredicatePollingState", conformingTo: ["Sendable", "Equatable"]),
            .type("PredicatePollingEvent", conformingTo: ["Sendable", "Equatable"]),
            .type("PredicatePollingEffect", conformingTo: ["Sendable", "Equatable"]),
            .type("PredicatePollingReduction", conformingTo: ["Sendable", "Equatable"]),
            .type("PredicatePollingObservationRequest", conformingTo: ["Sendable", "Equatable"]),
        ])

        #expect(reducer.contents.contains("case observe("))
        #expect(reducer.contents.contains("case sleep("))
        #expect(reducer.contents.contains("case finish("))
        #expect(pollingEngine.contents.contains("PredicatePollingReducer("))
        #expect(pollingEngine.contents.contains("CFAbsoluteTimeGetCurrent"))
        #expect(pollingEngine.contents.contains("Task.cancellableSleep"))
    }

    @Test func `predicate wait orchestration stops owning predicate decisions after reducer lands`() throws {
        _ = try repository.requiredFile(relativePath: "\(Self.brainsRoot)/PredicateWaitReducer.swift")
        let source = try repository.requiredFile(relativePath: "\(Self.brainsRoot)/PredicateWait.swift")
        let resolvedWait = try #require(
            try source.firstBlock(matching: #"\bfunc\s+wait\s*\(\s*for\s+step:\s+ResolvedWaitStep\b"#),
            "PredicateWait.swift should keep the resolved wait orchestration as a single function"
        )
        let missingInitialObservation = try #require(
            try source.firstBlock(matching: #"\bfunc\s+waitReceiptWithoutInitialObservation\b"#),
            "PredicateWait.swift should keep the no-initial-observation orchestration explicit"
        )
        let orchestrationSource = SourceShapeFile(
            relativePath: source.relativePath,
            contents: [
                resolvedWait.contents,
                missingInitialObservation.contents,
            ].joined(separator: "\n")
        )
        let directExpectationBranches = try orchestrationSource.lines(
            matching: #"\b(if|guard)\b.*\bexpectation[.]met\b|\bexpectation[.]met\b\s*[?:]"#
        )
        let finalStateWarningCalls = try orchestrationSource.lines(
            matching: #"\bfinalStateSatisfiedTransitionWarning\s*\("#
        )

        #expect(
            directExpectationBranches.isEmpty,
            """
            PredicateWait orchestration should feed observations into PredicateWaitReducer \
            instead of branching directly on expectation.met:
            \(directExpectationBranches.joined(separator: "\n"))
            """
        )
        #expect(
            finalStateWarningCalls.isEmpty,
            """
            Final-state warning decisions should live in PredicateWaitReducer or a pure \
            collaborator used by it:
            \(finalStateWarningCalls.joined(separator: "\n"))
            """
        )
        #expect(
            !source.contents.contains("PredicateWaitPollEvaluation"),
            "Predicate polling should return PredicateWaitDecision directly"
        )
    }

    @Test func `heist wait receipt is the single typed wait result source`() throws {
        let source = try repository.requiredFile(relativePath: "\(Self.brainsRoot)/TheBrains+HeistWaitExecution.swift")
        let receipt = try source.requiredBlock(
            .structure("HeistWaitReceipt"),
            message:
            "The wait pipeline should expose one canonical typed receipt"
        )
        let predicateWait = try repository.requiredFile(relativePath: "\(Self.brainsRoot)/PredicateWait.swift")

        #expect(
            !source.contents.contains("struct HeistWaitOutcome"),
            "HeistWaitReceipt should be the canonical typed wait result; do not add a parallel outcome wrapper"
        )
        #expect(receipt.contents.contains("enum Status"))
        #expect(receipt.contents.contains("case matched"))
        #expect(receipt.contents.contains("case timedOut"))
        #expect(receipt.contents.contains("case failed("))
        #expect(
            try !receipt.containsMatch(#"\blet\s+actionResult\s*:"#),
            "HeistWaitReceipt must derive ActionResult at the output boundary, not store it"
        )
        #expect(
            try !receipt.containsMatch(#"\blet\s+waitOutcome\s*:"#),
            "HeistWaitReceipt must not store a second wait outcome source of truth"
        )
        #expect(
            try receipt.containsMatch(#"\bvar\s+actionResult\s*:\s*ActionResult\b"#),
            "ActionResult should remain a computed output projection for wait callers"
        )
        #expect(
            try !predicateWait.containsMatch(#"\bActionResult\s*\("#),
            "PredicateWait should reduce typed evidence to HeistWaitReceipt, then project ActionResult at callers"
        )
    }

    @Test func `repeat until terminal receipts use typed terminal results`() throws {
        let source = try repository.requiredFile(relativePath: "\(Self.brainsRoot)/TheBrains+HeistRepeatUntilExecution.swift")
        let terminalResult = try source.requiredBlock(
            .enumeration("RepeatUntilTerminalResult"),
            message:
            "repeat_until terminal receipt construction should use one typed terminal result"
        )
        let receiptFunction = try #require(
            try source.firstBlock(matching: #"\bprivate\s+func\s+repeatUntilResult\s*\("#),
            "repeat_until should keep terminal receipt emission in repeatUntilResult"
        )

        #expect(terminalResult.contents.contains("case predicateMet("))
        #expect(terminalResult.contents.contains("case timedOut("))
        #expect(terminalResult.contents.contains("case initialUnavailable("))
        #expect(terminalResult.contents.contains("case bodyFailed("))
        #expect(terminalResult.contents.contains("case timeoutHandledByElse("))
        #expect(terminalResult.contents.contains("case timeoutElseFailed("))
        #expect(terminalResult.contents.contains("evidence: HeistRepeatUntilEvidence"))
        #expect(terminalResult.contents.contains("failure: HeistFailureDetail"))
        #expect(terminalResult.contents.contains("children: [HeistExecutionStepResult]"))
        #expect(
            !source.contents.contains("RepeatUntilResultOverride"),
            "repeat_until receipts should not reintroduce optional result override bags"
        )
        #expect(
            try !source.containsMatch(#"\brepeatUntilResult\s*\([^)]*\boverride\s*:\s*[^)]*[?]"#),
            "repeatUntilResult should not accept optional override bags"
        )
        #expect(
            !receiptFunction.contents.contains("failureReason"),
            "repeatUntilResult should emit from RepeatUntilTerminalResult instead of reconstructing failure reason"
        )
        #expect(
            !receiptFunction.contents.contains("repeatUntilEvidence("),
            "repeatUntilResult should not rebuild evidence outside RepeatUntilTerminalResult"
        )
    }

    @Test func `post action receipts use explicit observation outcome`() throws {
        let source = try repository.requiredFile(relativePath: "\(Self.brainsRoot)/PostActionObservation.swift")
        let observationOutcome = try source.requiredBlock(
            .enumeration("ObservationOutcome"),
            message:
            "PostActionObservation should declare an explicit observation outcome enum"
        )
        let receiptBuilder = try #require(
            try source.firstBlock(matching: #"\binit\s*\(\s*postActionMethod\s+method:\s+ActionMethod\b"#),
            "Post-action receipt construction should be a typed ActionResult initializer"
        )
        let receiptState = try source.requiredBlock(
            .enumeration("PostActionReceiptState"),
            message:
            "Post-action receipt construction should reduce through one typed receipt state"
        )
        let settleEvidence = try source.requiredBlock(
            .structure("PostActionReceiptSettleEvidence"),
            message:
            "Post-action settle fields should be grouped in immutable receipt evidence"
        )

        #expect(observationOutcome.contents.contains("case cancelled("))
        #expect(observationOutcome.contents.contains("case parseFailed"))
        #expect(observationOutcome.contents.contains("case settled("))
        #expect(
            try receiptBuilder.containsMatch(#"\bPostActionReceiptState\s*\("#),
            "post-action receipt construction should project through typed receipt state"
        )
        #expect(
            try !receiptBuilder.containsMatch(#"\bActionResultBuilder\b"#),
            "post-action receipt construction should not stage mutable ActionResultBuilder state"
        )
        #expect(
            try !source.containsMatch(#"\bstruct\s+PostActionReceiptReducer\b"#),
            "Post-action receipt construction should stay on ActionResult instead of a stateless reducer object"
        )
        #expect(receiptState.contents.contains("case cancelled("))
        #expect(receiptState.contents.contains("case parseFailed("))
        #expect(receiptState.contents.contains("case settledSuccess("))
        #expect(receiptState.contents.contains("case settledFailure("))
        #expect(
            try receiptState.containsMatch(#"\bswitch\s+observationOutcome\b"#),
            "receipt state should be selected by explicit observation outcome"
        )
        #expect(
            try receiptState.containsMatch(#"\bswitch\s+context[.]actionOutcome[.]receiptOutcome\b"#),
            "settled receipts should separate action success from action failure"
        )
        #expect(settleEvidence.contents.contains("let settled: Bool"))
        #expect(settleEvidence.contents.contains("let settleTimeMs: Int"))

        #expect(
            try !source.containsMatch(#"\bstruct\s+ResultInput\b"#),
            "The old ResultInput bag should not exist once receipt construction is typed"
        )
        #expect(
            try !source.containsMatch(#"\bfinalEvidence\s*:\s*FinalEvidence[?]"#),
            """
            Post-action receipt construction should receive an explicit outcome enum, not \
            optional final evidence:
            \(source.relativePath)
            """
        )
        #expect(
            try !receiptBuilder.containsMatch(#"\bguard\s+let\s+finalEvidence\b|\bif\s+let\s+finalEvidence\b"#),
            """
            Cancellation and parse failure should be enum cases, not inferred from \
            missing final evidence:
            \(receiptBuilder.contents)
            """
        )
    }

    @Test func `post action screen change pruning returns explicit effect`() throws {
        let source = try repository.requiredFile(relativePath: "\(Self.brainsRoot)/PostActionObservation.swift")
        let refinement = try source.requiredBlock(
            .enumeration("FinalStateRefinement"),
            message:
            "PostActionObservation should model final-state refinement as a typed value or effect"
        )
        let finalSemanticEvidence = try #require(
            try source.firstBlock(matching: #"\bfunc\s+finalSemanticEvidence\b"#),
            "Post-action final evidence should be the driver that applies refinement effects"
        )
        let refinedScreenChange = try #require(
            try source.firstBlock(matching: #"\bprivate\s+func\s+refinedScreenChangeFinalState\b"#),
            "Screen-change refinement should return a typed refinement"
        )
        let prunedScreenChange = try #require(
            try source.firstBlock(matching: #"\bprivate\s+func\s+prunedScreenChangeFinalState\b"#),
            "Pruned screen-change refinement should return a typed refinement"
        )
        let commitPattern = #"\bstash[.]semanticObservationStream[.]commitSettledVisibleObservation\s*\("#

        #expect(refinement.contents.contains("case state("))
        #expect(refinement.contents.contains("case commitSettledVisibleObservation("))
        #expect(try refinedScreenChange.containsMatch(#"->\s*FinalStateRefinement[?]"#))
        #expect(try prunedScreenChange.containsMatch(#"->\s*FinalStateRefinement[?]"#))
        #expect(
            try !refinedScreenChange.containsMatch(commitPattern),
            "refinedScreenChangeFinalState should decide, not commit"
        )
        #expect(
            try !prunedScreenChange.containsMatch(commitPattern),
            "prunedScreenChangeFinalState should return the commit effect without applying it"
        )
        #expect(
            try finalSemanticEvidence.matches(of: commitPattern).count == 1,
            "finalSemanticEvidence should apply the final-state commit effect exactly once"
        )
    }

    @Test func `heist action execution keeps one wait evaluation path`() throws {
        let source = try repository.requiredFile(relativePath: "\(Self.brainsRoot)/TheBrains+HeistActionExecution.swift")

        #expect(try source.containsMatch(#"\bprivate\s+enum\s+HeistWaitEvaluation\b"#))
        #expect(try source.containsMatch(#"\bprivate\s+enum\s+HeistWaitEvaluationPurpose\b"#))
        #expect(try source.containsMatch(#"\bprivate\s+func\s+waitEvaluation\s*\("#))

        let retiredFailureHelpers = try source.lines(
            matching: #"\bprivate\s+func\s+(expectationFailure|waitFailure)\s*\("#
        )
        let retiredFailureCallSites = try source.lines(
            matching: #"\blet\s+failure\s*=\s*(expectationFailure|waitFailure)\s*\("#
        )

        #expect(
            retiredFailureHelpers.isEmpty,
            """
            Action expectations and standalone waits should share HeistWaitEvaluation:
            \(retiredFailureHelpers.joined(separator: "\n"))
            """
        )
        #expect(
            retiredFailureCallSites.isEmpty,
            """
            Action expectations and standalone waits should not branch through retired \
            duplicate helper call sites:
            \(retiredFailureCallSites.joined(separator: "\n"))
            """
        )
    }

    @Test func `text input focus result is a sum type with targeted success evidence`() throws {
        let source = try repository.requiredFile(relativePath: "\(Self.brainsRoot)/Actions+TextInputActions.swift")
        let focusResult = try source.requiredBlock(
            .enumeration("TextInputFocusResult"),
            message:
            "TextInputFocusResult should be an enum, not an optional product bag"
        )
        let focusedInput = try source.requiredBlock(
            .structure("FocusedTextInput"),
            message:
            "Targeted focus success should carry a dedicated payload"
        )
        let executeTypeText = try #require(
            try source.firstBlock(matching: #"\bfunc\s+executeTypeText\s*\(\s*\n\s*_\s+target:\s+TypeTextTarget\b"#),
            "type text dispatch should switch over TextInputFocusResult"
        )

        #expect(focusResult.contents.contains("case alreadyFocused"))
        #expect(focusResult.contents.contains("case focused(FocusedTextInput)"))
        #expect(focusResult.contents.contains("case failed(TheSafecracker.InteractionResult)"))
        #expect(try executeTypeText.containsMatch(#"\bswitch\s+focusResult\b"#))
        #expect(executeTypeText.contents.contains("case .alreadyFocused"))
        #expect(executeTypeText.contents.contains("case .focused(let input)"))
        #expect(executeTypeText.contents.contains("case .failed(let failure)"))

        #expect(focusedInput.contents.contains("let subjectEvidence: ActionSubjectEvidence"))
        #expect(focusedInput.contents.contains("let resolvedElementId: HeistId"))
        #expect(focusedInput.contents.contains("let resolvedObject: NSObject"))
        #expect(focusedInput.contents.contains("let currentValue: String?"))
        #expect(
            !focusedInput.contents.contains("TheSafecracker.InteractionResult"),
            "FocusedTextInput should contain only targeted success data"
        )

        #expect(
            try !source.containsMatch(#"\bstruct\s+TextInputFocusResult\b"#),
            "TextInputFocusResult should not be constructible as a loose optional product"
        )
        #expect(
            try !source.containsMatch(#"\bfocusResult[.]failure\b"#),
            "call sites should switch over TextInputFocusResult instead of branching on failure"
        )
        #expect(
            try !focusResult.containsMatch(#"\blet\s+(failure|subjectEvidence|resolvedElementId|resolvedObject|currentValue)\s*:"#),
            "TextInputFocusResult enum should not store old optional-bag fields"
        )
    }

    @Test func `container scroll resolution failures are typed before diagnostic projection`() throws {
        let source = try repository.requiredFile(relativePath: "\(Self.brainsRoot)/Navigation+ScrollContainers.swift")
        let pageScroll = try repository.requiredFile(relativePath: "\(Self.brainsRoot)/Navigation+PageScroll.swift")
        let resolution = try source.requiredBlock(
            .enumeration("ContainerScrollResolution"),
            message:
            "ContainerScrollResolution should be a typed result enum"
        )
        let failure = try source.requiredBlock(
            .enumeration("ContainerScrollFailure"),
            message:
            "Container scroll failures should be represented as cases, not raw diagnostic strings"
        )
        let resolver = try #require(
            try source.firstBlock(matching: #"\bfunc\s+resolveContainerScrollTarget\s*\("#),
            "Container scroll target resolution should have a single typed entry point"
        )

        #expect(resolution.contents.contains("case resolved(ScrollableTarget)"))
        #expect(resolution.contents.contains("case failed(ContainerScrollFailure)"))
        #expect(source.contents.contains("enum ContainerScrollCommand"))
        #expect(failure.contents.contains("case elementKnownButNotVisible(command: ContainerScrollCommand)"))
        #expect(failure.contents.contains("case elementAmbiguous(TheStash.TargetAmbiguityFacts, command: ContainerScrollCommand)"))
        #expect(failure.contents.contains("case axisMismatch("))
        #expect(try failure.containsMatch(#"\bvar\s+message\s*:\s*String\b"#))
        #expect(try failure.containsMatch(#"\bvar\s+command\s*:\s*ContainerScrollCommand\b"#))
        #expect(try resolver.containsMatch(#"\bcommand\s*:\s*ContainerScrollCommand\b"#))
        #expect(pageScroll.contents.contains("failure.command.method"))
        #expect(pageScroll.contents.contains("failure.message"))

        #expect(
            !source.contents.contains("case failed(String)"),
            "ContainerScrollResolution should not carry untyped failure diagnostics"
        )
        #expect(
            !source.contents.contains("commandName: String"),
            "Container scroll command identity should be typed, not an arbitrary string"
        )
        #expect(
            !source.contents.contains("return .failed(\""),
            "Container scroll resolver should construct typed failure cases before message projection"
        )
    }
}

private func expectEffectFreeReducerSource(_ source: SourceShapeFile) throws {
    for forbidden in [
        "import UIKit",
        "CFAbsoluteTimeGetCurrent",
        "Date(",
        "FileManager.default",
        "URLSession",
        "NWConnection",
        "Task.sleep",
        "await ",
    ] {
        #expect(
            !source.contents.contains(forbidden),
            "\(source.relativePath) should stay pure and effect-free; found \(forbidden)"
        )
    }
}
