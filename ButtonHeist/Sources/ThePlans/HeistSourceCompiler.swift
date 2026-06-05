import Foundation

public extension HeistPlan {
    static func decodeValidatedHeistJSON(
        from data: Data,
        sourceURL: URL = URL(fileURLWithPath: "compiled-swift-heist-output.json")
    ) throws -> HeistPlan {
        let plan = try HeistArtifactCodec.decodePlanJSON(
            data,
            at: sourceURL
        )
        try plan.assertRuntimeAdmissible()
        return plan
    }

    func canonicalHeistJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

#if os(macOS) || os(Linux)
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

        HeistSourceCompilerTrace.write("preparing Swift heist compile")
        let packageRoot = try packageRoot ?? LocalThePlansPackage.resolve()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("heist-source-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let compileDirectory = try writeCompileDirectory(
            at: tempURL,
            source: source,
            entry: entry
        )

        let buildDirectory = tempURL.appendingPathComponent("Build", isDirectory: true)
        try FileManager.default.createDirectory(at: buildDirectory, withIntermediateDirectories: true)
        let moduleCache = buildDirectory.appendingPathComponent("ModuleCache", isDirectory: true)
        try FileManager.default.createDirectory(at: moduleCache, withIntermediateDirectories: true)

        if let artifacts = try ThePlansBuildArtifacts.resolve(in: packageRoot) {
            return try compileWithBuiltThePlansArtifacts(
                source: source,
                compileDirectory: compileDirectory,
                buildDirectory: buildDirectory,
                moduleCache: moduleCache,
                artifacts: artifacts
            )
        }

        let thePlansSource = try LocalThePlansPackage.thePlansSourceDirectory(in: packageRoot)

