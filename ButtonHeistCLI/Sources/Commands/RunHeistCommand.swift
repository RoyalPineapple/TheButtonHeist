import ArgumentParser
import ButtonHeist
import Foundation
import ThePlans

struct RunHeistCommand: AsyncParsableCommand, CLICommandContract {
    typealias SwiftHeistCompiler = (_ source: URL, _ entry: String) throws -> HeistPlan

    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Execute a Button Heist plan from .heist JSON or Swift DSL source",
        discussion: """
            Reads a canonical heist plan object from .heist/.json, or compiles
            Swift DSL source locally before sending the resulting plan through
            the run_heist command path. Existing --plan and --plan-from-file
            JSON inputs remain available for compatibility.

            Examples:
              buttonheist run_heist Flow.heist
              buttonheist run_heist Flow.swift --entry makeHeist
              buttonheist run_heist --plan-from-file plan.json
              buttonheist run_heist --plan '{"version":2,"body":[{"type":"warn","warn":{"message":"Check login state"}}]}'
            """
    )

    @Argument(help: "Path to a .heist/.json plan or Swift DSL source file.")
    var input: String?

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .long, help: "Inline canonical heist plan JSON object")
    var plan: String?

    @Option(name: .long, help: "Path to a JSON file containing a canonical heist plan object")
    var planFromFile: String?

    @Option(name: .long, help: "Zero-argument Swift entry symbol returning Heist or HeistPlan.")
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

    static func planArguments(
        inline: String?,
        fromFile path: String?,
        input: String?,
        entry: String?,
        compileSwiftFile: SwiftHeistCompiler = { source, entry in
            try HeistSourceCompiler().compileSwiftFile(source, entry: entry)
        }
    ) throws -> CLIRequestParameters {
        if input == nil {
            switch (inline, path) {
            case (nil, nil):
                throw ValidationError("Must supply either --plan or --plan-from-file")
            case (.some, .some):
                throw ValidationError("--plan and --plan-from-file are mutually exclusive")
            default:
                break
            }
        }

        let suppliedSources = [inline != nil, path != nil, input != nil].filter { $0 }.count
        guard suppliedSources == 1 else {
            if suppliedSources == 0 {
                throw ValidationError("Must supply a plan path, --plan, or --plan-from-file")
            }
            throw ValidationError("plan path, --plan, and --plan-from-file are mutually exclusive")
        }

        if entry != nil, input == nil {
            throw ValidationError("--entry is only valid with Swift source input")
        }

        if let input {
            return try planArguments(
                fromInputPath: input,
                entry: entry,
                compileSwiftFile: compileSwiftFile
            )
        }

        let fields = try loadJSONObject(
            inline: inline,
            fromFile: path,
            optionName: "plan"
        )
        return try requestParameters(from: fields)
    }

    private static func planArguments(
        fromInputPath path: String,
        entry: String?,
        compileSwiftFile: SwiftHeistCompiler
    ) throws -> CLIRequestParameters {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        switch url.pathExtension.lowercased() {
        case "heist", "json":
            guard entry == nil else {
                throw ValidationError("--entry is only valid with Swift source input")
            }
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw ValidationError("Failed to read \(path): \(error.localizedDescription)")
            }
            let plan: HeistPlan
            do {
                plan = try HeistPlan.decodeValidatedHeistJSON(from: data)
            } catch {
                throw ValidationError("\(path) is not valid .heist JSON: \(error)")
            }
            return try requestParameters(for: plan)

        case "swift":
            guard let entry, !entry.isEmpty else {
                throw ValidationError("--entry is required for Swift source input")
            }
            do {
                let plan = try compileSwiftFile(url, entry)
                return try requestParameters(for: plan)
            } catch {
                throw ValidationError("failed to compile Swift heist source: \(error)")
            }

        default:
            throw ValidationError("Unsupported run_heist input extension for \(path). Use .heist, .json, or .swift.")
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
