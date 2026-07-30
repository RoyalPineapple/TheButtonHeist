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
        ])
        #expect(HeistReport.CeilingMetricSource.allCases.map(\.rawValue) == [
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
        #expect(metrics.measurements.filter { $0.path?.description == "$.body[0]" }.allSatisfy {
            $0.kind == .action && $0.status == .passed
        })
        #expect(metrics.ceilings == [
            HeistReport.CeilingMetric(
                source: .caseSelectionTimeout,
                budgetMs: 500,
                elapsedMs: 490,
                path: "$.body[1]",
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
          "source": "caseSelection.timeout",
          "budgetMs": -1,
          "elapsedMs": 0,
          "path": "$.body[0]",
          "kind": "conditional",
          "status": "passed"
        }
        """#.utf8)
        let negativeCeilingElapsed = Data(#"""
        {
          "source": "caseSelection.timeout",
          "budgetMs": 0,
          "elapsedMs": -1,
          "path": "$.body[0]",
          "kind": "conditional",
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
                source: .caseSelectionTimeout,
                budgetMs: try ElapsedMilliseconds(validatingMilliseconds: -1),
                elapsedMs: 0,
                path: "$.body[0]",
                kind: .wait,
                status: .passed
            )
        }
        #expect(throws: (any Error).self) {
            _ = HeistReport.CeilingMetric(
                source: .caseSelectionTimeout,
                budgetMs: 0,
                elapsedMs: try ElapsedMilliseconds(validatingMilliseconds: -1),
                path: "$.body[0]",
                kind: .wait,
                status: .passed
            )
        }
    }

    private func metricsFixture() throws -> HeistResult {
        return try HeistResult(
            steps: [
                actionStep(),
                try caseSelectionStep(),
            ],
            durationMs: 1234
        )
    }

    private func actionStep() -> HeistExecutionStepResult {
        let command = HeistActionCommand.activate(.predicate(ElementPredicate(label: "Pay")))
        return HeistResultFixture.action(
            path: "$.body[0]",
            command: command,
            result: .success(
                payload: .activate,
                timing: actionTiming
            )
        )
    }

    private func caseSelectionStep() throws -> HeistExecutionStepResult {
        .conditional(
            path: try HeistExecutionPath(validating: "$.body[1]"),
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

    private func values(
        in projection: HeistReport.Metrics,
        named name: HeistReport.MetricName
    ) -> [Int] {
        projection.measurements.filter { $0.name == name }.map(\.valueMs.milliseconds)
    }
}
