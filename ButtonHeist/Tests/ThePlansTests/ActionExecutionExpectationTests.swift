import Foundation
import Testing

@testable import ThePlans

@Test func `action execution expectation is nonoptional for every admitted policy`() throws {
    let explicit = ActionStep(
        command: .dismiss,
        expectationPolicy: .expect(ActionExpectation(predicate: .screenChanged))
    )
    let waived = ActionStep(
        command: .dismiss,
        expectationPolicy: .waived(try ActionExpectationWaiver(validating: "fixture"))
    )
    let defaulted = ActionStep(command: .dismiss)

    guard case .authoredThenNoChange(let authored) = explicit.executionExpectation else {
        Issue.record("An authored action must preserve its authored expectation")
        return
    }
    #expect(authored.predicate == .screenChanged)
    #expect(waived.executionExpectation == .noChange)
    #expect(defaulted.executionExpectation == .noChange)
}

@Test func `decoded action derives the same execution expectation`() throws {
    let decoded = try JSONDecoder().decode(ActionStep.self, from: Data(#"""
    {
      "command": { "type": "dismiss" },
      "without_expectation": "fixture"
    }
    """#.utf8))

    #expect(decoded.executionExpectation == .noChange)
}
