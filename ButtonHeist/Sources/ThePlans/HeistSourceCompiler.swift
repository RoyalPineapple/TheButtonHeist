import Foundation

public extension HeistPlan {
    static func decodeValidatedHeistJSON(from data: Data) throws -> HeistPlan {
        let plan = try JSONDecoder().decode(HeistPlan.self, from: data)
        try plan.assertRuntimeAdmissible()
        return plan
    }

    func canonicalHeistJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

#if os(macOS)
public struct HeistSourceCompiler: Sendable {
    public let packageRoot: URL?

    public init(packageRoot: URL? = nil) {
        self.packageRoot = packageRoot
    }

    public func compileSwiftFile(
        _ source: URL,
        entry: String
    ) throws -> HeistPlan {
        let entry = try HeistSourceEntrySymbol(validating: entry)
        let source = source.standardizedFileURL
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw HeistSourceCompilerError.sourceFileNotFound(source.path)
        }

        let packageRoot = try packageRoot ?? LocalThePlansPackage.resolve()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("heist-source-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try writeCompilePackage(
            at: tempURL,
            source: source,
            packageRoot: packageRoot,
            entry: entry
        )

        let result = try ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "swift",
                "run",
                "--package-path",
                tempURL.path,
                "--quiet",
                "plan-compiler",
            ]
        )

        guard result.exitCode == 0 else {
            throw HeistSourceCompilerError.compileFailed(
                source.path,
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        do {
            return try HeistPlan.decodeValidatedHeistJSON(from: result.stdout)
        } catch {
            throw HeistSourceCompilerError.invalidCompilerOutput(String(describing: error))
        }
    }

    private func writeCompilePackage(
        at tempURL: URL,
        source: URL,
        packageRoot: URL,
        entry: HeistSourceEntrySymbol
    ) throws {
        let sourcesURL = tempURL
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("PlanCompiler", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)

        let packageManifest = """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "HeistSourceCompile",
            platforms: [.macOS(.v14)],
            products: [
                .executable(name: "plan-compiler", targets: ["PlanCompiler"]),
            ],
            dependencies: [
                .package(path: \(swiftStringLiteral(packageRoot.path))),
            ],
            targets: [
                .executableTarget(
                    name: "PlanCompiler",
                    dependencies: [
                        .product(name: "ThePlans", package: "ButtonHeist"),
                    ]
                ),
            ]
        )
        """
        try packageManifest.write(
            to: tempURL.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        let userSource = try String(contentsOf: source, encoding: .utf8)
        try userSource.write(
            to: sourcesURL.appendingPathComponent("PlanSource.swift"),
            atomically: true,
            encoding: .utf8
        )

        let wrapper = """
        import Foundation
        import ThePlans

        let plan: HeistPlan = try \(entry.name)()
        try plan.assertRuntimeAdmissible()
        FileHandle.standardOutput.write(try plan.canonicalHeistJSONData())
        """
        try wrapper.write(
            to: sourcesURL.appendingPathComponent("main.swift"),
            atomically: true,
            encoding: .utf8
        )
    }
}

public enum HeistSourceCompilerError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidEntry(String)
    case sourceFileNotFound(String)
    case packageRootNotFound
    case compileFailed(String, String)
    case invalidCompilerOutput(String)

    public var description: String {
        switch self {
        case .invalidEntry(let entry):
            return "invalid Swift heist entry symbol: \(entry)"
        case .sourceFileNotFound(let path):
            return "Swift heist source file not found: \(path)"
        case .packageRootNotFound:
            return "could not find local ButtonHeist package root for ThePlans"
        case .compileFailed(let path, let diagnostics):
            return "failed to compile Swift heist source \(path): \(diagnostics)"
        case .invalidCompilerOutput(let diagnostics):
            return "compiled Swift heist did not emit valid .heist JSON: \(diagnostics)"
        }
    }
}

private struct HeistSourceEntrySymbol {
    let name: String

    init(validating name: String) throws {
        let identifier = #"[A-Za-z_][A-Za-z0-9_]*"#
        let pattern = #"^\#(identifier)(\.\#(identifier))*$"#
        guard name.range(of: pattern, options: .regularExpression) != nil else {
            throw HeistSourceCompilerError.invalidEntry(name)
        }
        self.name = name
    }
}

private enum LocalThePlansPackage {
    static func resolve() throws -> URL {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let sourceURL = URL(fileURLWithPath: #filePath).standardizedFileURL
        let candidates = candidateRoots(from: currentDirectory)
            + candidateRoots(from: executableURL)
            + candidateRoots(from: sourceURL)

        for candidate in candidates {
            let nested = candidate.appendingPathComponent("ButtonHeist", isDirectory: true)
            if isButtonHeistPackageRoot(nested) {
                return nested
            }
            if isButtonHeistPackageRoot(candidate) {
                return candidate
            }
            let sibling = candidate
                .deletingLastPathComponent()
                .appendingPathComponent("ButtonHeist", isDirectory: true)
            if isButtonHeistPackageRoot(sibling) {
                return sibling
            }
        }

        throw HeistSourceCompilerError.packageRootNotFound
    }

    private static func candidateRoots(from url: URL) -> [URL] {
        var roots: [URL] = []
        var current = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        while current.path != current.deletingLastPathComponent().path {
            roots.append(current)
            current = current.deletingLastPathComponent()
        }
        roots.append(current)
        return roots
    }

    private static func isButtonHeistPackageRoot(_ url: URL) -> Bool {
        let manifest = url.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: manifest.path) else { return false }
        let nestedSources = url.appendingPathComponent("Sources/ThePlans")
        let rootSources = url.appendingPathComponent("ButtonHeist/Sources/ThePlans")
        return FileManager.default.fileExists(atPath: nestedSources.path)
            || FileManager.default.fileExists(atPath: rootSources.path)
    }
}

private struct ProcessResult {
    let exitCode: Int32
    let stdout: Data
    let stderr: String
}

private enum ProcessRunner {
    static func run(executable: URL, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let capture = try ProcessOutputCapture()
        process.standardOutput = capture.stdoutHandle
        process.standardError = capture.stderrHandle

        try process.run()
        process.waitUntilExit()

        try capture.close()
        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: try capture.stdoutData(),
            stderr: try capture.stderrString()
        )
    }
}

private final class ProcessOutputCapture {
    let stdoutURL: URL
    let stderrURL: URL
    let stdoutHandle: FileHandle
    let stderrHandle: FileHandle

    init() throws {
        let temp = FileManager.default.temporaryDirectory
        stdoutURL = temp.appendingPathComponent("heist-source-stdout-\(UUID().uuidString)")
        stderrURL = temp.appendingPathComponent("heist-source-stderr-\(UUID().uuidString)")
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

    func stdoutData() throws -> Data {
        try Data(contentsOf: stdoutURL)
    }

    func stderrString() throws -> String {
        let data = try Data(contentsOf: stderrURL)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private func swiftStringLiteral(_ value: String) -> String {
    var result = "\""
    for scalar in value.unicodeScalars {
        switch scalar {
        case "\\":
            result += "\\\\"
        case "\"":
            result += "\\\""
        case "\n":
            result += #"\n"#
        case "\r":
            result += #"\r"#
        case "\t":
            result += #"\t"#
        default:
            result.unicodeScalars.append(scalar)
        }
    }
    result += "\""
    return result
}
#endif
