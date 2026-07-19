import Testing
import ThePlans
import TheScore

@Suite struct HeistExecutionReportProjectionTests {
    @Test func `skipped action projects declaration identity without evidence`() throws {
        let command = HeistActionCommand.activate(
            .predicate(ElementPredicateTemplate(label: "Checkout"))
        )
        let step = HeistExecutionStepResult.action(
            path: try HeistExecutionPath(validating: "$.body[0]"),
            durationMs: 0,
            execution: .skipped(command: command)
        )

        #expect(step.actionEvidence == nil)
        #expect(step.reportCommandName == HeistActionCommandType.activate.rawValue)
        #expect(step.reportTarget == command.reportTarget)
    }

    @Test func `unavailable invocation evidence projects declaration identity`() throws {
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
        #expect(step.reportDisplayName == #"RunHeist("Cart.checkout", "Milk")"#)
    }

    @Test func `report reducer derives summary from the admitted receipt tree`() throws {
        let child = HeistExecutionStepResult.warning(
            path: "$.body[0].heist.body[0]",
            durationMs: 2,
            message: "notice",
            completion: .passed()
        )
        let children = try #require(HeistPassingChildren([child]))
        let root = HeistExecutionStepResult.heist(
            path: "$.body[0]",
            durationMs: 3,
            name: "Checkout",
            completion: .passed(children: children)
        )
        let result = HeistExecutionReceipt(steps: [root], durationMs: 5)

        let report = HeistExecutionReport.project(result)

        #expect(result.steps == [root])
        #expect(result.outputReceiptNodes == [root, child])
        #expect(report.summary.executedTopLevelStepCount == 1)
        #expect(report.summary.executedNodeCount == 2)
        #expect(report.summary.outputReceiptNodeCount == 2)
        #expect(report.summary.durationMs == 5)
        #expect(report.metrics.samples.first?.name == .heistDurationMs)
        #expect(report.metrics.samples.first?.valueMs == 5)
    }
}
