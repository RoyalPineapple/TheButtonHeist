import Testing
import ThePlans
import TheScore

@Suite struct HeistExecutionReportFactsTests {
    @Test func `skipped action keeps declaration identity without evidence`() throws {
        let command = HeistActionCommand.activate(
            .predicate(ElementPredicateTemplate(label: "Checkout"))
        )
        let step = HeistExecutionStepResult.action(
            path: try HeistExecutionPath(validating: "$.body[0]"),
            durationMs: 0,
            execution: .skipped(command: command)
        )

        #expect(step.actionEvidence == nil)
        #expect(step.reportFacts.command == .activate)
        #expect(step.reportFacts.target == command.reportTarget)
    }

    @Test func `unavailable invocation evidence keeps declaration identity`() throws {
        let step = HeistExecutionStepResult.invocation(
            path: try HeistExecutionPath(validating: "$.body[1]"),
            durationMs: 1,
            invocationPath: "Cart.checkout",
            argument: .string("Milk"),
            completion: .failed(
                evidence: .unavailable,
                failure: HeistFailureDetail(
                    category: .runtimeUnavailable,
                    contract: "invocation evidence is observed",
                    observed: "runtime unavailable"
                )
            )
        )

        #expect(step.invocationEvidence == nil)
        #expect(step.reportFacts.capabilityPath == "Cart.checkout")
        #expect(step.reportFacts.invocationDisplayName == #"RunHeist("Cart.checkout", "Milk")"#)
    }
}
