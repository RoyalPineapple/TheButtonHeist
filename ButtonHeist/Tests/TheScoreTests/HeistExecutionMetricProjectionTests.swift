import Testing
import ThePlans
import TheScore

@Suite struct HeistExecutionMetricProjectionTests {
    @Test func `metric names stay stable at the receipt boundary`() {
        #expect(HeistExecutionMetricName.allCases.map(\.rawValue) == [
            "heistDurationMs",
            "actionPipeline.targetResolutionMs",
            "actionPipeline.actionDispatchMs",
            "actionPipeline.settleMs",
            "actionPipeline.beforeObservationMs",
            "actionPipeline.finalSemanticEvidenceMs",
            "actionPipeline.totalMs",
            "waitPipeline.targetResolutionMs",
            "waitPipeline.actionDispatchMs",
            "waitPipeline.settleMs",
            "waitPipeline.beforeObservationMs",
            "waitPipeline.finalSemanticEvidenceMs",
            "waitPipeline.totalMs",
            "expectationWaitMs",
        ])
        #expect(HeistExecutionCeilingMetricSource.allCases.map(\.rawValue) == [
            "intent.wait.timeout",
            "repeatUntil.timeout",
            "caseSelection.timeout",
        ])
    }

    @Test func `metric projection derives samples and ceilings from typed report facts`() throws {
        let result = try metricProjectionFixture()
        let rollup = result.evidenceRollup
        let projection = HeistExecutionMetricProjection(rollup: rollup)

        #expect(projection == rollup.metrics)
        #expect(values(in: projection, named: .heistDurationMs) == [1234])
        #expect(values(in: projection, named: .actionPipelineTargetResolutionMs) == [1])
        #expect(values(in: projection, named: .actionPipelineTotalMs) == [15])
        #expect(values(in: projection, named: .waitPipelineTargetResolutionMs) == [6, 11, 21])
        #expect(values(in: projection, named: .waitPipelineTotalMs) == [40, 95, 60])
        #expect(values(in: projection, named: .expectationWaitMs) == [40])
        #expect(projection.samples.filter { $0.path == "$.body[0]" }.allSatisfy {
            $0.kind == "action" && $0.status == .passed
        })
        #expect(projection.ceilings == [
            HeistExecutionCeilingMetric(
                source: .intentWaitTimeout,
                budgetMs: 100,
                elapsedMs: 95,
                path: "$.body[1]",
                kind: "wait",
                status: .passed
            ),
            HeistExecutionCeilingMetric(
                source: .repeatUntilTimeout,
                budgetMs: 50,
                elapsedMs: 60,
                path: "$.body[2]",
                kind: "repeat_until",
                status: .passed
            ),
            HeistExecutionCeilingMetric(
                source: .caseSelectionTimeout,
                budgetMs: 500,
                elapsedMs: 490,
                path: "$.body[3]",
                kind: "if",
                status: .passed
            ),
        ])
    }

    @Test func `summary counts receipt roots without parsing their paths`() {
        let nestedBodyPath = HeistExecutionStepResult.passed(
            path: "$.body[0]",
            kind: .wait,
            durationMs: 1
        )
        let result = HeistExecutionResult.passed(
            steps: [
                HeistExecutionStepResult.passed(
                    path: "$.capability",
                    kind: .invoke,
                    durationMs: 1,
                    children: [nestedBodyPath]
                ),
                HeistExecutionStepResult.passed(
                    path: "$.renamed[1]",
                    kind: .action,
                    durationMs: 1
                ),
            ],
            durationMs: 2
        )

        #expect(result.evidenceRollup.summary.executedTopLevelStepCount == 2)
    }

    private func metricProjectionFixture() throws -> HeistExecutionResult {
        let predicate = AccessibilityPredicate.state(.exists(ElementPredicate(label: "Done")))
        return HeistExecutionResult.passed(
            steps: [
                actionStep(predicate: predicate),
                try waitStep(predicate: predicate),
                try repeatStep(predicate: predicate),
                caseSelectionStep(),
            ],
            durationMs: 1234
        )
    }

    private func actionStep(predicate: AccessibilityPredicate) -> HeistExecutionStepResult {
        let command = HeistActionCommand.activate(.target(.predicate(ElementPredicate(label: "Pay"))))
        return HeistExecutionStepResult.passed(
            path: "$.body[0]",
            receiptKind: .action,
            durationMs: 15,
            intent: .action(command: command),
            evidence: HeistActionEvidence.expectation(
                command: command,
                dispatchResult: .success(method: .activate, timing: actionTiming),
                expectationResult: .success(method: .wait, timing: expectationTiming),
                expectation: ExpectationResult(met: true, predicate: predicate)
            )
        )
    }

    private func waitStep(predicate: AccessibilityPredicate) throws -> HeistExecutionStepResult {
        let check = try #require(HeistWaitEvidence.MatchedCheck(
            actionResult: .success(method: .wait, timing: waitTiming),
            expectation: MetExpectationResult(predicate: predicate)
        ))
        return HeistExecutionStepResult.passed(
            path: "$.body[1]",
            receiptKind: .wait,
            durationMs: 100,
            intent: .wait(predicate: .predicate(predicate), timeout: 0.1),
            evidence: HeistWaitEvidence.matched(check)
        )
    }

    private func repeatStep(predicate: AccessibilityPredicate) throws -> HeistExecutionStepResult {
        HeistExecutionStepResult.passed(
            path: "$.body[2]",
            receiptKind: .repeatUntil,
            durationMs: 60,
            intent: .repeatUntil(predicate: .predicate(predicate), timeout: 0.05),
            evidence: HeistRepeatUntilEvidence.predicateMet(
                predicate: predicate,
                timeout: 0.05,
                iterationCount: 1,
                expectation: MetExpectationResult(predicate: predicate),
                actionResult: .success(method: .wait, timing: repeatTiming)
            )
        )
    }

    private func caseSelectionStep() -> HeistExecutionStepResult {
        HeistExecutionStepResult.passed(
            path: "$.body[3]",
            receiptKind: .conditional,
            durationMs: 490,
            intent: .conditional,
            evidence: HeistCaseSelectionEvidence(selection: HeistCaseSelectionResult(
                cases: [],
                outcome: .timedOut,
                elapsedMs: 490,
                timeout: 0.5
            ))
        )
    }

    private var actionTiming: ActionPerformanceTiming {
        ActionPerformanceTiming(
            beforeObservationMs: 4,
            targetResolutionMs: 1,
            actionDispatchMs: 2,
            settleMs: 3,
            finalSemanticEvidenceMs: 5,
            totalMs: 15
        )
    }

    private var expectationTiming: ActionPerformanceTiming {
        ActionPerformanceTiming(
            beforeObservationMs: 9,
            targetResolutionMs: 6,
            actionDispatchMs: 7,
            settleMs: 8,
            finalSemanticEvidenceMs: 10,
            totalMs: 40
        )
    }

    private var waitTiming: ActionPerformanceTiming {
        ActionPerformanceTiming(
            beforeObservationMs: 14,
            targetResolutionMs: 11,
            actionDispatchMs: 12,
            settleMs: 13,
            finalSemanticEvidenceMs: 15,
            totalMs: 95
        )
    }

    private var repeatTiming: ActionPerformanceTiming {
        ActionPerformanceTiming(
            beforeObservationMs: 24,
            targetResolutionMs: 21,
            actionDispatchMs: 22,
            settleMs: 23,
            finalSemanticEvidenceMs: 25,
            totalMs: 60
        )
    }

    private func values(
        in projection: HeistExecutionMetricProjection,
        named name: HeistExecutionMetricName
    ) -> [Int] {
        projection.samples.filter { $0.name == name }.map(\.valueMs)
    }
}
