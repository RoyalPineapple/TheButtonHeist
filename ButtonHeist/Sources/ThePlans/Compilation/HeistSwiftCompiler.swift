import Foundation

public enum Severity: String, Sendable, Equatable {
    case error
    case warning
}

public struct HeistBuildSourceLocation: Sendable, Equatable, CustomStringConvertible {
    public let url: URL
    public let line: Int?
    public let column: Int?

    public init(url: URL, line: Int? = nil, column: Int? = nil) {
        self.url = url
        self.line = line
        self.column = column
    }

    public var description: String {
        var result = url.path
        if let line {
            result += ":\(line)"
        }
        if let column {
            result += ":\(column)"
        }
        return result
    }
}

public actor HeistSwiftCompiler {
    public struct Configuration: Sendable, Equatable {
        public static let `default` = Configuration()

        public let packageRoot: URL?
        public let directoryEntry: HeistEntrySymbol
        let processLimits: HeistCompilerProcess.Limits
        let temporaryDirectory: URL

        public init(
            packageRoot: URL? = nil,
            directoryEntry: HeistEntrySymbol = "heist"
        ) {
            self.packageRoot = packageRoot
            self.directoryEntry = directoryEntry
            self.processLimits = .default
            self.temporaryDirectory = FileManager.default.temporaryDirectory
        }

        init(
            packageRoot: URL? = nil,
            directoryEntry: HeistEntrySymbol = "heist",
            processLimits: HeistCompilerProcess.Limits,
            temporaryDirectory: URL = FileManager.default.temporaryDirectory
        ) {
            self.packageRoot = packageRoot
            self.directoryEntry = directoryEntry
            self.processLimits = processLimits
            self.temporaryDirectory = temporaryDirectory
        }
    }

    private let configuration: Configuration

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    public func compileFile(
        _ url: URL,
        entry: HeistEntrySymbol = "heist"
    ) async -> ValidationResult<HeistPlan, HeistBuildDiagnostic> {
        let source = url.standardizedFileURL
        do {
            try Task.checkCancellation()
#if os(macOS) || os(Linux)
            let plan = try await HeistSwiftFileCompilation(
                packageRoot: configuration.packageRoot,
                processLimits: configuration.processLimits,
                temporaryDirectory: configuration.temporaryDirectory
            ).compile(source, entry: entry)
            try Task.checkCancellation()
            return .success(plan, diagnostics: [])
#else
            return .failure([
                Self.diagnostic(
                    code: .swiftCompilationUnsupportedPlatform,
                    "Swift heist source compilation is only supported on macOS and Linux.",
                    source: source
                ),
            ])
#endif
        } catch is CancellationError {
            return .failure([Self.diagnostic(
                code: .swiftCompilationCancelled,
                "Swift heist compilation was cancelled.",
                source: source
            )])
        } catch {
            return .failure(Self.diagnostics(for: error, source: source, entry: entry))
        }
    }

    public func compileDirectory(
        _ url: URL
    ) async -> ValidationResult<HeistCatalog, HeistBuildDiagnostic> {
        let directory = url.standardizedFileURL
        do {
            try Task.checkCancellation()
            let sources = try Self.sourceFiles(in: directory)
            guard !sources.isEmpty else {
                return .failure([
                    Self.diagnostic(
                        code: .directoryNoSources,
                        "Directory contains no Swift heist source files.",
                        phase: .planning,
                        source: directory
                    ),
                ])
            }

            var compileResults: [ValidationResult<HeistPlan, HeistBuildDiagnostic>] = []
            for source in sources {
                try Task.checkCancellation()
                compileResults.append(await compileFile(source, entry: configuration.directoryEntry))
            }

            let compiledPlans = compileResults.collectValidationResults()
            let compileDiagnostics = compiledPlans.diagnostics
            guard compileDiagnostics.allSatisfy({ $0.severity != .error }) else {
                return .failure(compileDiagnostics)
            }
            return compiledPlans.flatMap { plans in
                let catalogDiagnostics = Self.catalogDiagnostics(for: plans, sources: sources)
                guard catalogDiagnostics.allSatisfy({ $0.severity != .error }) else {
                    return .failure(catalogDiagnostics)
                }

                let catalog = HeistCatalog(
                    source: HeistCatalogSource(url: directory),
                    capabilities: plans
                )
                return .success(catalog, diagnostics: catalogDiagnostics)
            }
        } catch is CancellationError {
            return .failure([Self.diagnostic(
                code: .directoryCancelled,
                "Swift heist directory compilation was cancelled.",
                phase: .planning,
                source: directory
            )])
        } catch {
            return .failure(Self.diagnostics(for: error, source: directory, entry: configuration.directoryEntry))
        }
    }
}

