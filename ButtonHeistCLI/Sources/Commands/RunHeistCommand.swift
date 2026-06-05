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
        let request = try Self.planArguments(
            inline: plan,
            fromFile: planFromFile,
            input: input,
            entry: entry
        )

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            command: Self.fenceCommand,
            arguments: Self.fenceArguments(request),
            statusMessage: "Running heist..."
        )
    }

    static func planArguments(inline: String?, fromFile path: String?) throws -> CLIRequestParameters {
        try planArguments(inline: inline, fromFile: path, input: nil, entry: nil)
    }

    /// Build the run_heist request parameters.
    ///
    /// A `.heist` package artifact path is forwarded to the fence as an `input`
    /// path; the fence reads the package into a `HeistPlan` rather than the CLI
    /// re-encoding the plan through a parameter round-trip. `.swift` DSL source
    /// is compiled locally (it needs the toolchain) and sent inline, as are
    /// `--plan` / `--plan-from-file` JSON.
    static func planArguments(
        inline: String?,
        fromFile path: String?,
        input: String?,
        entry: String?,
        compileSwiftFile: SwiftHeistCompiler = { source, entry in
            try HeistSourceCompiler().compileSwiftFile(source, entry: entry)
        }
    ) throws -> CLIRequestParameters {
        let suppliedSources = [inline != nil, path != nil, input != nil].filter { $0 }.count
        guard suppliedSources == 1 else {
            if suppliedSources == 0 {
                throw ValidationError("Must supply a plan path, --plan, or --plan-from-file")
            }
            throw ValidationError("plan path, --plan, and --plan-from-file are mutually exclusive")
        }

        if let input {
            return try inputArguments(path: input, entry: entry, compileSwiftFile: compileSwiftFile)
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

    private static func inputArguments(
        path: String,
        entry: String?,
        compileSwiftFile: SwiftHeistCompiler
    ) throws -> CLIRequestParameters {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        switch url.pathExtension.lowercased() {
        case "heist":
            guard entry == nil else {
                throw ValidationError("--entry is only valid with Swift source input")
            }
            // Forward the artifact path; the fence reads the package into a HeistPlan.
            return [.input: .string(path)]
        case "swift":
            guard let entry, !entry.isEmpty else {
                throw ValidationError("--entry is required for Swift source input")
            }
            do {
                let plan = try compileSwiftFile(url, entry)
                return try requestParameters(for: plan.named(url.deletingPathExtension().lastPathComponent))
            } catch let error as ValidationError {
                throw error
            } catch {
                throw ValidationError("failed to compile Swift heist source: \(error)")
            }
        default:
            throw ValidationError(
                "Unsupported run_heist input for \(path). Use a .heist package artifact or .swift source " +
                "(raw .json plan IR is internal to the .heist package, not a run input)."
            )
        }
    }

    private static func requestParameters(for plan: HeistPlan) throws -> CLIRequestParameters {
        let data = try JSONEncoder().encode(plan)
        let fields = try JSONDecoder().decode([String: HeistValue].self, from: data)
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
