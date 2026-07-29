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
            "actionPipeline.totalMs",
            "waitPipeline.targetResolutionMs",
            "waitPipeline.actionDispatchMs",
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
        #expect(values(in: metrics, named: .waitPipelineTargetResolutionMs) == [21, 21])
        #expect(values(in: metrics, named: .waitPipelineTotalMs) == [60, 60])
        #expect(values(in: metrics, named: .expectationWaitMs).isEmpty)
        #expect(metrics.measurements.filter { $0.path?.description == "$.body[0]" }.allSatisfy {
            $0.kind == .action && $0.status == .passed
        })
        #expect(metrics.ceilings == [
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
                observation: observedActionEvidence(completeness: .incomplete),
                timing: actionTiming
            ),
            expectation: ExpectationResult(met: true, predicate: predicate)
        )
    }

    private func waitStep(predicate: AccessibilityPredicate) throws -> HeistExecutionStepResult {
        let evidence = HeistWaitMatchedEvidence(
            observation: observationEvidence(completeness: .complete),
            expectation: ExpectationResult.Met(predicate: predicate)
        )
        return .wait(
            path: try HeistExecutionPath(validating: "$.body[1]"),
            predicate: predicate,
            timeout: 0.1,
            completion: .passed(evidence: .matched(evidence))
        )
    }

    private func repeatStep(predicate: AccessibilityPredicate) throws -> HeistExecutionStepResult {
        let evidence = try #require(HeistRepeatUntilEvidence.matched(
            iterationCount: 1,
            expectation: ExpectationResult.Met(predicate: predicate),
            actionResult: .success(
                payload: .wait,
                observation: observedActionEvidence(completeness: .complete),
                timing: repeatTiming
            )
        ))
        let declaration = HeistRepeatUntilDeclaration(predicate: predicate, timeout: 0.05)
        let iteration = HeistExecutionStepResult.repeatUntilIteration(
            path: try HeistExecutionPath(validating: "$.body[2].repeat_until.iterations[0]"),
            declaration: declaration,
            completion: .passed(evidence: try #require(HeistPassedRepeatUntilIterationEvidence(evidence)))
        )
        let completion = HeistRepeatUntilCompletion.passed(
            evidence: try #require(HeistPassedRepeatUntilEvidence(evidence)),
            children: try #require(HeistPassingChildren([iteration]))
        )
        return HeistExecutionStepResult.repeatUntil(
            path: try HeistExecutionPath(validating: "$.body[2]"),
            declaration: declaration,
            completion: completion
        )
    }

    private func caseSelectionStep() throws -> HeistExecutionStepResult {
        .conditional(
            path: try HeistExecutionPath(validating: "$.body[3]"),
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
            targetResolutionMs: 1,
            actionDispatchMs: 2,
            totalMs: 15
        )
    }

    private var repeatTiming: ActionPerformanceTiming {
        ActionPerformanceTiming(
            targetResolutionMs: 21,
            actionDispatchMs: 22,
            totalMs: 60
        )
    }

    private func observedActionEvidence(
        completeness: Observation.Evidence.Completeness
    ) -> ActionResultObservationEvidence {
        .observed(observationEvidence(completeness: completeness))
    }

    private func observationEvidence(
        completeness: Observation.Evidence.Completeness
    ) -> Observation.Evidence {
        let snapshot = makeTestObservationSnapshot(elements: [])
        return makeTestObservationEvidence(
            baseline: snapshot,
            current: snapshot,
            events: [.noChange],
            completeness: completeness
        )
    }

    private func values(
        in projection: HeistReport.Metrics,
        named name: HeistReport.MetricName
    ) -> [Int] {
        projection.measurements.filter { $0.name == name }.map(\.valueMs.milliseconds)
    }
}
