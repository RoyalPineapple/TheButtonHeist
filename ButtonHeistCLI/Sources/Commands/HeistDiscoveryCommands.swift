import ArgumentParser
import ButtonHeist

struct ListHeistsCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "List reusable heists in a .heist artifact or inline plan",
        discussion: """
            Lists the root entry and all named reusable heists derived from one
            decoded, runtime-admitted plan.

            Examples:
              buttonheist list_heists --path Flow.heist
              buttonheist list_heists --detail --path Flow.heist
              buttonheist list_heists --plan '{"version":1,"name":"flow","body":[{"type":"warn","warn":{"message":"Check"}}]}'
            """
    )

    @Option(name: .long, help: "Path to a .heist package artifact.")
    var path: String?

    @OptionGroup var output: OutputOptions

    @Option(name: .long, help: "Inline canonical heist plan JSON object")
    var plan: String?

    @Flag(name: .long, help: "Include derived command names, nested heist calls, counts, and safe semantic surface summaries.")
    var detail = false

    @Option(name: .long, help: "Path to a JSON file containing a canonical heist plan object")
    var planFromFile: String?

    @ButtonHeistActor
    mutating func run() async throws {
        var request = try RunHeistCommand.planArguments(
            inline: plan,
            fromFile: planFromFile,
            path: path,
            entry: nil,
            commandName: Self.cliCommandName
        )
        if detail {
            request.set(.detail, "detailed")
        }
        try await Self.runLocal(
            command: Self.fenceCommand,
            arguments: Self.fenceArguments(request),
            format: output.format
        )
    }
}

struct DescribeHeistCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Describe one reusable heist in a .heist artifact or inline plan",
        discussion: """
            Describes the selected root entry or named reusable heist from one
            decoded, runtime-admitted plan.

            Examples:
              buttonheist describe_heist checkout --path Flow.heist
              buttonheist describe_heist Cart.checkout --plan '{"version":1,"name":"flow","body":[{"type":"warn","warn":{"message":"Check"}}]}'
            """
    )

    @Argument(help: "Root entry or capability name to describe.")
    var name: String

    @Option(name: .long, help: "Path to a .heist package artifact.")
    var path: String?

    @OptionGroup var output: OutputOptions

    @Option(name: .long, help: "Inline canonical heist plan JSON object")
    var plan: String?

    @Option(name: .long, help: "Path to a JSON file containing a canonical heist plan object")
    var planFromFile: String?

    @ButtonHeistActor
    mutating func run() async throws {
        var request = try RunHeistCommand.planArguments(
            inline: plan,
            fromFile: planFromFile,
            path: path,
            entry: nil,
            commandName: Self.cliCommandName
        )
        request.set(.heist, name)
        try await Self.runLocal(
            command: Self.fenceCommand,
            arguments: Self.fenceArguments(request),
            format: output.format
        )
    }
}

private extension CLICommandContract {
    @ButtonHeistActor
    static func runLocal(
        command: TheFence.Command,
        arguments: TheFence.CommandArgumentEnvelope,
        format: OutputFormat?
    ) async throws {
        let fence = TheFence(configuration: EnvironmentConfig.resolve(autoReconnect: false).fenceConfiguration)
        defer { fence.stop() }
        let response = try await fence.execute(command: command, arguments: arguments)
        CLIRunner.outputResponse(response, format: format ?? .auto)
        if response.isFailure {
            throw ExitCode.failure
        }
    }
}
