import Foundation

#if os(macOS) || os(Linux)
private enum HeistSwiftFileCompilationEnvironmentKey: String, Sendable, CustomStringConvertible {
    case thePlansBuildDirectory = "HEIST_THEPLANS_BUILD_DIR"
    case path = "PATH"
    case builtProductsDirectory = "BUILT_PRODUCTS_DIR"
    case targetBuildDirectory = "TARGET_BUILD_DIR"
    case configurationBuildDirectory = "CONFIGURATION_BUILD_DIR"
    case sourceCompilerTrace = "HEIST_SOURCE_COMPILER_TRACE"

    var description: String { rawValue }

    static let xcodeProductsDirectories: [HeistSwiftFileCompilationEnvironmentKey] = [
        .builtProductsDirectory,
        .targetBuildDirectory,
        .configurationBuildDirectory,
    ]
}

private extension Dictionary where Key == String, Value == String {
    subscript(_ key: HeistSwiftFileCompilationEnvironmentKey) -> String? {
        self[key.rawValue]
    }
}

struct HeistSwiftFileCompilation: Sendable {
    let packageRoot: URL?
    let processLimits: HeistCompilerProcess.Limits
    let temporaryDirectory: URL

    init(
        packageRoot: URL? = nil,
        processLimits: HeistCompilerProcess.Limits = .default,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.packageRoot = packageRoot
        self.processLimits = processLimits
        self.temporaryDirectory = temporaryDirectory
    }

    /// Persistent, shared swiftc module cache for plan compilation. Reused
    /// across compiles so the Foundation/ThePlans module interfaces are built
    /// once per toolchain rather than on every plan.
    static let sharedModuleCacheDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("buttonheist-heist-plan-module-cache", isDirectory: true)

    func compile(
        _ source: URL,
        entry: HeistEntrySymbol
    ) async throws -> HeistPlan {
        try Task.checkCancellation()
        let source = source.standardizedFileURL
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw HeistSwiftFileCompilationError.sourceFileNotFound(source.path)
        }
        HeistSwiftFileCompilationTrace.write("preparing Swift heist compile")
        let thePlansSwiftcArguments = try Self.resolveThePlansSwiftcArguments(explicitPackageRoot: packageRoot)

        let tempURL = temporaryDirectory
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

        let compileDirectory = try writeCompileDirectory(
            at: tempURL,
            source: source,
            entry: entry
        )

