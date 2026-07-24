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
        #expect(values(in: metrics, named: .waitPipelineTargetResolutionMs) == [11, 21, 21])
        #expect(values(in: metrics, named: .waitPipelineTotalMs) == [95, 60, 60])
        #expect(values(in: metrics, named: .expectationWaitMs).isEmpty)
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
                source: .repeatUntilTimeout,
                budgetMs: 50,
                elapsedMs: 60,
                path: "$.body[2].repeat_until.iterations[0]",
                kind: .repeatUntilIteration,
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

    @Test func `metric decoding rejects negative durations`() {
        let negativeMeasurement = Data(#"""
        {
          "name": "heistDurationMs",
          "valueMs": -1
        }
        """#.utf8)
        let negativeCeiling = Data(#"""
        {
          "source": "intent.wait.timeout",
          "budgetMs": -1,
          "elapsedMs": 0,
          "path": "$.body[0]",
          "kind": "wait",
          "status": "passed"
        }
        """#.utf8)
        let negativeCeilingElapsed = Data(#"""
        {
          "source": "intent.wait.timeout",
          "budgetMs": 0,
          "elapsedMs": -1,
          "path": "$.body[0]",
          "kind": "wait",
          "status": "passed"
        }
        """#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(HeistReport.Measurement.self, from: negativeMeasurement)
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(HeistReport.CeilingMetric.self, from: negativeCeiling)
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(HeistReport.CeilingMetric.self, from: negativeCeilingElapsed)
        }
    }

    @Test func `metric construction requires admitted durations`() {
        #expect(throws: (any Error).self) {
            _ = HeistReport.Measurement(
                name: .heistDurationMs,
                valueMs: try ElapsedMilliseconds(validatingMilliseconds: -1)
            )
        }
        #expect(throws: (any Error).self) {
            _ = HeistReport.CeilingMetric(
                source: .intentWaitTimeout,
                budgetMs: try ElapsedMilliseconds(validatingMilliseconds: -1),
                elapsedMs: 0,
                path: "$.body[0]",
                kind: .wait,
                status: .passed
            )
        }
        #expect(throws: (any Error).self) {
            _ = HeistReport.CeilingMetric(
                source: .intentWaitTimeout,
                budgetMs: 0,
                elapsedMs: try ElapsedMilliseconds(validatingMilliseconds: -1),
                path: "$.body[0]",
                kind: .wait,
                status: .passed
            )
        }
    }

    private func metricsFixture() throws -> HeistResult {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        return try HeistResult(
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
        let command = HeistActionCommand.activate(.predicate(ElementPredicate(label: "Pay")))
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
            expectation: ExpectationResult(met: true, predicate: predicate),
            durationMs: 15
        )
    }

    private func waitStep(predicate: AccessibilityPredicate) throws -> HeistExecutionStepResult {
        let check = try #require(HeistSettlementEvidence.MatchedCheck(
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
        let declaration = HeistRepeatUntilDeclaration(predicate: predicate, timeout: 0.05)
        let iteration = HeistExecutionStepResult.repeatUntilIteration(
            path: try HeistExecutionPath(validating: "$.body[2].repeat_until.iterations[0]"),
            durationMs: 60,
            declaration: declaration,
            completion: .passed(evidence: try #require(HeistPassedRepeatUntilIterationEvidence(evidence)))
        )
        let completion = HeistRepeatUntilCompletion.passed(
            evidence: try #require(HeistPassedRepeatUntilEvidence(evidence)),
            children: try #require(HeistPassingChildren([iteration]))
        )
        return HeistExecutionStepResult.repeatUntil(
            path: try HeistExecutionPath(validating: "$.body[2]"),
            durationMs: 60,
            declaration: declaration,
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
        projection.measurements.filter { $0.name == name }.map(\.valueMs.milliseconds)
    }
}