        HeistSourceCompilerTrace.write("compiling ThePlans module")
        let moduleResult = try ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: swiftcThePlansArguments(
                sourceDirectory: thePlansSource,
                buildDirectory: buildDirectory,
                moduleCache: moduleCache
            )
        )
        guard moduleResult.exitCode == 0 else {
            throw HeistSourceCompilerError.compileFailed(
                source.path,
                moduleResult.diagnostics
            )
        }

        let executableURL = buildDirectory.appendingPathComponent("plan-compiler")
        HeistSourceCompilerTrace.write("compiling Swift heist wrapper")
        let compilerResult = try ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: swiftcPlanCompilerArguments(
                compileDirectory: compileDirectory,
                buildDirectory: buildDirectory,
                moduleCache: moduleCache,
                executableURL: executableURL
            )
        )
        guard compilerResult.exitCode == 0 else {
            throw HeistSourceCompilerError.compileFailed(
                source.path,
                compilerResult.diagnostics
            )
        }

        HeistSourceCompilerTrace.write("running Swift heist wrapper")
        let result = try ProcessRunner.run(
            executable: executableURL,
            arguments: []
        )

        guard result.exitCode == 0 else {
            throw HeistSourceCompilerError.compileFailed(
                source.path,
                result.diagnostics
            )
        }

        do {
            return try HeistPlan.decodeValidatedHeistJSON(from: result.stdout, sourceURL: source)
        } catch {
            throw HeistSourceCompilerError.invalidCompilerOutput(String(describing: error))
        }
    }

    private func compileWithBuiltThePlansArtifacts(
        source: URL,
        compileDirectory: URL,
        buildDirectory: URL,
        moduleCache: URL,
        artifacts: ThePlansBuildArtifacts
    ) throws -> HeistPlan {
        let executableURL = buildDirectory.appendingPathComponent("plan-compiler")
        HeistSourceCompilerTrace.write("compiling Swift heist wrapper with built ThePlans artifacts")
        let compilerResult = try ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: swiftcPlanCompilerArguments(
                compileDirectory: compileDirectory,
                buildDirectory: buildDirectory,
                moduleCache: moduleCache,
                executableURL: executableURL,
                builtArtifacts: artifacts
            )
        )
        guard compilerResult.exitCode == 0 else {
            throw HeistSourceCompilerError.compileFailed(
                source.path,
                compilerResult.diagnostics
            )
        }

        HeistSourceCompilerTrace.write("running Swift heist wrapper")
        let result = try ProcessRunner.run(
            executable: executableURL,
            arguments: []
        )

        guard result.exitCode == 0 else {
            throw HeistSourceCompilerError.compileFailed(
                source.path,
                result.diagnostics
            )
        }

        do {
            return try HeistPlan.decodeValidatedHeistJSON(from: result.stdout, sourceURL: source)
        } catch {
            throw HeistSourceCompilerError.invalidCompilerOutput(String(describing: error))
        }
    }

    private func writeCompileDirectory(
        at tempURL: URL,
        source: URL,
        entry: HeistSourceEntrySymbol
    ) throws -> URL {
        let sourcesURL = tempURL
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("PlanCompiler", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)

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
        return sourcesURL
    }

    private func swiftcThePlansArguments(
        sourceDirectory: URL,
        buildDirectory: URL,
        moduleCache: URL
    ) throws -> [String] {
        let libraryURL = buildDirectory
            .appendingPathComponent("libThePlans.\(Self.dynamicLibraryExtension)")
        let moduleURL = buildDirectory.appendingPathComponent("ThePlans.swiftmodule")
        var arguments = [
            "swiftc",
            "-j",
            "1",
            "-num-threads",
            "1",
            "-emit-library",
            "-emit-module",
            "-module-name",
            "ThePlans",
            "-parse-as-library",
            "-swift-version",
            "6",
            "-module-cache-path",
            moduleCache.path,
            "-emit-module-path",
            moduleURL.path,
            "-o",
            libraryURL.path,
        ]
        arguments.append(contentsOf: try swiftSourceFiles(in: sourceDirectory).map(\.path))
        return arguments
    }

    private func swiftcPlanCompilerArguments(
        compileDirectory: URL,
        buildDirectory: URL,
        moduleCache: URL,
        executableURL: URL,
        builtArtifacts: ThePlansBuildArtifacts? = nil
    ) -> [String] {
        var arguments = [
            "swiftc",
            "-j",
            "1",
            "-num-threads",
            "1",
            "-swift-version",
            "6",
            "-module-cache-path",
            moduleCache.path,
            "-I",
            builtArtifacts?.modulesDirectory.path ?? buildDirectory.path,
            "-o",
            executableURL.path,
            compileDirectory.appendingPathComponent("PlanSource.swift").path,
            compileDirectory.appendingPathComponent("main.swift").path,
        ]

        if let builtArtifacts {
            arguments.append(contentsOf: builtArtifacts.objectFiles.map(\.path))
        } else {
            arguments.append(contentsOf: [
                "-L",
                buildDirectory.path,
                "-lThePlans",
                "-Xlinker",
                "-rpath",
                "-Xlinker",
                buildDirectory.path,
            ])
        }

        return arguments
    }

    private func swiftSourceFiles(in sourceDirectory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw HeistSourceCompilerError.packageRootNotFound
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                files.append(fileURL)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private static var dynamicLibraryExtension: String {
        #if os(macOS)
        "dylib"
        #else
        "so"
        #endif
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
            return "compiled Swift heist did not emit valid HeistPlan JSON: \(diagnostics)"
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

    static func thePlansSourceDirectory(in packageRoot: URL) throws -> URL {
        let direct = packageRoot.appendingPathComponent("Sources/ThePlans", isDirectory: true)
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }

        let nested = packageRoot.appendingPathComponent("ButtonHeist/Sources/ThePlans", isDirectory: true)
        if FileManager.default.fileExists(atPath: nested.path) {
            return nested
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

private struct ThePlansBuildArtifacts {
    let modulesDirectory: URL
    let objectFiles: [URL]

    static func resolve(in packageRoot: URL) throws -> ThePlansBuildArtifacts? {
        for buildDirectory in try candidateBuildDirectories(in: packageRoot) {
            let modulesDirectory = buildDirectory.appendingPathComponent("Modules", isDirectory: true)
            let module = modulesDirectory.appendingPathComponent("ThePlans.swiftmodule")
            let objectsDirectory = buildDirectory.appendingPathComponent("ThePlans.build", isDirectory: true)
            guard FileManager.default.fileExists(atPath: module.path) else {
                continue
            }
            let objectFiles = try swiftObjectFiles(in: objectsDirectory)
            guard !objectFiles.isEmpty else {
                continue
            }
            return ThePlansBuildArtifacts(
                modulesDirectory: modulesDirectory,
                objectFiles: objectFiles
            )
        }

        return nil
    }

    private static func candidateBuildDirectories(in packageRoot: URL) throws -> [URL] {
        let buildRoot = packageRoot.appendingPathComponent(".build", isDirectory: true)
        var candidates = [
            buildRoot.appendingPathComponent("debug", isDirectory: true),
            buildRoot.appendingPathComponent("release", isDirectory: true),
        ]

        if let entries = try? FileManager.default.contentsOfDirectory(
            at: buildRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for entry in entries {
                let values = try entry.resourceValues(forKeys: [.isDirectoryKey])
                guard values.isDirectory == true else { continue }
                candidates.append(entry.appendingPathComponent("debug", isDirectory: true))
                candidates.append(entry.appendingPathComponent("release", isDirectory: true))
            }
        }

        return candidates
    }

    private static func swiftObjectFiles(in directory: URL) throws -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try entries
            .filter { $0.lastPathComponent.hasSuffix(".swift.o") }
            .filter {
                let values = try $0.resourceValues(forKeys: [.isRegularFileKey])
                return values.isRegularFile == true
            }
            .sorted { $0.path < $1.path }
    }
}

private struct ProcessResult {
    let exitCode: Int32
    let stdout: Data
    let stderr: String

    var diagnostics: String {
        let stdoutText = String(data: stdout, encoding: .utf8) ?? ""
        return [stderr, stdoutText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
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

private enum HeistSourceCompilerTrace {
    static func write(_ message: String) {
        guard ProcessInfo.processInfo.environment["HEIST_SOURCE_COMPILER_TRACE"] == "1" else {
            return
        }

        let line = "heist-source-compiler: \(message)\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
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
        let openedStdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        do {
            stderrHandle = try FileHandle(forWritingTo: stderrURL)
            stdoutHandle = openedStdoutHandle
        } catch {
            try? openedStdoutHandle.close()
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
            throw error
        }
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

#endif
