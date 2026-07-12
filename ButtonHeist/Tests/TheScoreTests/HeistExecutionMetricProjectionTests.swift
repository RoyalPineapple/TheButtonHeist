import Foundation
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
            $0.kind == .action && $0.status == .passed
        })
        #expect(projection.ceilings == [
            HeistExecutionCeilingMetric(
                source: .intentWaitTimeout,
                budgetMs: 100,
                elapsedMs: 95,
                path: "$.body[1]",
                kind: .wait,
                status: .passed
            ),
            HeistExecutionCeilingMetric(
                source: .repeatUntilTimeout,
                budgetMs: 50,
                elapsedMs: 60,
                path: "$.body[2]",
                kind: .repeatUntil,
                status: .passed
            ),
            HeistExecutionCeilingMetric(
                source: .caseSelectionTimeout,
                budgetMs: 500,
                elapsedMs: 490,
                path: "$.body[3]",
                kind: .conditional,
                status: .passed
            ),
        ])

        let encoded = try JSONEncoder().encode(projection)
        let json = try #require(String(bytes: encoded, encoding: .utf8))
        #expect(json.contains(#""kind":"conditional""#))
        #expect(try JSONDecoder().decode(HeistExecutionMetricProjection.self, from: encoded) == projection)
    }

    @Test func `summary excludes flattened failure actions from top level count`() {
        let bodyStep = HeistExecutionStepResult.passed(
            path: "$.body[0]",
            kind: .wait,
            durationMs: 1
        )
        let failureScreenshot = HeistExecutionStepResult.passed(
            path: "$.body[0].failure.actions[0]",
            kind: .action,
            durationMs: 1
        )
        let result = HeistExecutionResult.passed(
            steps: [bodyStep, failureScreenshot],
            durationMs: 2
        )

        #expect(result.evidenceRollup.summary.executedTopLevelStepCount == 1)
    }

    private func metricProjectionFixture() throws -> HeistExecutionResult {
        let predicate = AccessibilityPredicate<RootContext>.exists(.label("Done"))
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

    private func actionStep(predicate: AccessibilityPredicate<RootContext>) -> HeistExecutionStepResult {
        let command = HeistActionCommand.activate(.predicate(ElementPredicateTemplate(label: "Pay")))
        return HeistExecutionStepResult.passed(
            path: "$.body[0]",
            receiptKind: .action,
            durationMs: 15,
            intent: .action(command: command),
            evidence: HeistActionEvidence.expectation(
                command: command,
                dispatchResult: .success(
                    method: .activate,
                    evidence: ActionResultEvidence(timing: actionTiming)
                ),
                expectationResult: .success(
                    method: .wait,
                    evidence: ActionResultEvidence(timing: expectationTiming)
                ),
                expectation: ExpectationResult(met: true, predicate: predicate),
                warning: nil
            )
        )
    }

    private func waitStep(predicate: AccessibilityPredicate<RootContext>) throws -> HeistExecutionStepResult {
        let check = try #require(HeistWaitEvidence.MatchedCheck(
            actionResult: .success(
                method: .wait,
                evidence: ActionResultEvidence(timing: waitTiming)
            ),
            expectation: ExpectationResult.Met(predicate: predicate)
        ))
        return HeistExecutionStepResult.passed(
            path: "$.body[1]",
            receiptKind: .wait,
            durationMs: 100,
            intent: .wait(predicate: predicate, timeout: 0.1),
            evidence: HeistWaitEvidence.matched(check)
        )
    }

    private func repeatStep(predicate: AccessibilityPredicate<RootContext>) throws -> HeistExecutionStepResult {
        HeistExecutionStepResult.passed(
            path: "$.body[2]",
            receiptKind: .repeatUntil,
            durationMs: 60,
            intent: .repeatUntil(predicate: predicate, timeout: 0.05),
            evidence: HeistRepeatUntilEvidence.predicateMet(
                predicate: predicate,
                timeout: 0.05,
                iterationCount: 1,
                expectation: ExpectationResult.Met(predicate: predicate),
                actionResult: .success(
                    method: .wait,
                    evidence: ActionResultEvidence(timing: repeatTiming)
                )
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
