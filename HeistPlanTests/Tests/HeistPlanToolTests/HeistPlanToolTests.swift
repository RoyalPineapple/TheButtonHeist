import Foundation
import Testing
import ThePlans

@Suite(.serialized)
struct HeistPlanToolTests {
    @Test
    func `validate succeeds for a valid fixture`() throws {
        let temp = try TemporaryDirectory()
        let planURL = temp.url.appendingPathComponent("valid.heist")
        try HeistArtifactCodec.writePlan(representativePlan(), to: planURL)

        let result = try runHeistPlan(["validate", planURL.path])

        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout.isEmpty)
    }

    @Test
    func `validate fails for malformed JSON`() throws {
        let temp = try TemporaryDirectory()
        let planURL = temp.url.appendingPathComponent("malformed.json")
        try "{".write(to: planURL, atomically: true, encoding: .utf8)

        let result = try runHeistPlan(["validate", planURL.path])

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("Invalid heist plan"))
    }

    @Test
    func `validate fails for raw JSON with heist extension`() throws {
        let temp = try TemporaryDirectory()
        let planURL = temp.url.appendingPathComponent("raw.heist")
        try writeCanonicalJSON(representativePlan(), to: planURL)

        let result = try runHeistPlan(["validate", planURL.path])

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("raw JSON is not a .heist package"))
    }

    @Test
    func `validate fails for runtime-invalid plan with path and contract`() throws {
        let temp = try TemporaryDirectory()
        let planURL = temp.url.appendingPathComponent("runtime-invalid.heist")
        try writeRuntimeInvalidHeistArtifact(to: planURL)

        let result = try runHeistPlan(["validate", planURL.path])

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("$.body[500]"))
        #expect(result.stderr.contains("max total heist steps"))
    }

    @Test
    func `render-swift prints canonical Swift`() throws {
        let temp = try TemporaryDirectory()
        let planURL = temp.url.appendingPathComponent("valid.heist")
        try HeistArtifactCodec.writePlan(representativePlan(), to: planURL)

        let result = try runHeistPlan(["render-swift", planURL.path])

        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == """
        try HeistPlan("loginFlow") {
            TypeText("alex@example.com", into: .identifier("email"))
                .expect(.present(.value("alex@example.com")), timeout: .seconds(1))

            Warn("done")
        }

        """)
    }

    @Test
    func `canonicalize writes sorted stable JSON`() throws {
        let temp = try TemporaryDirectory()
        let inputURL = temp.url.appendingPathComponent("input.json")
        let outputURL = temp.url.appendingPathComponent("output.heist")
        let plan = try representativePlan()
        try writeCanonicalJSON(plan, to: inputURL)

        let result = try runHeistPlan([
            "canonicalize",
            inputURL.path,
            "--output",
            outputURL.path,
        ])

        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout.isEmpty)
        let output = try String(contentsOf: outputURL.appendingPathComponent("plan.json"), encoding: .utf8)
        let expected = try String(data: canonicalJSONData(plan) + Data([0x0A]), encoding: .utf8)
        #expect(output + "\n" == expected)
        #expect(FileManager.default.fileExists(atPath: outputURL.appendingPathComponent("manifest.json").path))
    }

    @Test
    func `heist plan tool does not import or depend on runtime modules`() throws {
        let root = try repositoryRoot()
        let buttonHeistRoot = try buttonHeistPackageRoot()
        let sourceRoot = buttonHeistRoot.appendingPathComponent("Sources/HeistPlanTool")
        let forbiddenImports = [
            "TheScore",
            "ButtonHeist",
            "TheFence",
            "TheInsideJob",
            "ButtonHeistCLI",
            "ButtonHeistMCP",
            "AccessibilitySnapshotModel",
            "AccessibilitySnapshotParser",
            "MCP",
        ]

        let sourceFiles = try (
            FileManager.default.contentsOfDirectory(at: sourceRoot, includingPropertiesForKeys: nil)
                + FileManager.default.contentsOfDirectory(
                    at: buttonHeistRoot.appendingPathComponent("Sources/ThePlans"),
                    includingPropertiesForKeys: nil
                )
        ).filter { $0.pathExtension == "swift" }

        for file in sourceFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            for forbiddenImport in forbiddenImports {
                #expect(!source.contains("import \(forbiddenImport)"), "\(file.lastPathComponent) imports \(forbiddenImport)")
            }
        }

        for manifest in packageManifests(root: root) {
            let block = try heistPlanToolTargetBlock(in: manifest)
            #expect(block.contains("\"ThePlans\""))
            #expect(block.contains("ArgumentParser"))
            for forbiddenDependency in forbiddenImports {
                #expect(!block.contains("\"\(forbiddenDependency)\""), "HeistPlanTool depends on \(forbiddenDependency)")
            }
        }
    }
}

private func representativePlan() throws -> HeistPlan {
    try HeistPlan("loginFlow") {
        TypeText("alex@example.com", into: .identifier("email"))
            .expect(.present(.value("alex@example.com")), timeout: .seconds(1))

        Warn("done")
    }
}

private func canonicalJSONData(_ plan: HeistPlan) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(plan)
}

private func writeCanonicalJSON(_ plan: HeistPlan, to url: URL) throws {
    try canonicalJSONData(plan).write(to: url)
}

