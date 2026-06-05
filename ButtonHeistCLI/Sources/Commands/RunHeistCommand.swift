import ArgumentParser
import ButtonHeist
import Foundation
import ThePlans
import TheScore

struct RunHeistCommand: AsyncParsableCommand, CLICommandContract {
    typealias SwiftHeistCompiler = (_ source: URL, _ entry: String) throws -> HeistPlan

    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Execute a Button Heist plan from a .heist package artifact or Swift DSL source",
        discussion: """
            Forwards a generated .heist package artifact to the fence, which
            reads the package into a HeistPlan and runs it. Swift DSL source is
            compiled locally before sending. The raw plan.json inside a .heist
            package is internal to the artifact, not a run input. Existing
            --plan and --plan-from-file inline JSON inputs remain available.

            Examples:
              buttonheist run_heist Flow.heist
              buttonheist run_heist Flow.swift --entry makeHeist
              buttonheist run_heist --plan '{"version":1,"body":[{"type":"warn","warn":{"message":"Check login state"}}]}'
            """
    )

    @Argument(help: "Path to a .heist package artifact or Swift DSL source file.")
    var input: String?

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .long, help: "Inline canonical heist plan JSON object")
    var plan: String?

    @Option(name: .long, help: "Path to a JSON file containing a canonical heist plan object")
    var planFromFile: String?

    @Option(name: .long, help: "Zero-argument Swift entry symbol returning HeistPlan.")
    var entry: String?

    @ButtonHeistActor
    mutating func run() async throws {
        // Swift DSL source is compiled to a temporary .heist package up front,
        // so every run dispatches a .heist the fence reads — the plan is never
        // re-encoded through a lossy parameter round-trip.
        let prepared = try Self.prepareInput(input: input, entry: entry)
        defer { prepared.cleanup() }

        let request = try Self.planArguments(
            inline: plan,
            fromFile: planFromFile,
            input: prepared.input,
            entry: prepared.entry
        )

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            command: Self.fenceCommand,
            arguments: Self.fenceArguments(request),
            statusMessage: "Running heist..."
        )
    }

    struct PreparedInput {
        let input: String?
        let entry: String?
        let cleanup: () -> Void
    }

    /// Resolve the input before request construction.
    ///
    /// `.swift` DSL source is compiled (it needs the toolchain) and written to a
    /// temporary `.heist` package, so what reaches the fence is always a `.heist`
    /// artifact read through the canonical codec — never a `HeistPlan` re-encoded
    /// through a lossy parameter round-trip. The caller must invoke `cleanup`
    /// once the run completes.
    static func prepareInput(
        input: String?,
        entry: String?,
        compileSwiftFile: SwiftHeistCompiler = { source, entry in
            try HeistSourceCompiler().compileSwiftFile(source, entry: entry)
        }
    ) throws -> PreparedInput {
        guard let input, input.lowercased().hasSuffix(".swift") else {
            return PreparedInput(input: input, entry: entry, cleanup: {})
        }
        guard let entry, !entry.isEmpty else {
            throw ValidationError("--entry is required for Swift source input")
        }

        let source = URL(fileURLWithPath: (input as NSString).expandingTildeInPath)
        let name = source.deletingPathExtension().lastPathComponent
        let plan: HeistPlan
        do {
            plan = try compileSwiftFile(source, entry)
        } catch {
            throw ValidationError("failed to compile Swift heist source: \(error)")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-heist-\(UUID().uuidString)", isDirectory: true)
        let artifact = directory.appendingPathComponent("\(name).heist")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try HeistArtifactCodec.writePlan(plan.named(name), to: artifact)
        return PreparedInput(input: artifact.path, entry: nil, cleanup: {
            try? FileManager.default.removeItem(at: directory)
        })
    }

    static func planArguments(inline: String?, fromFile path: String?) throws -> CLIRequestParameters {
        try planArguments(inline: inline, fromFile: path, input: nil, entry: nil)
    }

    /// Build the run_heist request parameters.
    ///
    /// A `.heist` package artifact path is forwarded to the fence as an `input`
    /// path; the fence reads the package into a `HeistPlan` directly. Inline
    /// `--plan` / `--plan-from-file` JSON is the only path expanded into plan
    /// fields here. `.swift` source is resolved to a `.heist` by `prepareInput`
    /// before reaching this point.
    static func planArguments(
        inline: String?,
        fromFile path: String?,
        input: String?,
        entry: String?
    ) throws -> CLIRequestParameters {
        let suppliedSources = [inline != nil, path != nil, input != nil].filter { $0 }.count
        guard suppliedSources == 1 else {
            if suppliedSources == 0 {
                throw ValidationError("Must supply a plan path, --plan, or --plan-from-file")
            }
            throw ValidationError("plan path, --plan, and --plan-from-file are mutually exclusive")
        }

        if let input {
            guard entry == nil else {
                throw ValidationError("--entry is only valid with Swift source input")
            }
            let url = URL(fileURLWithPath: (input as NSString).expandingTildeInPath)
            guard url.pathExtension.lowercased() == "heist" else {
                throw ValidationError(
                    "Unsupported run_heist input for \(input). Use a .heist package artifact or .swift source " +
                    "(raw .json plan IR is internal to the .heist package, not a run input)."
                )
            }
            // Forward the artifact path; the fence reads the package into a HeistPlan.
            return [.input: .string(input)]
        }

        if entry != nil {
            throw ValidationError("--entry is only valid with Swift source input")
        }

        let fields = try loadJSONObject(
            inline: inline,
            fromFile: path,
            optionName: "plan"
        )
        return try requestParameters(from: fields)
    }

    private static func requestParameters(from fields: [String: HeistValue]) throws -> CLIRequestParameters {
        var request: CLIRequestParameters = [:]
        for (field, value) in fields {
            guard let key = FenceParameterKey(rawValue: field) else {
                throw ValidationError("plan contains an invalid empty field name")
            }
            request.set(key, value)
        }
        return request
    }
}
