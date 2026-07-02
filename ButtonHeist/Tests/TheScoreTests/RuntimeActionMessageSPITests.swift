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

    let outputURL = temp.url.appendingPathComponent("stdout.txt")
    let errorURL = temp.url.appendingPathComponent("stderr.txt")
    _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    _ = FileManager.default.createFile(atPath: errorURL.path, contents: nil)
    let outputHandle = try FileHandle(forWritingTo: outputURL)
    let errorHandle = try FileHandle(forWritingTo: errorURL)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
        "swiftc",
        "-typecheck",
        "-I",
        moduleSearchPath.path,
        sourceURL.path,
    ]
    process.standardOutput = outputHandle
    process.standardError = errorHandle

    let processExited = XCTestExpectation(description: "swiftc typecheck exits")
    process.terminationHandler = { _ in
        processExited.fulfill()
    }

    try process.run()
    let timedOut = XCTWaiter().wait(for: [processExited], timeout: 15) != .completed
    process.terminationHandler = nil
    if timedOut, process.isRunning {
        process.terminate()
    }
    process.waitUntilExit()

    outputHandle.closeFile()
    errorHandle.closeFile()

    let outputText = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
    let errorText = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
    let timeoutText = timedOut ? "\nswiftc typecheck timed out after 15 seconds" : ""
    return TypecheckResult(
        terminationStatus: timedOut ? -1 : process.terminationStatus,
        combinedOutput: outputText + errorText + timeoutText
    )
}

private func theScoreModuleSearchPath() throws -> URL {
    let packageRoot = try buttonHeistPackageRoot()
    let buildRoot = packageRoot.appendingPathComponent(".build", isDirectory: true)

    let targetTriples = ["arm64-apple-macosx", "x86_64-apple-macosx"]
    let candidates = [
        buildRoot.appendingPathComponent("debug/Modules", isDirectory: true),
    ] + targetTriples.map {
        buildRoot.appendingPathComponent("\($0)/debug/Modules", isDirectory: true)
    }

    for candidate in candidates
        where FileManager.default.fileExists(atPath: candidate.appendingPathComponent("TheScore.swiftmodule").path) {
        return candidate
    }

    throw XCTSkip("Could not find a built TheScore.swiftmodule under \(buildRoot.path)")
}

private func buttonHeistPackageRoot() throws -> URL {
    var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while candidate.path != candidate.deletingLastPathComponent().path {
        if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path),
           FileManager.default.fileExists(atPath: candidate.appendingPathComponent("ButtonHeist/Sources/TheScore").path) {
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