private func writeRuntimeInvalidHeistArtifact(to url: URL) throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    let manifest = HeistArtifactManifest(
        format: heistArtifactFormat,
        entry: "tooManySteps",
        formatVersion: currentHeistArtifactFormatVersion,
        planVersion: currentHeistPlanVersion,
        producer: .buttonHeist,
        createdAt: Date(timeIntervalSince1970: 0)
    )
    try HeistArtifactCodec.canonicalManifestJSONData(manifest)
        .write(to: url.appendingPathComponent(HeistArtifactCodec.manifestFileName))
    try runtimeInvalidPlanJSONData()
        .write(to: url.appendingPathComponent(HeistArtifactCodec.planFileName))
}

private func runtimeInvalidPlanJSONData() throws -> Data {
    let warnStep: [String: Any] = [
        "type": "warn",
        "warn": ["message": "too many steps"],
    ]
    let payload: [String: Any] = [
        "version": currentHeistPlanVersion,
        "name": "tooManySteps",
        "body": Array(repeating: warnStep, count: 501),
    ]
    return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("heist-plan-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

private struct ToolResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

private func runHeistPlan(_ arguments: [String]) throws -> ToolResult {
    let tool = try heistPlanToolURL()
    return try runProcess(executable: tool, arguments: arguments)
}

private func heistPlanToolURL() throws -> URL {
    if let path = ProcessInfo.processInfo.environment["HEIST_PLAN_TOOL"], !path.isEmpty {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        if FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }
    }

    let testExecutable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let debugDirectory = testExecutable
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let buttonHeistRoot = try buttonHeistPackageRoot()
    let candidates = [
        debugDirectory.appendingPathComponent("heist-plan"),
        testExecutable.deletingLastPathComponent().appendingPathComponent("heist-plan"),
        buttonHeistRoot.appendingPathComponent(".build/debug/heist-plan"),
    ]
    for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
        return candidate
    }
    throw TestFailure("heist-plan executable was not built")
}

private func runProcess(executable: URL, arguments: [String]) throws -> ToolResult {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments

    let capture = try ToolOutputCapture()
    process.standardOutput = capture.stdoutHandle
    process.standardError = capture.stderrHandle

    try process.run()
    process.waitUntilExit()

    try capture.close()
    return ToolResult(
        exitCode: process.terminationStatus,
        stdout: try capture.stdoutString(),
        stderr: try capture.stderrString()
    )
}

private final class ToolOutputCapture {
    let stdoutURL: URL
    let stderrURL: URL
    let stdoutHandle: FileHandle
    let stderrHandle: FileHandle

    init() throws {
        let temp = FileManager.default.temporaryDirectory
        stdoutURL = temp.appendingPathComponent("heist-plan-tests-stdout-\(UUID().uuidString)")
        stderrURL = temp.appendingPathComponent("heist-plan-tests-stderr-\(UUID().uuidString)")
        _ = FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        _ = FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        stderrHandle = try FileHandle(forWritingTo: stderrURL)
    }

    deinit {
        try? FileManager.default.removeItem(at: stdoutURL)
        try? FileManager.default.removeItem(at: stderrURL)
    }

    func close() throws {
        try stdoutHandle.close()
        try stderrHandle.close()
    }

    func stdoutString() throws -> String {
        String(data: try Data(contentsOf: stdoutURL), encoding: .utf8) ?? ""
    }

    func stderrString() throws -> String {
        String(data: try Data(contentsOf: stderrURL), encoding: .utf8) ?? ""
    }
}

private func repositoryRoot() throws -> URL {
    let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    if isRepositoryRoot(currentDirectory) {
        return currentDirectory
    }

    var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while candidate.path != candidate.deletingLastPathComponent().path {
        if isRepositoryRoot(candidate) {
            return candidate
        }
        candidate = candidate.deletingLastPathComponent()
    }

    throw TestFailure("could not find repository root")
}

private func isRepositoryRoot(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.appendingPathComponent("ButtonHeist/Package.swift").path)
        && FileManager.default.fileExists(atPath: url.appendingPathComponent("HeistPlanTests/Package.swift").path)
}

private func buttonHeistPackageRoot() throws -> URL {
    try repositoryRoot().appendingPathComponent("ButtonHeist", isDirectory: true)
}

private func packageManifests(root: URL) -> [String] {
    let candidates = [
        root.appendingPathComponent("Package.swift"),
        root.appendingPathComponent("ButtonHeist/Package.swift"),
    ]
    return candidates.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
}

private func heistPlanToolTargetBlock(in manifest: String) throws -> Substring {
    guard let nameRange = manifest.range(of: #"name: "HeistPlanTool""#) else {
        throw TestFailure("manifest does not declare HeistPlanTool")
    }
    guard let start = manifest[..<nameRange.lowerBound].range(of: ".executableTarget(", options: .backwards)?.lowerBound else {
        throw TestFailure("HeistPlanTool is not an executable target")
    }

    var depth = 0
    var foundOpenParen = false
    for index in manifest[start...].indices {
        switch manifest[index] {
        case "(":
            depth += 1
            foundOpenParen = true
        case ")":
            depth -= 1
            if foundOpenParen, depth == 0 {
                return manifest[start...index]
            }
        default:
            break
        }
    }

    throw TestFailure("could not parse HeistPlanTool target declaration")
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
