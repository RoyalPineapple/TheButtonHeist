import ArgumentParser
import ButtonHeist
import Foundation
import ThePlans
import TheScore

struct RunHeistCommand: AsyncParsableCommand, CLICommandContract {
    typealias SwiftHeistCompiler = @Sendable (_ source: URL, _ entry: String) async -> HeistCompilationResult<HeistPlan>

    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Execute a Button Heist plan from a .heist package artifact or Swift DSL source",
        discussion: """
            Forwards a .heist package artifact `--path` to the fence, which reads
            the package into a HeistPlan and runs it. Swift DSL source is compiled
            locally to a .heist before sending. Inline `--plan` accepts canonical
            ButtonHeist DSL source, not raw JSON IR.

            Examples:
              buttonheist run_heist --path Flow.heist
              buttonheist run_heist --path Search.heist --argument '{"type":"string","value":"milk"}'
              buttonheist run_heist --path Flow.swift --entry makeHeist
              buttonheist run_heist --path Flow.heist --junit report.xml
              buttonheist run_heist --plan 'HeistPlan("smoke") { Warn("Check") }'
            """
    )

    @Option(name: .long, help: "Path to a .heist package artifact or Swift DSL source file.")
    var path: String?

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .long, help: "Inline canonical ButtonHeist DSL source.")
    var plan: String?

    @Option(name: .long, help: "Root heist argument as canonical HeistArgument JSON object.")
    var argument: String?

    @Option(name: .long, help: "Zero-argument Swift entry symbol returning HeistPlan.")
    var entry: String?

    @Option(name: .long, help: "Write a JUnit XML report to this path.")
    var junit: String?

    @ButtonHeistActor
    mutating func run() async throws {
        // Swift DSL source is compiled to a temporary .heist package up front,
        // so every run dispatches a .heist the fence reads — the plan is never
        // re-encoded through a lossy parameter round-trip.
        let prepared = try await Self.prepareInput(path: path, entry: entry)
        defer { prepared.cleanup() }

        let request = try Self.planArguments(
            inline: plan,
            path: prepared.path,
            entry: prepared.entry,
            argument: argument
        )

        guard let junitPath = junit else {
            try await CLIRunner.run(
                connection: connection,
                format: output.format,
                command: Self.fenceCommand,
                arguments: Self.fenceArguments(request),
                statusMessage: "Running heist..."
            )
            return
        }

        let (fence, response) = try await CLIRunner.execute(
            connection: connection,
            command: Self.fenceCommand,
            arguments: Self.fenceArguments(request)
        )
        defer { fence.stop() }

        if case .heistExecution(_, let result, _) = response {
            let name = prepared.path
                .map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "heist"
            let report = fence.junitReport(
                for: result,
                heistName: name,
                totalTimeSeconds: Double(result.durationMs) / 1000
            )
            try report.junitXML().write(to: URL(fileURLWithPath: junitPath), atomically: true, encoding: .utf8)
            logStatus("JUnit report written to \(junitPath)")
        } else {
            logStatus("Warning: --junit requested but run_heist did not produce a report")
        }

        CLIRunner.outputResponse(response, format: output.format ?? .auto)
        if response.isFailure {
            throw ExitCode.failure
        }
    }

    struct PreparedInput {
        let path: String?
        let entry: String?
        let cleanup: () -> Void
    }

    /// Resolve the `--path` input before request construction.
    ///
    /// `.swift` DSL source is compiled (it needs the toolchain) and written to a
    /// temporary `.heist` package, so what reaches the fence is always a `.heist`
    /// artifact read through the canonical codec — never a `HeistPlan` re-encoded
    /// through a lossy parameter round-trip. The caller must invoke `cleanup`
    /// once the run completes.
    static func prepareInput(
        path: String?,
        entry: String?,
        compileSwiftFile: SwiftHeistCompiler = { source, entry in
            await HeistCompiler().compileFile(source, entry: entry)
        }
    ) async throws -> PreparedInput {
        guard let path, path.lowercased().hasSuffix(".swift") else {
            return PreparedInput(path: path, entry: entry, cleanup: {})
        }
        guard let entry, !entry.isEmpty else {
            throw ValidationError("--entry is required for Swift source input")
        }

        let source = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let name = source.deletingPathExtension().lastPathComponent
        let plan: HeistPlan
        switch await compileSwiftFile(source, entry) {
        case .success(let compiledPlan, _):
            plan = compiledPlan
        case .failure(let diagnostics):
            throw ValidationError("failed to compile Swift heist source: \(formatCompilationDiagnostics(diagnostics))")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-heist-\(UUID().uuidString)", isDirectory: true)
        let artifact = directory.appendingPathComponent("\(name).heist")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Write the plan exactly as compiled. The artifact file name carries the
        // run name for reporting; it must not be stamped into the plan's `name`,
        // which is a Swift-identifier-constrained semantic field and would fail
        // runtime safety checks for a non-identifier file name.
        try HeistArtifactCodec.writePlan(plan, to: artifact)
        return PreparedInput(path: artifact.path, entry: nil, cleanup: {
            try? FileManager.default.removeItem(at: directory)
        })
    }

    static func planArguments(inline: String?) throws -> CLIRequestParameters {
        try planArguments(inline: inline, path: nil, entry: nil)
    }

    /// Build the run_heist request parameters.
    ///
    /// A `.heist` package artifact path is forwarded to the fence as a `path`
    /// parameter; the fence asks ThePlans to read the package into a `HeistPlan`
    /// directly. Inline `--plan` is ButtonHeist DSL source. `.swift` source is
    /// resolved to a `.heist` by `prepareInput` before reaching this point.
    static func planArguments(
        inline: String?,
        path: String?,
        entry: String?,
        argument: String? = nil,
        commandName: String = Self.cliCommandName
    ) throws -> CLIRequestParameters {
        let suppliedSources = [inline != nil, path != nil].filter { $0 }.count
        guard suppliedSources == 1 else {
            if suppliedSources == 0 {
                throw ValidationError("Must supply --path or --plan")
            }
            throw ValidationError("--path and --plan are mutually exclusive")
        }

        if let path {
            guard entry == nil else {
                throw ValidationError("--entry is only valid with Swift source input")
            }
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard url.pathExtension.lowercased() == "heist" else {
                throw ValidationError(
                    "Unsupported \(commandName) --path \(path). Use a .heist package artifact or .swift source " +
                    "(raw .json plan IR is internal to the .heist package, not a run input)."
                )
            }
            // Forward the artifact path; the fence reads the package into a HeistPlan.
            var request: CLIRequestParameters = [.path: .string(path)]
            if let argument {
                request.set(.argument, try parseRootArgument(argument))
            }
            return request
        }

        if entry != nil {
            throw ValidationError("--entry is only valid with Swift source input")
        }

        guard let inline else {
            throw ValidationError("Must supply --path or --plan")
        }
        guard !inline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError("--plan must be ButtonHeist DSL source")
        }
        var request: CLIRequestParameters = [.plan: .string(inline)]
        if let argument {
            request.set(.argument, try parseRootArgument(argument))
        }
        return request
    }

    private static func parseRootArgument(_ rawValue: String) throws -> HeistValue {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationError("--argument must be a JSON object")
        }
        let value: HeistValue
        do {
            value = try JSONDecoder().decode(HeistValue.self, from: Data(trimmed.utf8))
        } catch {
            throw ValidationError("--argument must be valid JSON: \(error)")
        }
        guard case .object = value else {
            throw ValidationError("--argument must be a JSON object")
        }
        return value
    }
}

private func formatCompilationDiagnostics(_ diagnostics: [HeistCompilationDiagnostic]) -> String {
    diagnostics.map(\.description).joined(separator: "\n")
}
