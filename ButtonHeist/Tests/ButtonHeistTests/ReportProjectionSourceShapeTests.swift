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
            source.contains("outputNodes = rollup.nodes.map { HeistReportNodeProjection(node: $0, profile: profile) }"),
            "output report projection should be built from TheScore flat evidence nodes"
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
            message:
            "Action evidence projection should use HeistActionEvidence.resultEvidence"
        )

        #expect(
            !scoreReport.contains("expectationActionResult ??"),
            "Report facts should not inline action expectation/result coalescing"
        )
        #expect(!scoreReport.contains("actionEvidence?.actionResult"))
        #expect(!scoreReport.contains("actionEvidence?.expectationActionResult"))
        #expect(scoreReport.contains("actionEvidence?.dispatchResult"))
        #expect(scoreReport.contains("actionEvidence?.reportedResult"))
        #expect(scoreReport.contains("actionEvidence?.traceResult"))
        #expect(
            actionProjection.contents.contains("let results = evidence.resultEvidence"),
            "Projection should read the typed action result evidence model once"
        )
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
