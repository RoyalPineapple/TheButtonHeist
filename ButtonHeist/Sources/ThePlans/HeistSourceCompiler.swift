import Foundation

extension HeistPlan {
    static func decodeValidatedHeistJSON(
        from data: Data,
        sourceURL: URL = URL(fileURLWithPath: "compiled-swift-heist-output.json")
    ) throws -> HeistPlan {
        let raw = try HeistArtifactCodec.decodeUnvalidatedPlanJSON(
            data,
            at: sourceURL
        )
        return try raw.validatedForRuntime()
    }
}

public extension HeistPlan {
    func canonicalHeistJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

enum HeistSourceInput: Sendable, Equatable {
    case inlinePlanSource(source: String, sourceName: String)
#if os(macOS) || os(Linux)
    case swiftFile(URL, entry: String)
#endif
}

struct HeistSourceCompiler: Sendable {
    let packageRoot: URL?

    init(packageRoot: URL? = nil) {
        self.packageRoot = packageRoot
    }

    func compile(_ source: HeistSourceInput) throws -> HeistPlan {
        switch source {
        case .inlinePlanSource(let source, let sourceName):
            return try HeistPlanSourceCompiler().compile(source, sourceName: sourceName)
#if os(macOS) || os(Linux)
        case .swiftFile(let url, let entry):
            return try HeistSwiftFileSourceCompiler(packageRoot: packageRoot)
                .compileSwiftFile(url, entry: entry)
#endif
        }
    }

    func compileHeistPlanSource(
        _ source: String,
        sourceName: String = "inline-heist-plan"
    ) throws -> HeistPlan {
        try compile(.inlinePlanSource(source: source, sourceName: sourceName))
    }

#if os(macOS) || os(Linux)
    func compileSwiftFile(
        _ source: URL,
        entry: String
    ) throws -> HeistPlan {
        try compile(.swiftFile(source, entry: entry))
    }
#endif
}

#if os(macOS) || os(Linux)
private struct HeistSwiftFileSourceCompiler: Sendable {
    let packageRoot: URL?

    init(packageRoot: URL? = nil) {
        self.packageRoot = packageRoot
    }

    /// Persistent, shared swiftc module cache for plan compilation. Reused
    /// across compiles so the Foundation/ThePlans module interfaces are built
    /// once per toolchain rather than on every plan.
    static let sharedModuleCacheDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("buttonheist-heist-plan-module-cache", isDirectory: true)

    func compileSwiftFile(
        _ source: URL,
        entry: String
    ) throws -> HeistPlan {
        let entry = try HeistSourceEntrySymbol(validating: entry)
        let source = source.standardizedFileURL
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw HeistSourceCompilerError.sourceFileNotFound(source.path)
        }

        HeistSourceCompilerTrace.write("preparing Swift heist compile")
        let artifacts = try ThePlansBuildArtifacts.resolve(explicitPackageRoot: packageRoot)
        HeistSourceCompilerTrace.write("using built ThePlans artifacts at \(artifacts.buildDirectory.path)")

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("heist-source-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let buildDirectory = tempURL.appendingPathComponent("Build", isDirectory: true)
        try FileManager.default.createDirectory(at: buildDirectory, withIntermediateDirectories: true)

        // Persist the module cache across compiles. A fresh per-compile cache
        // forced swiftc to rebuild the Foundation/ThePlans module interfaces on
        // every run — the dominant per-plan cost (~2.5s of ~3s). swiftc keys
        // cache entries by content hash, so sharing the path is safe and warm
        // compiles drop to sub-second.
        let moduleCache = Self.sharedModuleCacheDirectory
        try FileManager.default.createDirectory(at: moduleCache, withIntermediateDirectories: true)

        var compileDiagnostics: [String] = []
        for resolution in HeistSourceEntryResolution.allCases {
            let compileDirectory = try writeCompileDirectory(
                at: tempURL,
                source: source,
                entry: entry,
                resolution: resolution
            )

            do {
                return try compile(
                    source: source,
                    compileDirectory: compileDirectory,
                    buildDirectory: buildDirectory,
                    moduleCache: moduleCache,
                    artifacts: artifacts
                )
            } catch let error as HeistSourceCompilerError {
                guard case .compileFailed(_, let diagnostics) = error else {
                    throw error
                }
                compileDiagnostics.append(diagnostics)
            }
        }

        throw HeistSourceCompilerError.compileFailed(
            source.path,
            compileDiagnostics.joined(separator: "\n")
        )
    }

