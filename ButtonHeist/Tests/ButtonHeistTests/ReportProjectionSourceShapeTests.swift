import Foundation
import ButtonHeistTestSupport
import Testing

@Suite struct ReportProjectionSourceShapeTests {

    @Test func `report projections stay split by domain and size`() throws {
        let fenceDirectory = repositoryRoot()
            .appendingPathComponent("ButtonHeist/Sources/TheButtonHeist/TheFence", isDirectory: true)

        let requiredFiles = Set([
            "ActionProjection.swift",
            "DeltaProjection.swift",
            "HeistEvidenceProjection.swift",
            "HeistReportProjection.swift",
            "InterfaceProjection.swift",
            "ProjectionProfile.swift",
        ])
        for fileName in requiredFiles {
            #expect(
                FileManager.default.fileExists(atPath: fenceDirectory.appendingPathComponent(fileName).path),
                "\(fileName) should own one report projection domain"
            )
        }

        let projectionFiles = try projectionSourceFiles(in: fenceDirectory)
        #expect(!projectionFiles.isEmpty, "projection source files should be discoverable")

        for fileURL in projectionFiles {
            let lineCount = try sourceLineCount(fileURL)
            #expect(
                lineCount <= 400,
                "\(fileURL.lastPathComponent) has \(lineCount) lines; projection files should stay at or below 400"
            )
        }
    }

    @Test func `heist report projection consumes score evidence nodes`() throws {
        let source = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("ButtonHeist/Sources/TheButtonHeist/TheFence/HeistReportProjection.swift"),
            encoding: .utf8
        )

        #expect(
            source.contains("nodes = rollup.rootNodes.map { HeistReportNodeProjection(node: $0, profile: profile) }"),
            "tree report projection should be built from TheScore root evidence nodes"
        )
        #expect(
            source.contains("outputNodes = rollup.outputNodes.map { HeistReportNodeProjection(node: $0, profile: profile) }"),
            "output report projection should be built from TheScore event-derived flat evidence nodes"
        )
        #expect(
            !source.contains("result.steps.map { HeistReportNodeProjection"),
            "Fence must not bypass TheScore evidence nodes when projecting report nodes"
        )
        #expect(
            !source.contains("precondition("),
            "Fence should not runtime-check summary/output-node agreement it can make unrepresentable"
        )
        #expect(
            !source.contains("traceResultsInExecutionOrder\n            .compactMap"),
            "final-screen facts should originate in TheScore summary facts"
        )
    }

    @Test func `summary action and warning rollups reduce typed evidence events`() throws {
        let relativePath = "ButtonHeist/Sources/TheScore/HeistExecutionResult+Report.swift"
        let contents = try sourceFile(relativePath)
        let scoreReport = SourceShapeFile(relativePath: relativePath, contents: contents)
        let rollup = try scoreReport.requiredBlock(
            .structure("HeistExecutionEvidenceRollup"),
            message: "TheScore rollup should own the ordered evidence event stream"
        )
        let event = try scoreReport.requiredBlock(
            .enumeration("HeistExecutionEvidenceEvent"),
            message: "TheScore should model report facts as typed evidence events"
        )
        let builder = try scoreReport.requiredBlock(
            .structure("HeistExecutionEvidenceEventBuilder"),
            message: "Event construction should stay owned by TheScore"
        )
        let stepDetail = try scoreReport.requiredBlock(
            .enumeration("HeistExecutionStepReportDetail"),
            message: "Step report facts should derive from a typed evidence detail"
        )
        let stepFacts = try scoreReport.requiredBlock(
            .structure("HeistExecutionStepReportFacts"),
            message: "Step report facts should avoid flattened optional evidence inputs"
        )
        let summary = try scoreReport.requiredBlock(
            .structure("HeistExecutionEvidenceSummary"),
            message: "Summary facts should reduce typed evidence events"
        )
        let actions = try scoreReport.requiredBlock(
            .structure("HeistExecutionActionEvidenceRollup"),
            message: "Action rollups should reduce typed evidence events"
        )
        let warnings = try scoreReport.requiredBlock(
            .structure("HeistExecutionWarningEvidenceRollup"),
            message: "Warning rollups should reduce typed evidence events"
        )

        #expect(try event.containsMatch(#"\bcase\s+nodeVisited\s*\("#))
        #expect(try event.containsMatch(#"\bcase\s+dispatchedActionResult\s*\("#))
        #expect(try event.containsMatch(#"\bcase\s+reportedActionResult\s*\("#))
        #expect(try event.containsMatch(#"\bcase\s+traceResult\s*\("#))
        #expect(try event.containsMatch(#"\bcase\s+expectationChecked\s*\("#))
        #expect(try event.containsMatch(#"\bcase\s+warning\s*\("#))
        #expect(try event.containsMatch(#"\bcase\s+firstFailure\s*\("#))
        #expect(try event.containsMatch(#"\bcase\s+finalScreen\s*\("#))

        #expect(try rollup.containsMatch(#"\bpackage\s+let\s+events\s*:\s*\[HeistExecutionEvidenceEvent\]"#))
        #expect(
            rollup.contents.contains("self.events = HeistExecutionEvidenceEventBuilder().events(rootNodes: rootNodes)"),
            "Rollup should store one ordered event stream built from its evidence nodes"
        )
        #expect(try builder.containsMatch(#"\bevents[.]append\s*\([.]nodeVisited\b"#))
        #expect(try builder.containsMatch(#"\bevents[.]append\s*\([.]dispatchedActionResult\b"#))
        #expect(try builder.containsMatch(#"\bevents[.]append\s*\([.]reportedActionResult\b"#))
        #expect(try builder.containsMatch(#"\bevents[.]append\s*\([.]traceResult\b"#))
        #expect(try builder.containsMatch(#"\bevents[.]append\s*\([.]expectationChecked\b"#))
        #expect(try builder.containsMatch(#"\bevents[.]append\s*\([.]warning\b"#))
        #expect(try builder.containsMatch(#"\bevents[.]append\s*\([.]firstFailure\b"#))
        #expect(try builder.containsMatch(#"\bevents[.]append\s*\([.]finalScreen\b"#))

        #expect(summary.contents.contains("for event in rollup.events"))
        #expect(!summary.contents.contains("rollup.nodes.count"))
        #expect(!summary.contents.contains("rollup.actions.finalScreenId"))
        #expect(actions.contents.contains("fileprivate let events: [HeistExecutionEvidenceEvent]"))
        #expect(!actions.contents.contains("nodes.compactMap"))
        #expect(!actions.contents.contains("traceResultsInExecutionOrder\n            .compactMap"))
        #expect(warnings.contents.contains("fileprivate let events: [HeistExecutionEvidenceEvent]"))
        #expect(!warnings.contents.contains("nodes.compactMap"))

        #expect(try stepDetail.containsMatch(#"\bcase\s+action\s*\(\s*HeistActionEvidence\s*\)"#))
        #expect(try stepDetail.containsMatch(#"\bcase\s+wait\s*\(\s*HeistWaitEvidence\s*\)"#))
        #expect(try stepDetail.containsMatch(#"\bcase\s+repeatUntil\s*\(\s*HeistRepeatUntilEvidence\s*\)"#))
        #expect(try stepDetail.containsMatch(#"\bcase\s+invocation\s*\(\s*HeistInvocationEvidence\s*\)"#))
        #expect(
            stepFacts.contents.contains("let detail = HeistExecutionStepReportDetail(kind: step.kind, evidence: step.evidence)"),
            "Step facts should build typed report detail once"
        )
        #expect(try !stepFacts.containsMatch(#"\blet\s+actionEvidence\s*=\s*step[.]actionEvidence\b"#))
        #expect(try !stepFacts.containsMatch(#"\blet\s+waitEvidence\s*=\s*step[.]waitEvidence\b"#))
        #expect(try !stepFacts.containsMatch(#"\blet\s+repeatUntilEvidence\s*=\s*step[.]repeatUntilEvidence\b"#))
        #expect(try !stepFacts.containsMatch(#"\blet\s+invocationEvidence\s*=\s*step[.]invocationEvidence\b"#))
        let flattenedEvidenceSignaturePattern = [
            #"actionEvidence\s*:\s*HeistActionEvidence[?]"#,
            #"waitEvidence\s*:\s*HeistWaitEvidence[?]"#,
            #"repeatUntilEvidence\s*:\s*HeistRepeatUntilEvidence[?]"#,
            #"invocationEvidence\s*:\s*HeistInvocationEvidence[?]"#,
        ].joined(separator: #"[\s\S]*"#)
        #expect(try !stepFacts.containsMatch(
            flattenedEvidenceSignaturePattern,
            options: [.dotMatchesLineSeparators]
        ))
    }

    @Test func `action report consumers use typed action result evidence`() throws {
        let scoreReport = try sourceFile("ButtonHeist/Sources/TheScore/HeistExecutionResult+Report.swift")
        let projectionSource = try sourceFile(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/HeistEvidenceProjection.swift"
        )
        let doctorSource = try sourceFile("ButtonHeist/Sources/HeistDoctorCore/HeistDoctorEvidence.swift")
        let actionProjection = try SourceShapeFile(
            relativePath: "ButtonHeist/Sources/TheButtonHeist/TheFence/HeistEvidenceProjection.swift",
            contents: projectionSource
        ).requiredBlock(
            .structure("HeistActionEvidenceProjection"),
            message: "Action evidence projection should own command metadata separately from typed action evidence"
        )
        let actionResultProjection = try SourceShapeFile(
            relativePath: "ButtonHeist/Sources/TheButtonHeist/TheFence/HeistEvidenceProjection.swift",
            contents: projectionSource
        ).requiredBlock(
            .enumeration("HeistActionResultEvidenceProjection"),
            message: "Action evidence projection should keep action evidence typed until public JSON encoding"
        )
        let publicActionEvidence = try SourceShapeFile(
            relativePath: "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON+Action.swift",
            contents: try sourceFile("ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON+Action.swift")
        ).requiredBlock(
            .structure("PublicHeistActionEvidence"),
            message: "Public action evidence should be the sparse JSON boundary"
        )

        #expect(
            !scoreReport.contains("expectationActionResult ??"),
            "Report facts should not inline action expectation/result coalescing"
        )
        #expect(!scoreReport.contains("actionEvidence?.actionResult"))
        #expect(!scoreReport.contains("actionEvidence?.expectationActionResult"))
        #expect(!scoreReport.contains("actionEvidence?.dispatchResult"))
        #expect(!scoreReport.contains("actionEvidence?.reportedResult"))
        #expect(!scoreReport.contains("actionEvidence?.traceResult"))
        #expect(scoreReport.contains("return evidence.dispatchResult"))
        #expect(scoreReport.contains("case .action(let evidence):\n            return evidence.reportedResult"))
        #expect(scoreReport.contains("case .action(let evidence):\n            return evidence.traceResult"))
        #expect(
            actionProjection.contents.contains("let evidence: HeistActionResultEvidenceProjection"),
            "Projection should store typed action evidence rather than flattened optional DTO fields"
        )
        #expect(!actionProjection.contents.contains("let result: ActionProjection?"))
        #expect(!actionProjection.contents.contains("let expectationResult: ActionProjection?"))
        #expect(!actionProjection.contents.contains("let expectation: ExpectationProjection?"))
        #expect(!actionProjection.contents.contains("let warning: HeistActionWarning?"))
        #expect(try actionResultProjection.containsMatch(#"\bcase\s+commandResolutionFailure\s*\("#))
        #expect(try actionResultProjection.containsMatch(#"\bcase\s+dispatch\s*\("#))
        #expect(try actionResultProjection.containsMatch(#"\bcase\s+expectation\s*\("#))
        #expect(try actionResultProjection.containsMatch(#"\bswitch\s+resultEvidence\b"#))
        #expect(try publicActionEvidence.containsMatch(#"\bswitch\s+projection[.]evidence\b"#))
        #expect(try publicActionEvidence.containsMatch(#"\bcase\s+result\b"#))
        #expect(try publicActionEvidence.containsMatch(#"\bcase\s+expectationResult\b"#))
        #expect(try publicActionEvidence.containsMatch(#"\bcase\s+expectation\b"#))
        #expect(try publicActionEvidence.containsMatch(#"\bcase\s+warning\b"#))
        #expect(!actionProjection.contents.contains("evidence.actionResult"))
        #expect(!actionProjection.contents.contains("evidence.expectationActionResult"))
        #expect(!doctorSource.contains("expectationActionResult ??"))
        #expect(!doctorSource.contains("actionEvidence.actionResult"))
        #expect(!doctorSource.contains("actionEvidence.expectationActionResult"))
        #expect(doctorSource.contains("evidence.reportedResult"))
        #expect(doctorSource.contains("actionEvidence.dispatchResult"))
    }
}

private func projectionSourceFiles(in directory: URL) throws -> [URL] {
    let files = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    )
    return files
        .filter { $0.pathExtension == "swift" && $0.lastPathComponent.contains("Projection") }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

private func sourceLineCount(_ fileURL: URL) throws -> Int {
    try String(contentsOf: fileURL, encoding: .utf8)
        .split(separator: "\n", omittingEmptySubsequences: false)
        .count
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func sourceFile(_ relativePath: String) throws -> String {
    try String(
        contentsOf: repositoryRoot().appendingPathComponent(relativePath),
        encoding: .utf8
    )
}
