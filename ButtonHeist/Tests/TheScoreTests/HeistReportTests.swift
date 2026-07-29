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
            execution: .skipped(command: command)
        )

        let report = try HeistReport.project(result: try HeistResult(steps: [step], durationMs: 0))
        let node = try #require(report.outputNodes.first)

        #expect(node.command == .activate)
        #expect(node.target == command.reportTarget)
        #expect(node.evidence == nil)
    }

    @Test func `unavailable invocation evidence projects declaration identity`() throws {
        let step = HeistExecutionStepResult.invocation(
            path: try HeistExecutionPath(validating: "$.body[0]"),
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

        let report = try HeistReport.project(result: try HeistResult(steps: [step], durationMs: 1))
        let node = try #require(report.outputNodes.first)

        #expect(node.invocationDisplayName == #"RunHeist("Cart.checkout", "Milk")"#)
        #expect(node.evidence == nil)
    }

    @Test func `report reducer derives summary from the admitted result tree`() throws {
        let child = HeistExecutionStepResult.warning(
            path: "$.body[0].heist.body[0]",
            message: "notice",
            completion: .passed()
        )
        let children = try #require(HeistPassingChildren([child]))
        let root = HeistExecutionStepResult.heist(
            path: "$.body[0]",
            name: "Checkout",
            completion: .passed(children: children)
        )
        let result = try HeistResult(steps: [root], durationMs: 5)

        let report = try HeistReport.project(result: result)

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

        let notApplicable = try HeistReport.project(result: try HeistResult(steps: [], durationMs: 0))
        #expect(notApplicable.accessibilityChange == .notApplicable)

        let incomplete = try report(
            evidence: evidence(
                before: before,
                after: after,
                coverage: .incomplete(.historyUnavailable)
            )
        )
        #expect(incomplete.accessibilityChange == .incomplete)

        let unchanged = try report(
            evidence: evidence(before: before, after: before, coverage: .complete)
        )
        #expect(unchanged.accessibilityChange == .unchanged)

        let changed = try report(
            evidence: evidence(before: before, after: after, coverage: .complete)
        )
        guard case .changed(let evidence) = changed.accessibilityChange else {
            Issue.record("Expected a complete accessibility change")
            return
        }
        #expect(evidence.count == 1)
        #expect(evidence.first?.baseline?.interface == before)
        #expect(evidence.first?.current?.interface == after)
    }

    @Test func reportPreservesEvidenceForEachExecutedStep() throws {
        let first = evidence(
            before: makeTestInterface(elementCount: 0),
            after: makeTestInterface(elementCount: 1),
            coverage: .complete
        )
        let second = evidence(
            before: makeTestInterface(elementCount: 1),
            after: makeTestInterface(elementCount: 2),
            coverage: .complete
        )
        let result = HeistResultFixture.result(steps: [
            HeistResultFixture.action(
                path: "$.body[0]",
                result: HeistResultFixture.actionResult(observationEvidence: first)
            ),
            HeistResultFixture.action(
                path: "$.body[1]",
                result: HeistResultFixture.actionResult(observationEvidence: second)
            ),
        ])

        guard case .changed(let evidence) = try HeistReport.project(result: result).accessibilityChange else {
            Issue.record("Expected accessibility changes")
            return
        }
        #expect(evidence == [first, second])
    }

    private func report(evidence: Observation.Evidence) throws -> HeistReport {
        let action = HeistResultFixture.action(
            result: HeistResultFixture.actionResult(observationEvidence: evidence)
        )
        return try HeistReport.project(result: HeistResultFixture.result(steps: [action], durationMs: 0))
    }

    private func evidence(
        before: Interface,
        after: Interface,
        coverage: Observation.Coverage
    ) -> Observation.Evidence {
        let baseline = Observation.Snapshot(interface: before, context: .empty)
        let current = Observation.Snapshot(interface: after, context: .empty)
        return Observation.Evidence(
            baseline: baseline,
            events: before == after ? [.noChange] : [.elementsChanged(current)],
            current: current,
            coverage: coverage
        )
    }
}
