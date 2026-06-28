import Foundation
import ThePlans
import XCTest

final class RuntimeActionMessageSPITests: XCTestCase {

    func testRuntimeActionMessageIsHiddenFromPlainTheScoreImports() throws {
        let moduleSearchPath = try theScoreModuleSearchPath()

        let result = try typecheck(
            source: """
            import TheScore

            let _: RuntimeActionMessage? = nil
            """,
            moduleSearchPath: moduleSearchPath
        )

        XCTAssertNotEqual(result.terminationStatus, 0, result.combinedOutput)
        XCTAssertTrue(
            result.combinedOutput.contains("cannot find type 'RuntimeActionMessage' in scope"),
            result.combinedOutput
        )
    }

    func testRuntimeActionMessageIsHiddenFromExternalButtonHeistInternalsSPIImports() throws {
        let moduleSearchPath = try theScoreModuleSearchPath()

        let result = try typecheck(
            source: """
            @_spi(ButtonHeistInternals) import TheScore

            let _: RuntimeActionMessage? = nil
            """,
            moduleSearchPath: moduleSearchPath
        )

        XCTAssertNotEqual(result.terminationStatus, 0, result.combinedOutput)
        XCTAssertTrue(
            result.combinedOutput.contains("cannot find type 'RuntimeActionMessage' in scope"),
            result.combinedOutput
        )
    }
}

private struct TypecheckResult {
    let terminationStatus: Int32
    let combinedOutput: String
}

private func typecheck(source: String, moduleSearchPath: URL) throws -> TypecheckResult {
    let temp = try ScoreSPITemporaryDirectory()
    let sourceURL = temp.url.appendingPathComponent("Client.swift")
    try source.write(to: sourceURL, atomically: true, encoding: .utf8)

    let output = Pipe()
    let error = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
        "swiftc",
        "-typecheck",
        "-I",
        moduleSearchPath.path,
        sourceURL.path,
    ]
    process.standardOutput = output
    process.standardError = error

    try process.run()
    process.waitUntilExit()

    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = error.fileHandleForReading.readDataToEndOfFile()
    let outputText = String(data: outputData, encoding: .utf8) ?? ""
    let errorText = String(data: errorData, encoding: .utf8) ?? ""
    return TypecheckResult(
        terminationStatus: process.terminationStatus,
        combinedOutput: outputText + errorText
    )
}

private func theScoreModuleSearchPath() throws -> URL {
    let packageRoot = try buttonHeistPackageRoot()
    let buildRoot = packageRoot.appendingPathComponent(".build", isDirectory: true)
    guard let enumerator = FileManager.default.enumerator(
        at: buildRoot,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ) else {
        throw XCTSkip("Could not inspect \(buildRoot.path)")
    }

    var candidates: [URL] = []
    for case let url as URL in enumerator where url.lastPathComponent == "TheScore.swiftmodule" {
        guard !url.path.contains("/index-build/") else { continue }
        candidates.append(url.deletingLastPathComponent())
    }

    if let debugCandidate = candidates.first(where: { $0.path.contains("/debug/Modules") }) {
        return debugCandidate
    }
    if let candidate = candidates.sorted(by: { $0.path < $1.path }).first {
        return candidate
    }
    throw XCTSkip("Could not find a built TheScore.swiftmodule under \(buildRoot.path)")
}

private func buttonHeistPackageRoot() throws -> URL {
    var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while candidate.path != candidate.deletingLastPathComponent().path {
        if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path),
           candidate.lastPathComponent == "ButtonHeist" {
            return candidate
        }
        candidate = candidate.deletingLastPathComponent()
    }

    throw XCTSkip("Could not find ButtonHeist package root")
}

private final class ScoreSPITemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("score-spi-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