    private func compile(
        source: URL,
        compileDirectory: URL,
        buildDirectory: URL,
        moduleCache: URL,
        artifacts: ThePlansBuildArtifacts
    ) throws -> HeistPlan {
        let executableURL = buildDirectory.appendingPathComponent("plan-compiler")
        HeistSourceCompilerTrace.write("compiling Swift heist wrapper against built ThePlans artifacts")
        let compilerResult = try ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: swiftcPlanCompilerArguments(
                compileDirectory: compileDirectory,
                moduleCache: moduleCache,
                executableURL: executableURL,
                artifacts: artifacts
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
            throw HeistSourceCompilerError.executionFailed(
                source.path,
                result.diagnostics
            )
        }

        do {
            return try HeistPlan.decodeValidatedHeistJSON(from: result.stdout, sourceURL: source)
        } catch let error as HeistPlanValidationError {
            throw HeistSourceCompilerError.runtimeValidationFailed(error.description)
        } catch {
            throw HeistSourceCompilerError.invalidCompilerOutput(String(describing: error))
        }
    }

    private func writeCompileDirectory(
        at tempURL: URL,
        source: URL,
        entry: HeistSourceEntrySymbol,
        resolution: HeistSourceEntryResolution
    ) throws -> URL {
        let sourcesURL = tempURL
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("PlanCompiler", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)

        let userSource = try String(contentsOf: source, encoding: .utf8)
        let wrapper = """
        \(sourceLocationDirective(for: source))
        \(userSource)

        #sourceLocation()
        import Foundation
        import ThePlans

        let plan: HeistPlan = \(resolution.planExpression(for: entry))
        FileHandle.standardOutput.write(try plan.canonicalHeistJSONData())
        """
        try wrapper.write(
            to: sourcesURL.appendingPathComponent("main.swift"),
            atomically: true,
            encoding: .utf8
        )
        return sourcesURL
    }

    private func swiftcPlanCompilerArguments(
        compileDirectory: URL,
        moduleCache: URL,
        executableURL: URL,
        artifacts: ThePlansBuildArtifacts
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
            "-o",
            executableURL.path,
            compileDirectory.appendingPathComponent("main.swift").path,
        ]
        arguments.append(contentsOf: artifacts.swiftcArguments)
        return arguments
    }

    private func sourceLocationDirective(for source: URL) -> String {
        "#sourceLocation(file: \(swiftStringLiteral(source.path)), line: 1)"
    }

    private func swiftStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: #"\"#, with: #"\\"#)
            .replacingOccurrences(of: #"""#, with: #"\""#)
        return #""\#(escaped)""#
    }
}

enum HeistSourceCompilerError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidEntry(String)
    case sourceFileNotFound(String)
    case packageRootNotFound
    case buildArtifactsNotFound(searched: [String], hint: String)
    case compileFailed(String, String)
    case executionFailed(String, String)
    case invalidCompilerOutput(String)
    case runtimeValidationFailed(String)

    var description: String {
        switch self {
        case .invalidEntry(let entry):
            return "invalid Swift heist entry symbol: \(entry)"
        case .sourceFileNotFound(let path):
            return "Swift heist source file not found: \(path)"
        case .packageRootNotFound:
            return """
            could not locate a local ButtonHeist package root containing Sources/ThePlans. \
            Run the compiler from inside a ButtonHeist checkout, or set HEIST_THEPLANS_BUILD_DIR \
            to a directory holding built ThePlans artifacts \
            (Modules/ThePlans.swiftmodule and ThePlans.build/*.swift.o).
            """
        case .buildArtifactsNotFound(let searched, let hint):
            let searchedList = searched.map { "  - \($0)" }.joined(separator: "\n")
            return """
            could not find built ThePlans artifacts for Swift compilation.
            searched:
            \(searchedList)
            \(hint)
            """
        case .compileFailed(let path, let diagnostics):
            return "failed to compile Swift heist source \(path): \(diagnostics)"
        case .executionFailed(let path, let diagnostics):
            return "compiled Swift heist source \(path) failed while evaluating entry: \(diagnostics)"
        case .invalidCompilerOutput(let diagnostics):
            return "compiled Swift heist did not emit valid HeistPlan JSON: \(diagnostics)"
        case .runtimeValidationFailed(let diagnostics):
            return "compiled Swift heist failed runtime validation: \(diagnostics)"
        }
    }
}

private enum HeistSourceEntryResolution: CaseIterable {
    case value
    case function

