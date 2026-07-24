import Testing
import ButtonHeistTestSupport
import ThePlans
import TheScore

@Suite struct HeistReportTests {
    @Test func `skipped action report preserves declaration identity without evidence`() throws {
        let command = HeistActionCommand.activate(
            .predicate(ElementPredicate(label: "Checkout"))
        )
        let step = HeistExecutionStepResult.action(
            path: try HeistExecutionPath(validating: "$.body[0]"),
            durationMs: 0,
            execution: .skipped(command: command)
        )

        let report = HeistReport.project(result: try HeistResult(steps: [step], durationMs: 0))
        let node = try #require(report.outputNodes.first)

        #expect(node.command == .activate)
        #expect(node.target == command.reportTarget)
        #expect(node.evidence == nil)
    }

    @Test func `unavailable invocation evidence projects declaration identity`() throws {
        let step = HeistExecutionStepResult.invocation(
            path: try HeistExecutionPath(validating: "$.body[0]"),
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

        let report = HeistReport.project(result: try HeistResult(steps: [step], durationMs: 1))
        let node = try #require(report.outputNodes.first)

        #expect(node.invocationDisplayName == #"RunHeist("Cart.checkout", "Milk")"#)
        #expect(node.evidence == nil)
    }

    @Test func `report reducer derives summary from the admitted result tree`() throws {
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
        let result = try HeistResult(steps: [root], durationMs: 5)

        let report = HeistReport.project(result: result)

        #expect(result.steps == [root])
        #expect(report.outputNodes.map(\.path) == [root.path, child.path])
        #expect(report.nodes.first?.children.first?.path == child.path)
        #expect(report.summary.executedTopLevelStepCount == 1)
        #expect(report.summary.executedNodeCount == 2)
        #expect(report.summary.outputNodeCount == 2)
        #expect(report.summary.durationMs == 5)
        #expect(report.metrics.measurements.first?.name == .heistDurationMs)
        #expect(report.metrics.measurements.first?.valueMs == 5)
        #expect(report.warnings == [HeistExecutionWarning(path: child.path, message: "notice")])
    }

    @Test func `report classifies accessibility change without optional absence`() throws {
        let before = makeTestInterface(elementCount: 0)
        let after = makeTestInterface(elementCount: 1)

        let notApplicable = HeistReport.project(result: try HeistResult(steps: [], durationMs: 0))
        #expect(notApplicable.accessibilityChange == .notApplicable)

        let incomplete = report(trace: makeTestTrace(before: before, after: after), completeness: .incomplete)
        #expect(incomplete.accessibilityChange == .incomplete)

        let unchanged = report(trace: makeTestTrace(before: before, after: before), completeness: .complete)
        #expect(unchanged.accessibilityChange == .unchanged)

        let changed = report(trace: makeTestTrace(before: before, after: after), completeness: .complete)
        guard case .changed(let trace) = changed.accessibilityChange else {
            Issue.record("Expected a complete accessibility change")
            return
        }
        #expect(trace.captures.first?.interface == before)
        #expect(trace.captures.last?.interface == after)
    }

    private func report(
        trace: AccessibilityTrace,
        completeness: AccessibilityTraceEvidence.Completeness
    ) -> HeistReport {
        let evidence = makeTestTraceEvidence(trace, completeness: completeness)
        let action = HeistResultFixture.action(
            result: HeistResultFixture.actionResult(traceEvidence: evidence)
        )
        return HeistReport.project(result: HeistResultFixture.result(steps: [action], durationMs: 0))
    }
}