        return try await compile(
            source: source,
            compileDirectory: compileDirectory,
            buildDirectory: buildDirectory,
            moduleCache: moduleCache,
            thePlansSwiftcArguments: thePlansSwiftcArguments
        )
    }

    private func compile(
        source: URL,
        compileDirectory: URL,
        buildDirectory: URL,
        moduleCache: URL,
        thePlansSwiftcArguments: [String]
    ) async throws -> HeistPlan {
        let executableURL = buildDirectory.appendingPathComponent("plan-compiler")
        HeistSwiftFileCompilationTrace.write("compiling Swift heist wrapper against built ThePlans artifacts")
        let compilerResult = try await HeistCompilerProcess.Runner.shared.execute(
            Self.planCompilerCommand(
                compileDirectory: compileDirectory,
                moduleCache: moduleCache,
                executableURL: executableURL,
                thePlansSwiftcArguments: thePlansSwiftcArguments
            ),
            purpose: .compilation,
            limits: processLimits
        )
        _ = try successfulOutput(
            from: compilerResult,
            phase: .compilation(source.path)
        )

        HeistSwiftFileCompilationTrace.write("running Swift heist wrapper")
        let executionResult = try await HeistCompilerProcess.Runner.shared.execute(
            HeistCompilerProcess.Command(executable: executableURL, arguments: []),
            purpose: .execution,
            limits: processLimits
        )
        let output = try successfulOutput(
            from: executionResult,
            phase: .execution(source.path)
        )

        do {
            return try HeistPlanJSONCodec.decodeValidatedPlan(output.stdout, sourceURL: source)
        } catch let error as HeistPlanJSONCodecError {
            throw HeistSwiftFileCompilationError.invalidCompilerOutput(error.description)
        } catch let error as HeistPlanRuntimeSafetyError {
            throw HeistSwiftFileCompilationError.runtimeSafetyFailed(error.description)
        } catch {
            throw HeistSwiftFileCompilationError.invalidCompilerOutput(String(describing: error))
        }
    }

    private func successfulOutput(
        from outcome: HeistCompilerProcess.Outcome,
        phase: HeistSwiftFileCompilationProcessPhase
    ) throws -> HeistCompilerProcess.Output {
        switch outcome {
        case .succeeded(let output):
            return output
        case .nonzeroExit(let code, let output):
            throw phase.nonzeroExit(code: code, diagnostics: output.diagnostics)
        case .signaled(let signal, let output):
            throw phase.signaled(signal: signal, diagnostics: output.diagnostics)
        case .timedOut(let output):
            throw phase.timedOut(diagnostics: output.diagnostics)
        case .cancelled:
            throw CancellationError()
        case .outputLimitExceeded(let stream, let output):
            throw phase.outputLimitExceeded(stream: stream, diagnostics: output.diagnostics)
        }
    }

    private func writeCompileDirectory(
        at tempURL: URL,
        source: URL,
        entry: HeistEntrySymbol
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

        let plan: HeistPlan = try \(entry)()
        FileHandle.standardOutput.write(try plan.canonicalHeistJSONData())
        """
        try wrapper.write(
            to: sourcesURL.appendingPathComponent("main.swift"),
            atomically: true,
            encoding: .utf8
        )
        return sourcesURL
    }

    package static func planCompilerCommand(
        compileDirectory: URL,
        moduleCache: URL,
        executableURL: URL,
        thePlansSwiftcArguments: [String]
    ) -> HeistCompilerProcess.Command {
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
        arguments.append(contentsOf: thePlansSwiftcArguments)
        return HeistCompilerProcess.Command(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: arguments
        )
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

private enum LocalThePlansPackage {
    static func resolve() throws -> URL {
        guard let packageRoot = resolveCandidates().first else {
            throw HeistSwiftFileCompilationError.packageRootNotFound
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

private extension HeistSwiftFileCompilation {
    static let environmentOverrideKey = HeistSwiftFileCompilationEnvironmentKey.thePlansBuildDirectory

    static func resolveThePlansSwiftcArguments(explicitPackageRoot: URL?) throws -> [String] {
        if let override = environmentOverridePath() {
            HeistSwiftFileCompilationTrace.write("resolving \(environmentOverrideKey) override at \(override)")
            let buildDirectory = URL(fileURLWithPath: override, isDirectory: true)
            if let arguments = try resolveSwiftPMBuildDirectory(buildDirectory) {
                HeistSwiftFileCompilationTrace.write("using built ThePlans artifacts at \(buildDirectory.path)")
                return arguments
            }
            if let arguments = resolveXcodeProductsDirectory(buildDirectory) {
                HeistSwiftFileCompilationTrace.write("using built ThePlans artifacts at \(buildDirectory.path)")
                return arguments
            }
            throw HeistSwiftFileCompilationError.buildArtifactsNotFound(
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
            HeistSwiftFileCompilationTrace.write("checking installed ThePlans artifacts: \(buildDirectory.path)")
            if let arguments = try resolveSwiftPMBuildDirectory(buildDirectory) {
                HeistSwiftFileCompilationTrace.write("using built ThePlans artifacts at \(buildDirectory.path)")
                return arguments
            }
        }

        let packageRoots: [URL]
        if let explicitPackageRoot {
            packageRoots = [explicitPackageRoot.standardizedFileURL]
        } else {
            HeistSwiftFileCompilationTrace.write("resolving ButtonHeist package roots")
            packageRoots = LocalThePlansPackage.resolveCandidates()
        }
        guard !packageRoots.isEmpty || !installedCandidates.isEmpty else {
            throw HeistSwiftFileCompilationError.packageRootNotFound
        }

        for packageRoot in packageRoots {
            HeistSwiftFileCompilationTrace.write("checking ButtonHeist package root: \(packageRoot.path)")
            let swiftPMCandidates = try candidateBuildDirectories(in: packageRoot)
            searched.append(contentsOf: swiftPMCandidates.map(\.path))
            for buildDirectory in swiftPMCandidates {
                if let arguments = try resolveSwiftPMBuildDirectory(buildDirectory) {
                    HeistSwiftFileCompilationTrace.write("using built ThePlans artifacts at \(buildDirectory.path)")
                    return arguments
                }
            }

            let xcodeCandidates = candidateXcodeProductsDirectories(packageRoot: packageRoot)
            searched.append(contentsOf: xcodeCandidates.map(\.path))
            for productsDirectory in xcodeCandidates {
                if let arguments = resolveXcodeProductsDirectory(productsDirectory) {
                    HeistSwiftFileCompilationTrace.write(
                        "using built ThePlans artifacts at \(productsDirectory.path)"
                    )
                    return arguments
                }
            }
        }

        let localBuildSummary = packageRoots.isEmpty
            ? "local ButtonHeist package .build directories"
            : packageRoots.map { $0.appendingPathComponent(".build").path }.joined(separator: " or ")

        throw HeistSwiftFileCompilationError.buildArtifactsNotFound(
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

    private static func resolveSwiftPMBuildDirectory(_ buildDirectory: URL) throws -> [String]? {
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
        return [
            "-I",
            modulesDirectory.path,
        ] + objectFiles.map(\.path)
    }

    private static func resolveXcodeProductsDirectory(_ productsDirectory: URL) -> [String]? {
        let frameworkDirectory = productsDirectory.appendingPathComponent("ThePlans.framework", isDirectory: true)
        let binary = frameworkDirectory.appendingPathComponent("ThePlans")
        let swiftModuleDirectory = frameworkDirectory
            .appendingPathComponent("Modules", isDirectory: true)
            .appendingPathComponent("ThePlans.swiftmodule", isDirectory: true)
        guard FileManager.default.fileExists(atPath: binary.path),
              FileManager.default.fileExists(atPath: swiftModuleDirectory.path) else {
            return nil
        }
        return [
            "-F",
            productsDirectory.path,
            "-Xlinker",
            "-rpath",
            "-Xlinker",
            productsDirectory.path,
            "-framework",
            "ThePlans",
        ]
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
        let environmentDirectories = HeistSwiftFileCompilationEnvironmentKey.xcodeProductsDirectories.compactMap { key -> URL? in
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

private enum HeistSwiftFileCompilationTrace {
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

#endif