    func planExpression(for entry: HeistSourceEntrySymbol) -> String {
        switch self {
        case .value:
            return entry.name
        case .function:
            return "try \(entry.name)()"
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
        guard let packageRoot = resolveCandidates().first else {
            throw HeistSourceCompilerError.packageRootNotFound
        }
        return packageRoot
    }

    static func resolveCandidates() -> [URL] {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let sourceURL = URL(fileURLWithPath: #filePath).standardizedFileURL
        let candidates = candidateRoots(from: currentDirectory)
            + candidateRoots(from: executableURL)
            + candidateRoots(from: sourceURL)

        var packageRoots: [URL] = []
        for candidate in candidates {
            if isButtonHeistPackageRoot(candidate) {
                appendUnique(candidate, to: &packageRoots)
            }
            let nested = candidate.appendingPathComponent("ButtonHeist", isDirectory: true)
            if isButtonHeistPackageRoot(nested) {
                appendUnique(nested, to: &packageRoots)
            }
            let sibling = candidate
                .deletingLastPathComponent()
                .appendingPathComponent("ButtonHeist", isDirectory: true)
            if isButtonHeistPackageRoot(sibling) {
                appendUnique(sibling, to: &packageRoots)
            }
        }

        return packageRoots
    }

    private static func appendUnique(_ url: URL, to urls: inout [URL]) {
        let standardized = url.standardizedFileURL
        guard !urls.contains(standardized) else { return }
        urls.append(standardized)
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

/// The single resolution path for built ThePlans artifacts used by Swift heist
/// compilation. `HEIST_THEPLANS_BUILD_DIR` is the deterministic override; absent
/// it, the local package's `.build` directories are searched. Both routes feed
/// the same compile path, and a miss reports what was searched and how to fix it.
private struct ThePlansBuildArtifacts {
    static let environmentOverrideKey = "HEIST_THEPLANS_BUILD_DIR"

    let buildDirectory: URL
    let swiftcArguments: [String]

    static func resolve(explicitPackageRoot: URL?) throws -> ThePlansBuildArtifacts {
        if let override = environmentOverridePath() {
            HeistSourceCompilerTrace.write("resolving \(environmentOverrideKey) override at \(override)")
            let buildDirectory = URL(fileURLWithPath: override, isDirectory: true)
            if let artifacts = try resolveSwiftPMBuildDirectory(buildDirectory) {
                return artifacts
            }
            if let artifacts = resolveXcodeProductsDirectory(buildDirectory) {
                return artifacts
            }
            throw HeistSourceCompilerError.buildArtifactsNotFound(
                searched: [buildDirectory.path],
                hint: """
                \(environmentOverrideKey)=\(override) does not contain built ThePlans artifacts \
                (expected Modules/ThePlans.swiftmodule and ThePlans.build/*.swift.o, or \
                ThePlans.framework in an Xcode products directory). \
                Build them with `swift build --package-path ButtonHeist --product heist-plan` \
                and point \(environmentOverrideKey) at ButtonHeist/.build/debug.
                """
            )
        }

        let packageRoots: [URL]
        if let explicitPackageRoot {
            packageRoots = [explicitPackageRoot.standardizedFileURL]
        } else {
            HeistSourceCompilerTrace.write("resolving ButtonHeist package roots")
            packageRoots = LocalThePlansPackage.resolveCandidates()
        }
        guard !packageRoots.isEmpty else {
            throw HeistSourceCompilerError.packageRootNotFound
        }

        var searched: [String] = []
        for packageRoot in packageRoots {
            HeistSourceCompilerTrace.write("checking ButtonHeist package root: \(packageRoot.path)")
            let swiftPMCandidates = try candidateBuildDirectories(in: packageRoot)
            searched.append(contentsOf: swiftPMCandidates.map(\.path))
            for buildDirectory in swiftPMCandidates {
                if let artifacts = try resolveSwiftPMBuildDirectory(buildDirectory) {
                    return artifacts
                }
            }

            let xcodeCandidates = candidateXcodeProductsDirectories(packageRoot: packageRoot)
            searched.append(contentsOf: xcodeCandidates.map(\.path))
            for productsDirectory in xcodeCandidates {
                if let artifacts = resolveXcodeProductsDirectory(productsDirectory) {
                    return artifacts
                }
            }
        }

        throw HeistSourceCompilerError.buildArtifactsNotFound(
            searched: searched,
            hint: """
            No built ThePlans artifacts found under \
            \(packageRoots.map { $0.appendingPathComponent(".build").path }.joined(separator: " or ")). \
            Build them with `swift build --package-path ButtonHeist --product heist-plan`, \
            or set \(environmentOverrideKey) to a directory containing \
            Modules/ThePlans.swiftmodule and ThePlans.build/*.swift.o. \
            Xcode test runs can also provide a products directory containing ThePlans.framework.
            """
        )
    }

    private static func environmentOverridePath() -> String? {
        guard let override = ProcessInfo.processInfo.environment[environmentOverrideKey],
              !override.isEmpty else {
            return nil
        }
        return override
    }

    private static func resolveSwiftPMBuildDirectory(_ buildDirectory: URL) throws -> ThePlansBuildArtifacts? {
        let modulesDirectory = buildDirectory.appendingPathComponent("Modules", isDirectory: true)
        let module = modulesDirectory.appendingPathComponent("ThePlans.swiftmodule")
        let objectsDirectory = buildDirectory.appendingPathComponent("ThePlans.build", isDirectory: true)
        guard FileManager.default.fileExists(atPath: module.path) else {
            return nil
        }
        let objectFiles = try activeSwiftObjectFiles(
            in: buildDirectory,
            moduleName: "ThePlans"
        ) ?? swiftObjectFiles(in: objectsDirectory)
        guard !objectFiles.isEmpty else {
            return nil
        }
        return ThePlansBuildArtifacts(
            buildDirectory: buildDirectory,
            swiftcArguments: [
                "-I",
                modulesDirectory.path,
            ] + objectFiles.map(\.path)
        )
    }

    private static func resolveXcodeProductsDirectory(_ productsDirectory: URL) -> ThePlansBuildArtifacts? {
        let frameworkDirectory = productsDirectory.appendingPathComponent("ThePlans.framework", isDirectory: true)
        let binary = frameworkDirectory.appendingPathComponent("ThePlans")
        let swiftModuleDirectory = frameworkDirectory
            .appendingPathComponent("Modules", isDirectory: true)
            .appendingPathComponent("ThePlans.swiftmodule", isDirectory: true)
        guard FileManager.default.fileExists(atPath: binary.path),
              FileManager.default.fileExists(atPath: swiftModuleDirectory.path) else {
            return nil
        }
        return ThePlansBuildArtifacts(
            buildDirectory: productsDirectory,
            swiftcArguments: [
                "-F",
                productsDirectory.path,
                "-Xlinker",
                "-rpath",
                "-Xlinker",
                productsDirectory.path,
                "-framework",
                "ThePlans",
            ]
        )
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

    private static func candidateXcodeProductsDirectories(packageRoot: URL) -> [URL] {
        let environmentKeys = [
            "BUILT_PRODUCTS_DIR",
            "TARGET_BUILD_DIR",
            "CONFIGURATION_BUILD_DIR",
        ]
        let environmentDirectories = environmentKeys.compactMap { key -> URL? in
            guard let value = ProcessInfo.processInfo.environment[key], !value.isEmpty else {
                return nil
            }
            return URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
        }
        let seedURLs = environmentDirectories + [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
            URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL,
            URL(fileURLWithPath: #filePath).standardizedFileURL,
            packageRoot,
        ]

        var seen = Set<String>()
        var candidates: [URL] = []
        for seedURL in seedURLs {
            for candidate in ancestorDirectories(from: seedURL, maxDepth: 8) {
                let path = candidate.path
                guard seen.insert(path).inserted else { continue }
                candidates.append(candidate)
            }
        }
        return candidates
    }

    private static func ancestorDirectories(from url: URL, maxDepth: Int) -> [URL] {
        var directories: [URL] = []
        var current = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        while directories.count < maxDepth && current.path != current.deletingLastPathComponent().path {
            directories.append(current)
            current = current.deletingLastPathComponent()
        }
        return directories
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

    private static func activeSwiftObjectFiles(
        in buildDirectory: URL,
        moduleName: String
    ) throws -> [URL]? {
        let descriptionURL = buildDirectory.appendingPathComponent("description.json")
        guard let data = try? Data(contentsOf: descriptionURL),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let swiftCommands = root["swiftCommands"] as? [String: Any] else {
            return nil
        }

        for commandValue in swiftCommands.values {
            guard let command = commandValue as? [String: Any],
                  command["moduleName"] as? String == moduleName,
                  let objectPaths = command["objects"] as? [String] else {
                continue
            }

            let objectFiles = try objectPaths.compactMap { path -> URL? in
                let url = URL(fileURLWithPath: path)
                guard url.lastPathComponent.hasSuffix(".swift.o") else { return nil }
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { return nil }
                return url
            }
            return objectFiles.sorted { $0.path < $1.path }
        }

        return nil
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
