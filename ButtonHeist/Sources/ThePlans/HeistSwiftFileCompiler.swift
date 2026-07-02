import Foundation

#if os(macOS) || os(Linux)
private struct HeistSwiftFileCompilerEnvironmentKey: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "Environment key must not be empty")
        self.rawValue = rawValue
    }

    private init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    var description: String {
        rawValue
    }

    static let thePlansBuildDirectory = Self("HEIST_THEPLANS_BUILD_DIR")
    static let path = Self("PATH")
    static let builtProductsDirectory = Self("BUILT_PRODUCTS_DIR")
    static let targetBuildDirectory = Self("TARGET_BUILD_DIR")
    static let configurationBuildDirectory = Self("CONFIGURATION_BUILD_DIR")
    static let sourceCompilerTrace = Self("HEIST_SOURCE_COMPILER_TRACE")

    static let xcodeProductsDirectories: [HeistSwiftFileCompilerEnvironmentKey] = [
        .builtProductsDirectory,
        .targetBuildDirectory,
        .configurationBuildDirectory,
    ]
}

private extension Dictionary where Key == String, Value == String {
    subscript(_ key: HeistSwiftFileCompilerEnvironmentKey) -> String? {
        self[key.rawValue]
    }
}

struct HeistSwiftFileCompiler: Sendable {
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
        let entry = try HeistSwiftFileEntrySymbol(validating: entry)
        let source = source.standardizedFileURL
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw HeistSwiftFileCompilerError.sourceFileNotFound(source.path)
        }
        HeistSwiftFileCompilerTrace.write("preparing Swift heist compile")
        let artifacts = try ThePlansBuildArtifacts.resolve(explicitPackageRoot: packageRoot)
        HeistSwiftFileCompilerTrace.write("using built ThePlans artifacts at \(artifacts.buildDirectory.path)")

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
        for resolution in HeistSwiftFileEntryResolution.allCases {
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
            } catch let error as HeistSwiftFileCompilerError {
                guard case .compileFailed(_, let diagnostics) = error else {
                    throw error
                }
                compileDiagnostics.append(diagnostics)
            }
        }

        throw HeistSwiftFileCompilerError.compileFailed(
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
        HeistSwiftFileCompilerTrace.write("compiling Swift heist wrapper against built ThePlans artifacts")
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
            throw HeistSwiftFileCompilerError.compileFailed(
                source.path,
                compilerResult.diagnostics
            )
        }

        HeistSwiftFileCompilerTrace.write("running Swift heist wrapper")
        let result = try ProcessRunner.run(
            executable: executableURL,
            arguments: []
        )

        guard result.exitCode == 0 else {
            throw HeistSwiftFileCompilerError.executionFailed(
                source.path,
                result.diagnostics
            )
        }

        do {
            return try HeistPlanJSONCodec.decodeValidatedPlan(result.stdout, sourceURL: source)
        } catch let error as HeistPlanJSONCodecError {
            throw HeistSwiftFileCompilerError.invalidCompilerOutput(error.description)
        } catch let error as HeistPlanRuntimeSafetyError {
            throw HeistSwiftFileCompilerError.runtimeSafetyFailed(error.description)
        } catch {
            throw HeistSwiftFileCompilerError.invalidCompilerOutput(String(describing: error))
        }
    }

    private func writeCompileDirectory(
        at tempURL: URL,
        source: URL,
        entry: HeistSwiftFileEntrySymbol,
        resolution: HeistSwiftFileEntryResolution
    ) throws -> URL {
        let sourcesURL = tempURL
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("PlanCompiler", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)

        let wrapper = """
        \(sourceLocationDirective(for: source))
        \(try String(contentsOf: source, encoding: .utf8))

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

enum HeistSwiftFileCompilerError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidEntry(String)
    case sourceFileNotFound(String)
    case packageRootNotFound
    case buildArtifactsNotFound(searched: [String], hint: String)
    case compileFailed(String, String)
    case executionFailed(String, String)
    case invalidCompilerOutput(String)
    case runtimeSafetyFailed(String)

    var description: String {
        switch self {
        case .invalidEntry(let entry):
            return "invalid Swift heist entry symbol: \(entry)"
        case .sourceFileNotFound(let path):
            return "Swift heist source file not found: \(path)"
        case .packageRootNotFound:
            return """
            could not locate built ThePlans artifacts or a local ButtonHeist package root containing Sources/ThePlans. \
            Install Button Heist with its heist-plan compiler artifacts, run the compiler from inside \
            a ButtonHeist checkout, or set HEIST_THEPLANS_BUILD_DIR to a directory holding built ThePlans artifacts \
            (Modules/ThePlans.swiftmodule or Modules/ThePlans.swiftinterface, plus ThePlans.build/*.swift.o).
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
        case .runtimeSafetyFailed(let diagnostics):
            return "compiled Swift heist failed runtime safety: \(diagnostics)"
        }
    }
}

private enum HeistSwiftFileEntryResolution: CaseIterable {
    case value
    case function

    func planExpression(for entry: HeistSwiftFileEntrySymbol) -> String {
        switch self {
        case .value:
            return entry.name
        case .function:
            return "try \(entry.name)()"
        }
    }
}

private struct HeistSwiftFileEntrySymbol {
    let name: String

    init(validating name: String) throws {
        let identifier = #"[A-Za-z_][A-Za-z0-9_]*"#
        let pattern = #"^\#(identifier)(\.\#(identifier))*$"#
        guard name.range(of: pattern, options: .regularExpression) != nil else {
            throw HeistSwiftFileCompilerError.invalidEntry(name)
        }
        self.name = name
    }
}

private enum LocalThePlansPackage {
    static func resolve() throws -> URL {
        guard let packageRoot = resolveCandidates().first else {
            throw HeistSwiftFileCompilerError.packageRootNotFound
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
/// it, installed artifacts next to the compiler and local package `.build`
/// directories are searched. Every route feeds the same compile path, and a miss
/// reports what was searched and how to fix it.
private struct ThePlansBuildArtifacts {
    static let environmentOverrideKey = HeistSwiftFileCompilerEnvironmentKey.thePlansBuildDirectory

    let buildDirectory: URL
    let swiftcArguments: [String]

    static func resolve(explicitPackageRoot: URL?) throws -> ThePlansBuildArtifacts {
        if let override = environmentOverridePath() {
            HeistSwiftFileCompilerTrace.write("resolving \(environmentOverrideKey) override at \(override)")
            let buildDirectory = URL(fileURLWithPath: override, isDirectory: true)
            if let artifacts = try resolveSwiftPMBuildDirectory(buildDirectory) {
                return artifacts
            }
            if let artifacts = resolveXcodeProductsDirectory(buildDirectory) {
                return artifacts
            }
            throw HeistSwiftFileCompilerError.buildArtifactsNotFound(
                searched: [buildDirectory.path],
                hint: """
                \(environmentOverrideKey)=\(override) does not contain built ThePlans artifacts \
                (expected Modules/ThePlans.swiftmodule or Modules/ThePlans.swiftinterface and ThePlans.build/*.swift.o, or \
                ThePlans.framework in an Xcode products directory). \
                Build them with `swift build --product heist-plan` \
                and point \(environmentOverrideKey) at .build/debug.
                """
            )
        }

        var searched: [String] = []
        let installedCandidates = candidateInstalledBuildDirectories()
        searched.append(contentsOf: installedCandidates.map(\.path))
        for buildDirectory in installedCandidates {
            HeistSwiftFileCompilerTrace.write("checking installed ThePlans artifacts: \(buildDirectory.path)")
            if let artifacts = try resolveSwiftPMBuildDirectory(buildDirectory) {
                return artifacts
            }
        }

        let packageRoots: [URL]
        if let explicitPackageRoot {
            packageRoots = [explicitPackageRoot.standardizedFileURL]
        } else {
            HeistSwiftFileCompilerTrace.write("resolving ButtonHeist package roots")
            packageRoots = LocalThePlansPackage.resolveCandidates()
        }
        guard !packageRoots.isEmpty || !installedCandidates.isEmpty else {
            throw HeistSwiftFileCompilerError.packageRootNotFound
        }

        for packageRoot in packageRoots {
            HeistSwiftFileCompilerTrace.write("checking ButtonHeist package root: \(packageRoot.path)")
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

        let localBuildSummary = packageRoots.isEmpty
            ? "local ButtonHeist package .build directories"
            : packageRoots.map { $0.appendingPathComponent(".build").path }.joined(separator: " or ")

        throw HeistSwiftFileCompilerError.buildArtifactsNotFound(
            searched: searched,
            hint: """
            No built ThePlans artifacts found in the installed lib/ThePlans directory or under \
            \(localBuildSummary). \
            Install Button Heist with heist-plan compiler artifacts, build them with \
            `swift build --product heist-plan`, or set \
            \(environmentOverrideKey) to a directory containing \
            Modules/ThePlans.swiftmodule or Modules/ThePlans.swiftinterface and ThePlans.build/*.swift.o. \
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

    private static func candidateInstalledBuildDirectories() -> [URL] {
        var candidates: [URL] = []
        for executable in executableCandidates() {
            let binDirectory = executable.deletingLastPathComponent()
            let prefix = binDirectory.deletingLastPathComponent()
            let artifactRoot = prefix
                .appendingPathComponent("lib", isDirectory: true)
                .appendingPathComponent("ThePlans", isDirectory: true)
            appendInstalledBuildDirectories(in: artifactRoot, to: &candidates)
        }
        return unique(candidates)
    }

    private static func appendInstalledBuildDirectories(in artifactRoot: URL, to candidates: inout [URL]) {
        let currentArch = currentArchitectureBuildDirectoryName()
        if let currentArch {
            candidates.append(artifactRoot.appendingPathComponent(currentArch, isDirectory: true)
                .appendingPathComponent("release", isDirectory: true))
            candidates.append(artifactRoot.appendingPathComponent(currentArch, isDirectory: true)
                .appendingPathComponent("debug", isDirectory: true))
        }
        candidates.append(artifactRoot.appendingPathComponent("release", isDirectory: true))
        candidates.append(artifactRoot.appendingPathComponent("debug", isDirectory: true))
        candidates.append(artifactRoot)
    }

    private static func executableCandidates() -> [URL] {
        var candidates: [URL] = []
        if let executableURL = Bundle.main.executableURL {
            candidates.append(executableURL.standardizedFileURL)
            candidates.append(executableURL.resolvingSymlinksInPath().standardizedFileURL)
        }

        if let rawExecutable = CommandLine.arguments.first, !rawExecutable.isEmpty {
            if rawExecutable.contains("/") {
                let executable = URL(fileURLWithPath: rawExecutable).standardizedFileURL
                candidates.append(executable)
                candidates.append(executable.resolvingSymlinksInPath().standardizedFileURL)
            } else {
                for directory in pathDirectories() {
                    let executable = directory.appendingPathComponent(rawExecutable)
                    candidates.append(executable.standardizedFileURL)
                    candidates.append(executable.resolvingSymlinksInPath().standardizedFileURL)
                }
            }
        }
        return unique(candidates)
    }

    private static func pathDirectories() -> [URL] {
        let path = ProcessInfo.processInfo.environment[.path] ?? ""
        return path
            .split(separator: ":", omittingEmptySubsequences: true)
            .map { URL(fileURLWithPath: String($0), isDirectory: true).standardizedFileURL }
    }

    private static func currentArchitectureBuildDirectoryName() -> String? {
        #if arch(arm64)
        return "arm64-apple-macosx"
        #elseif arch(x86_64)
        return "x86_64-apple-macosx"
        #else
        return nil
        #endif
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let standardized = url.standardizedFileURL
            guard seen.insert(standardized.path).inserted else { continue }
            result.append(standardized)
        }
        return result
    }

    private static func resolveSwiftPMBuildDirectory(_ buildDirectory: URL) throws -> ThePlansBuildArtifacts? {
        let modulesDirectory = buildDirectory.appendingPathComponent("Modules", isDirectory: true)
        let binaryModule = modulesDirectory.appendingPathComponent("ThePlans.swiftmodule")
        let textualModuleInterface = modulesDirectory.appendingPathComponent("ThePlans.swiftinterface")
        let objectsDirectory = buildDirectory.appendingPathComponent("ThePlans.build", isDirectory: true)
        guard FileManager.default.fileExists(atPath: binaryModule.path)
                || FileManager.default.fileExists(atPath: textualModuleInterface.path) else {
            return nil
        }
        let objectFiles = try SwiftPMBuildDescription.activeSwiftObjectFiles(
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
        let environmentDirectories = HeistSwiftFileCompilerEnvironmentKey.xcodeProductsDirectories.compactMap { key -> URL? in
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

}

struct SwiftPMBuildDescription: Decodable {
    let swiftCommands: [String: SwiftPMBuildCommand]

    private enum CodingKeys: String, CodingKey {
        case swiftCommands
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            swiftCommands = [:]
            return
        }
        swiftCommands = (try? container.decode([String: SwiftPMBuildCommand].self, forKey: .swiftCommands)) ?? [:]
    }

    static func activeSwiftObjectFiles(
        in buildDirectory: URL,
        moduleName: String
    ) throws -> [URL]? {
        let descriptionURL = buildDirectory.appendingPathComponent("description.json")
        guard let data = try? Data(contentsOf: descriptionURL) else {
            return nil
        }

        let description = try JSONDecoder().decode(SwiftPMBuildDescription.self, from: data)
        for command in description.swiftCommands.values {
            guard command.moduleName == moduleName,
                  let objectPaths = command.objects else {
                continue
            }

            let objectFiles = try objectPaths.compactMap { path -> URL? in
                let originalURL = URL(fileURLWithPath: path)
                guard originalURL.lastPathComponent.hasSuffix(".swift.o") else { return nil }
                let relocatedURL = buildDirectory
                    .appendingPathComponent("ThePlans.build", isDirectory: true)
                    .appendingPathComponent(originalURL.lastPathComponent)
                let url = FileManager.default.fileExists(atPath: originalURL.path)
                    ? originalURL
                    : relocatedURL
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { return nil }
                return url
            }
            return objectFiles.sorted { $0.path < $1.path }
        }

        return nil
    }
}

struct SwiftPMBuildCommand: Decodable {
    let moduleName: String?
    let objects: [String]?

    private enum CodingKeys: String, CodingKey {
        case moduleName
        case objects
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            moduleName = nil
            objects = nil
            return
        }
        moduleName = try? container.decode(String.self, forKey: .moduleName)
        objects = try? container.decode([String].self, forKey: .objects)
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

private enum HeistSwiftFileCompilerTrace {
    static func write(_ message: String) {
        guard ProcessInfo.processInfo.environment[.sourceCompilerTrace] == "1" else {
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
