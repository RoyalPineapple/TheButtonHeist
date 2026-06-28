import Foundation

public enum Severity: String, Sendable, Equatable {
    case error
    case warning
}

public struct HeistCompilationSourceLocation: Sendable, Equatable, CustomStringConvertible {
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

public typealias HeistCompilationDiagnostic = HeistBuildDiagnostic
public typealias HeistCompilationResult<Value: Sendable> = ValidationResult<Value, HeistBuildDiagnostic>

public actor HeistCompiler {
    public struct Configuration: Sendable, Equatable {
        public static let `default` = Configuration()

        public let packageRoot: URL?
        public let directoryEntry: String

        public init(
            packageRoot: URL? = nil,
            directoryEntry: String = "heist"
        ) {
            self.packageRoot = packageRoot
            self.directoryEntry = directoryEntry
        }
    }

    private let configuration: Configuration

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    public func compileFile(
        _ url: URL,
        entry: String = "heist"
    ) async -> HeistCompilationResult<HeistPlan> {
        let source = url.standardizedFileURL
        do {
            try Task.checkCancellation()
#if os(macOS) || os(Linux)
            let plan = try HeistSwiftFileCompiler(packageRoot: configuration.packageRoot)
                .compileSwiftFile(source, entry: entry)
            try Task.checkCancellation()
            return .success(plan, diagnostics: [])
#else
            return .failure([
                Self.diagnostic(
                    code: "heist.swift_compilation.unsupported_platform",
                    "Swift heist source compilation is only supported on macOS and Linux.",
                    source: source
                ),
            ])
#endif
        } catch is CancellationError {
            return .failure([Self.diagnostic(
                code: "heist.swift_compilation.cancelled",
                "Swift heist compilation was cancelled.",
                source: source
            )])
        } catch {
            return .failure(Self.diagnostics(for: error, source: source, entry: entry))
        }
    }

    public func compileDirectory(
        _ url: URL
    ) async -> HeistCompilationResult<HeistCatalog> {
        let directory = url.standardizedFileURL
        do {
            try Task.checkCancellation()
            let sources = try Self.sourceFiles(in: directory)
            guard !sources.isEmpty else {
                return .failure([
                    Self.diagnostic(
                        code: "heist.directory.no_sources",
                        "Directory contains no Swift heist source files.",
                        phase: .planning,
                        source: directory
                    ),
                ])
            }

            var plans: [HeistPlan] = []
            var diagnostics: [HeistCompilationDiagnostic] = []
            for source in sources {
                try Task.checkCancellation()
                switch await compileFile(source, entry: configuration.directoryEntry) {
                case .success(let plan, let compileDiagnostics):
                    plans.append(plan)
                    diagnostics.append(contentsOf: compileDiagnostics)
                case .failure(let compileDiagnostics):
                    diagnostics.append(contentsOf: compileDiagnostics)
                }
            }

            guard diagnostics.allSatisfy({ $0.severity != .error }) else {
                return .failure(diagnostics)
            }
            let catalogDiagnostics = Self.catalogDiagnostics(for: plans, sources: sources)
            diagnostics.append(contentsOf: catalogDiagnostics)
            guard diagnostics.allSatisfy({ $0.severity != .error }) else {
                return .failure(diagnostics)
            }

            let catalog = HeistCatalog(
                source: HeistCatalogSource(url: directory),
                capabilities: plans
            )
            return .success(catalog, diagnostics: diagnostics)
        } catch is CancellationError {
            return .failure([Self.diagnostic(
                code: "heist.directory.cancelled",
                "Swift heist directory compilation was cancelled.",
                phase: .planning,
                source: directory
            )])
        } catch {
            return .failure(Self.diagnostics(for: error, source: directory, entry: configuration.directoryEntry))
        }
    }
}

private extension HeistCompiler {
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
    ) -> [HeistCompilationDiagnostic] {
        var diagnostics: [HeistCompilationDiagnostic] = []
        var seen: [String: URL] = [:]

        for (index, plan) in plans.enumerated() {
            let source = sources[index]
            if plans.count > 1, plan.name?.isEmpty != false {
                diagnostics.append(diagnostic(
                    code: "heist.catalog.anonymous_capability",
                    "Directory heist source compiled an anonymous capability. Name directory capabilities in the authored HeistPlan.",
                    phase: .planValidation,
                    source: source
                ))
            }

            do {
                let catalog = try plan.heistCatalog()
                for entry in catalog.heists {
                    if let previous = seen[entry.name] {
                        diagnostics.append(diagnostic(
                            code: "heist.catalog.duplicate_capability",
                            "Duplicate capability name \"\(entry.name)\" also compiled from \(previous.lastPathComponent).",
                            phase: .planValidation,
                            source: source
                        ))
                    } else {
                        seen[entry.name] = source
                    }
                }
            } catch let error as HeistCatalogError {
                diagnostics.append(diagnostic(
                    code: "heist.catalog.invalid_entry",
                    error.description,
                    phase: .planValidation,
                    source: source
                ))
            } catch {
                diagnostics.append(diagnostic(
                    code: "heist.catalog.invalid_entry",
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
        entry: String?
    ) -> [HeistCompilationDiagnostic] {
#if os(macOS) || os(Linux)
        if let compilerError = error as? HeistSwiftFileCompilerError {
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
        for error: HeistSwiftFileCompilerError,
        source: URL?,
        entry: String?
    ) -> [HeistCompilationDiagnostic] {
        let entrySuffix = entry.map { " entry \"\($0)\"" } ?? ""
        switch error {
        case .invalidEntry(let invalidEntry):
            return [diagnostic(
                code: "heist.swift_compilation.invalid_entry",
                "Invalid Swift heist entry symbol \"\(invalidEntry)\".",
                source: source
            )]
        case .sourceFileNotFound(let path):
            return [diagnostic(
                code: "heist.swift_compilation.source_not_found",
                "Swift heist source file not found: \(path).",
                source: source
            )]
        case .packageRootNotFound:
            return [diagnostic(
                code: "heist.swift_compilation.package_root_not_found",
                bounded(errorDescription: error),
                source: source
            )]
        case .buildArtifactsNotFound:
            return [diagnostic(
                code: "heist.swift_compilation.build_artifacts_not_found",
                bounded(errorDescription: error),
                source: source
            )]
        case .compileFailed(_, let output):
            return [diagnostic(
                code: "heist.swift_compilation.compile_failed",
                "Failed to compile Swift heist source\(entrySuffix): \(bounded(output))",
                source: source
            )]
        case .executionFailed(_, let output):
            return [diagnostic(
                code: "heist.swift_compilation.execution_failed",
                "Compiled Swift heist source\(entrySuffix) failed while evaluating the entry: \(bounded(output))",
                source: source
            )]
        case .invalidCompilerOutput(let output):
            return [diagnostic(
                code: "heist.swift_compilation.invalid_output",
                "Compiled Swift heist source\(entrySuffix) did not emit valid HeistPlan JSON: \(bounded(output))",
                source: source
            )]
        case .runtimeSafetyFailed(let output):
            return [diagnostic(
                code: "heist.plan.runtime_safety",
                "Compiled Swift heist source\(entrySuffix) failed runtime safety: \(bounded(output))",
                phase: .planValidation,
                source: source
            )]
        }
    }
#endif

    static func diagnostics(for error: HeistDirectoryCompilationError) -> [HeistCompilationDiagnostic] {
        switch error {
        case .notDirectory(let url):
            return [diagnostic(
                code: "heist.directory.not_directory",
                "Heist catalog source is not a directory.",
                phase: .planning,
                source: url
            )]
        case .unsupportedHeistSourceFiles(let urls):
            return urls.map {
                diagnostic(
                    code: "heist.directory.unsupported_source_file",
                    "Unsupported heist source file. Directory compilation only accepts .swift files.",
                    phase: .planning,
                    source: $0
                )
            }
        }
    }

    static func diagnostic(
        code: String = "heist.swift_compilation.failed",
        _ message: String,
        severity: Severity = .error,
        phase: HeistBuildPhase = .swiftCompilation,
        source: URL?
    ) -> HeistCompilationDiagnostic {
        HeistCompilationDiagnostic(
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
