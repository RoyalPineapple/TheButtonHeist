import Foundation
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