private extension HeistSwiftCompiler {
    static func sourceFiles(in directory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw HeistDirectoryCompilationError.notDirectory(directory)
        }

        let entries = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var swiftSources: [URL] = []
        var unsupportedHeistSources: [URL] = []
        for entry in entries {
            let values = try entry.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            if entry.pathExtension.lowercased() == "swift" {
                swiftSources.append(entry.standardizedFileURL)
            } else if looksLikeHeistSource(entry) {
                unsupportedHeistSources.append(entry.standardizedFileURL)
            }
        }

        guard unsupportedHeistSources.isEmpty else {
            throw HeistDirectoryCompilationError.unsupportedHeistSourceFiles(unsupportedHeistSources)
        }
        return swiftSources.sorted { $0.path < $1.path }
    }

    static func looksLikeHeistSource(_ url: URL) -> Bool {
        let lowercasedName = url.lastPathComponent.lowercased()
        if lowercasedName == "readme" || lowercasedName.hasPrefix("readme.") {
            return false
        }
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let source = String(data: Data(data.prefix(64 * 1024)), encoding: .utf8) else {
            return false
        }
        return source.contains("import ThePlans")
            || source.contains("HeistPlan(")
            || source.contains("Warn(")
            || source.contains("Activate(")
    }

    static func catalogDiagnostics(
        for plans: [HeistPlan],
        sources: [URL]
    ) -> [HeistBuildDiagnostic] {
        var diagnostics: [HeistBuildDiagnostic] = []
        var seen: [HeistDefinitionPath: URL] = [:]

        for (index, plan) in plans.enumerated() {
            let source = sources[index]
            if plans.count > 1, plan.name == nil {
                diagnostics.append(diagnostic(
                    code: .catalogAnonymousCapability,
                    "Directory heist source compiled an anonymous capability. Name directory capabilities in the authored HeistPlan.",
                    phase: .planValidation,
                    source: source
                ))
            }

            do {
                let catalog = try plan.heistCatalog()
                for entry in catalog.heists {
                    guard let lookupPath = entry.identity.lookupPath else { continue }
                    if let previous = seen[lookupPath] {
                        diagnostics.append(diagnostic(
                            code: .catalogDuplicateCapability,
                            "Duplicate capability name \"\(entry.identity.displayName)\" also compiled from \(previous.lastPathComponent).",
                            phase: .planValidation,
                            source: source
                        ))
                    } else {
                        seen[lookupPath] = source
                    }
                }
            } catch let error as HeistCatalogError {
                diagnostics.append(diagnostic(
                    code: .catalogInvalidEntry,
                    error.description,
                    phase: .planValidation,
                    source: source
                ))
            } catch {
                diagnostics.append(diagnostic(
                    code: .catalogInvalidEntry,
                    "Invalid compiled catalog entry: \(bounded(errorDescription: error))",
                    phase: .planValidation,
                    source: source
                ))
            }
        }

        return diagnostics
    }

    static func diagnostics(
        for error: Error,
        source: URL?,
        entry: HeistEntrySymbol?
    ) -> [HeistBuildDiagnostic] {
#if os(macOS) || os(Linux)
        if let compilerError = error as? HeistSwiftFileCompilationError {
            return diagnostics(for: compilerError, source: source, entry: entry)
        }
#endif
        if let directoryError = error as? HeistDirectoryCompilationError {
            return diagnostics(for: directoryError)
        }
        return [diagnostic(bounded(errorDescription: error), source: source)]
    }

