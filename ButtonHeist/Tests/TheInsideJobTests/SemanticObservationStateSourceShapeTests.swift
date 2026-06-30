import ButtonHeistTestSupport
import Foundation
import Testing

@Suite struct SemanticObservationStateSourceShapeTests {
    private static let stashRoot = "ButtonHeist/Sources/TheInsideJob/TheStash"

    private let repository = SourceShapeRepository(filePath: #filePath)

    @Test func `observation cycles are scoped by begin token`() throws {
        let source = try repository.requiredFile(relativePath: "\(Self.stashRoot)/SemanticObservationCycles.swift")

        #expect(!source.contents.contains("var inProgress"))
        #expect(source.contents.contains("enum CyclePhase"))
        #expect(source.contents.contains("case idle(completed: UInt64)"))
        #expect(source.contents.contains("case running(Cycle)"))
        #expect(source.contents.contains("func beginCycle(scope: SemanticObservationScope) -> Cycle"))
        #expect(source.contents.contains("func finishCycle(token cycle: Cycle, didObserve: Bool)"))
        #expect(!source.contents.contains("func finishCycle(didObserve: Bool, scope: SemanticObservationScope)"))
    }

    @Test func `fulfillment history is an explicit enum state`() throws {
        let source = try repository.requiredFile(relativePath: "\(Self.stashRoot)/SemanticObservationStream.swift")
        let fulfillment = try #require(
            try source.firstBlock(matching: #"\bstruct\s+SemanticObservationFulfillmentState\b"#),
            "SemanticObservationStream should keep fulfillment state in SemanticObservationFulfillmentState"
        )

        #expect(fulfillment.contents.contains("enum State"))
        #expect(fulfillment.contents.contains("case empty"))
        #expect(fulfillment.contents.contains("case clean(CurrentFulfillment)"))
        #expect(fulfillment.contents.contains("case invalidated(CurrentFulfillment?)"))
        #expect(
            try !fulfillment.containsMatch(#"\bvar\s+latestSettledObservationInvalidated\s*="#),
            "latestSettledObservationInvalidated should be derived from fulfillment state, not stored"
        )
    }

    @Test func `passive observation scheduling is one enum state`() throws {
        let source = try repository.requiredFile(relativePath: "\(Self.stashRoot)/SemanticObservationStream.swift")

        #expect(source.contents.contains("enum PassiveObservationState"))
        #expect(source.contents.contains("case stopped"))
        #expect(source.contents.contains("case running("))
        for forbidden in [
            "passiveObservationTask",
            "discoveryObservation",
            "passiveObservationSettledReading",
        ] {
            #expect(
                !source.contents.contains(forbidden),
                "Passive observation should not restore sidecar field \(forbidden)"
            )
        }
    }

    @Test func `waiter continuation lifecycle is an enum`() throws {
        let source = try repository.requiredFile(relativePath: "\(Self.stashRoot)/SemanticObservationSettledWaiters.swift")
        let continuation = try #require(
            try source.firstBlock(matching: #"\bstruct\s+SemanticObservationWaiterContinuation\b"#),
            "SemanticObservationSettledWaiters should keep continuation state isolated"
        )

        #expect(continuation.contents.contains("enum State"))
        #expect(continuation.contents.contains("case pending"))
        #expect(continuation.contents.contains("case registered(CheckedContinuation<Value, Never>)"))
        #expect(continuation.contents.contains("case resumed"))
        #expect(!continuation.contents.contains("didResume"))
        #expect(
            try !continuation.containsMatch(#"\bvar\s+continuation\s*:\s*CheckedContinuation<[^>]+>\?"#),
            "Waiter continuation should not pair an optional continuation with resumed state"
        )
    }
}
