import ButtonHeistTestSupport
import Foundation
import Testing
import ThePlans
import TheScore

@Suite struct HeistReportMetricsTests {
    @Test func `metric names stay stable at the result boundary`() {
        #expect(HeistReport.MetricName.allCases.map(\.rawValue) == [
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
        #expect(HeistReport.CeilingMetricSource.allCases.map(\.rawValue) == [
            "intent.wait.timeout",
            "repeatUntil.timeout",
            "caseSelection.timeout",
        ])
    }

    @Test func `metrics reduce admitted execution evidence`() throws {
        let result = try metricsFixture()
        let report = HeistReport.project(result: result)
        let metrics = report.metrics

        #expect(values(in: metrics, named: .heistDurationMs) == [1234])
        #expect(values(in: metrics, named: .actionPipelineTargetResolutionMs) == [1])
        #expect(values(in: metrics, named: .actionPipelineTotalMs) == [15])
        #expect(values(in: metrics, named: .waitPipelineTargetResolutionMs) == [6, 11, 21])
        #expect(values(in: metrics, named: .waitPipelineTotalMs) == [40, 95, 60])
        #expect(values(in: metrics, named: .expectationWaitMs) == [40])
        #expect(metrics.measurements.filter { $0.path?.description == "$.body[0]" }.allSatisfy {
            $0.kind == .action && $0.status == .passed
        })
        #expect(metrics.ceilings == [
            HeistReport.CeilingMetric(
                source: .intentWaitTimeout,
                budgetMs: 100,
                elapsedMs: 95,
                path: "$.body[1]",
                kind: .wait,
                status: .passed
            ),
            HeistReport.CeilingMetric(
                source: .repeatUntilTimeout,
                budgetMs: 50,
                elapsedMs: 60,
                path: "$.body[2]",
                kind: .repeatUntil,
                status: .passed
            ),
            HeistReport.CeilingMetric(
                source: .caseSelectionTimeout,
                budgetMs: 500,
                elapsedMs: 490,
                path: "$.body[3]",
                kind: .conditional,
                status: .passed
            ),
        ])

        let encoded = try JSONEncoder().encode(metrics)
        let json = try #require(String(bytes: encoded, encoding: .utf8))
        #expect(json.contains(#""kind":"conditional""#))
        #expect(try JSONDecoder().decode(HeistReport.Metrics.self, from: encoded) == metrics)
    }

    private func metricsFixture() throws -> HeistResult {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        return HeistResult(
            steps: [
                actionStep(predicate: predicate),
                try waitStep(predicate: predicate),
                try repeatStep(predicate: predicate),
                try caseSelectionStep(),
            ],
            durationMs: 1234
        )
    }

    private func actionStep(predicate: AccessibilityPredicate) -> HeistExecutionStepResult {
        let command = HeistActionCommand.activate(.predicate(ElementPredicateTemplate(label: "Pay")))
        return HeistResultFixture.action(
            path: "$.body[0]",
            command: command,
            result: .success(
                payload: .activate,
                observation: .settledTrace(
                    makeTestTraceEvidence(
                        .noChangeForTests(elementCount: 0),
                        completeness: .incomplete
                    ),
                    .settled(duration: 3)
                ),
                timing: actionTiming
            ),
            expectationActionResult: .success(
                payload: .wait,
                observation: .settledTrace(
                    makeTestTraceEvidence(
                        .noChangeForTests(elementCount: 0),
                        completeness: .complete
                    ),
                    .settled(duration: 8)
                ),
                timing: expectationTiming
            ),
            expectation: ExpectationResult(met: true, predicate: predicate),
            durationMs: 15
        )
    }

    private func waitStep(predicate: AccessibilityPredicate) throws -> HeistExecutionStepResult {
        let check = try #require(HeistWaitEvidence.MatchedCheck(
            actionResult: .success(
                payload: .wait,
                observation: .settledTrace(
                    makeTestTraceEvidence(
                        .noChangeForTests(elementCount: 0),
                        completeness: .complete
                    ),
                    .settled(duration: 13)
                ),
                timing: waitTiming
            ),
            expectation: ExpectationResult.Met(predicate: predicate)
        ))
        return .wait(
            path: try HeistExecutionPath(validating: "$.body[1]"),
            durationMs: 100,
            predicate: predicate,
            timeout: 0.1,
            completion: .passed(evidence: try #require(HeistPassedWaitEvidence(.matched(check))))
        )
    }

    private func repeatStep(predicate: AccessibilityPredicate) throws -> HeistExecutionStepResult {
        let evidence = try #require(HeistRepeatUntilEvidence.matched(
            iterationCount: 1,
            expectation: ExpectationResult.Met(predicate: predicate),
            actionResult: .success(
                payload: .wait,
                observation: .settledTrace(
                    makeTestTraceEvidence(
                        .noChangeForTests(elementCount: 0),
                        completeness: .complete
                    ),
                    .settled(duration: 23)
                ),
                timing: repeatTiming
            )
        ))
        let completion = HeistRepeatUntilCompletion.passed(
            evidence: try #require(HeistPassedRepeatUntilEvidence(evidence))
        )
        return HeistExecutionStepResult.repeatUntil(
            path: try HeistExecutionPath(validating: "$.body[2]"),
            durationMs: 60,
            declaration: HeistRepeatUntilDeclaration(predicate: predicate, timeout: 0.05),
            completion: completion
        )
    }

    private func caseSelectionStep() throws -> HeistExecutionStepResult {
        .conditional(
            path: try HeistExecutionPath(validating: "$.body[3]"),
            durationMs: 490,
            completion: .passed(evidence: HeistCaseSelectionEvidence(selection: .selectingFirstMatch(
                cases: [],
                ifNone: .timedOut,
                elapsedMs: 490,
                timeout: 0.5
            )))
        )
    }

    private var actionTiming: ActionPerformanceTiming {
        ActionPerformanceTiming(
            beforeObservationMs: 4,
            targetResolutionMs: 1,
            actionDispatchMs: 2,
            finalSemanticEvidenceMs: 5,
            totalMs: 15
        )
    }

    private var expectationTiming: ActionPerformanceTiming {
        ActionPerformanceTiming(
            beforeObservationMs: 9,
            targetResolutionMs: 6,
            actionDispatchMs: 7,
            finalSemanticEvidenceMs: 10,
            totalMs: 40
        )
    }

    private var waitTiming: ActionPerformanceTiming {
        ActionPerformanceTiming(
            beforeObservationMs: 14,
            targetResolutionMs: 11,
            actionDispatchMs: 12,
            finalSemanticEvidenceMs: 15,
            totalMs: 95
        )
    }

    private var repeatTiming: ActionPerformanceTiming {
        ActionPerformanceTiming(
            beforeObservationMs: 24,
            targetResolutionMs: 21,
            actionDispatchMs: 22,
            finalSemanticEvidenceMs: 25,
            totalMs: 60
        )
    }

    private func values(
        in projection: HeistReport.Metrics,
        named name: HeistReport.MetricName
    ) -> [Int] {
        projection.measurements.filter { $0.name == name }.map(\.valueMs)
    }
}