#if os(macOS) || os(Linux)
    static func diagnostics(
        for error: HeistSwiftFileCompilationError,
        source: URL?,
        entry: HeistEntrySymbol?
    ) -> [HeistBuildDiagnostic] {
        let entrySuffix = entry.map { " entry \"\($0)\"" } ?? ""
        switch error {
        case .sourceFileNotFound(let path):
            return [diagnostic(
                code: .swiftCompilationSourceNotFound,
                "Swift heist source file not found: \(path).",
                source: source
            )]
        case .packageRootNotFound:
            return [diagnostic(
                code: .swiftCompilationPackageRootNotFound,
                bounded(errorDescription: error),
                source: source
            )]
        case .buildArtifactsNotFound:
            return [diagnostic(
                code: .swiftCompilationBuildArtifactsNotFound,
                bounded(errorDescription: error),
                source: source
            )]
        case .compileFailed(_, let output):
            return [diagnostic(
                code: .swiftCompilationCompileFailed,
                "Failed to compile Swift heist source\(entrySuffix): \(bounded(output))",
                source: source
            )]
        case .executionFailed(_, let output):
            return [diagnostic(
                code: .swiftCompilationExecutionFailed,
                "Compiled Swift heist source\(entrySuffix) failed while evaluating the entry: \(bounded(output))",
                source: source
            )]
        case .compileTimedOut(_, let output):
            return [diagnostic(
                code: .swiftCompilationCompileTimedOut,
                "Swift heist source compilation\(entrySuffix) exceeded its deadline: \(bounded(output))",
                source: source
            )]
        case .executionTimedOut(_, let output):
            return [diagnostic(
                code: .swiftCompilationExecutionTimedOut,
                "Compiled Swift heist source\(entrySuffix) exceeded its evaluation deadline: \(bounded(output))",
                source: source
            )]
        case .compileOutputLimitExceeded(_, let stream, let output):
            return [diagnostic(
                code: .swiftCompilationCompileOutputLimitExceeded,
                "Swift compiler\(entrySuffix) exceeded its \(stream.rawValue) output limit: \(bounded(output))",
                source: source
            )]
        case .executionOutputLimitExceeded(_, let stream, let output):
            return [diagnostic(
                code: .swiftCompilationExecutionOutputLimitExceeded,
                """
                Compiled Swift heist source\(entrySuffix) exceeded its \(stream.rawValue) output limit: \
                \(bounded(output))
                """,
                source: source
            )]
        case .compilerTerminated(_, let signal, let output):
            return [diagnostic(
                code: .swiftCompilationCompilerTerminated,
                "Swift compiler\(entrySuffix) terminated by signal \(signal): \(bounded(output))",
                source: source
            )]
        case .executionTerminated(_, let signal, let output):
            return [diagnostic(
                code: .swiftCompilationExecutionTerminated,
                "Compiled Swift heist source\(entrySuffix) terminated by signal \(signal): \(bounded(output))",
                source: source
            )]
        case .invalidCompilerOutput(let output):
            return [diagnostic(
                code: .swiftCompilationInvalidOutput,
                "Compiled Swift heist source\(entrySuffix) did not emit valid HeistPlan JSON: \(bounded(output))",
                source: source
            )]
        case .runtimeSafetyFailed(let output):
            return [diagnostic(
                code: .planRuntimeSafety,
                "Compiled Swift heist source\(entrySuffix) failed runtime safety: \(bounded(output))",
                phase: .planValidation,
                source: source
            )]
        }
    }
#endif

    static func diagnostics(for error: HeistDirectoryCompilationError) -> [HeistBuildDiagnostic] {
        switch error {
        case .notDirectory(let url):
            return [diagnostic(
                code: .directoryNotDirectory,
                "Heist catalog source is not a directory.",
                phase: .planning,
                source: url
            )]
        case .unsupportedHeistSourceFiles(let urls):
            return urls.map {
                diagnostic(
                    code: .directoryUnsupportedSourceFile,
                    "Unsupported heist source file. Directory compilation only accepts .swift files.",
                    phase: .planning,
                    source: $0
                )
            }
        }
    }

    static func diagnostic(
        code: HeistKnownBuildDiagnosticCode = .swiftCompilationFailed,
        _ message: String,
        severity: Severity = .error,
        phase: HeistBuildPhase = .swiftCompilation,
        source: URL?
    ) -> HeistBuildDiagnostic {
        HeistBuildDiagnostic(
            code: code,
            kind: severity.diagnosticKind,
            phase: phase,
            sourceSpan: source.map {
                HeistBuildSourceSpan(
                    sourceName: $0.path,
                    offset: 0,
                    line: 1,
                    column: 1
                )
            },
            message: message,
            hint: nil
        )
    }

    static func bounded(errorDescription error: Error) -> String {
        bounded(String(describing: error))
    }

    static func bounded(_ message: String, maxLines: Int = 12, maxCharacters: Int = 2_000) -> String {
        var lines = message
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if lines.count > maxLines {
            lines = Array(lines.prefix(maxLines)) + ["..."]
        }
        var compact = lines.joined(separator: "\n")
        if compact.count > maxCharacters {
            compact = String(compact.prefix(maxCharacters)) + "..."
        }
        return compact.isEmpty ? "no compiler diagnostics" : compact
    }
}

private enum HeistDirectoryCompilationError: Error, Sendable, Equatable {
    case notDirectory(URL)
    case unsupportedHeistSourceFiles([URL])
}

private extension Severity {
    var diagnosticKind: HeistBuildDiagnosticKind {
        switch self {
        case .error:
            return .error
        case .warning:
            return .warning
        }
    }
}
