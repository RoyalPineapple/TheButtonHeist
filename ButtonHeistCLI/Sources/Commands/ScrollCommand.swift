import ArgumentParser
@_spi(ButtonHeistTooling) import ButtonHeist
import ThePlans

struct ScrollCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Scroll a scroll view by one page",
        discussion: """
            Scrolls the nearest scroll view ancestor of a target element by
            approximately one page in the given direction. Defaults to down.

            Examples:
              buttonheist scroll
              buttonheist scroll btn_list
              buttonheist scroll btn_list -d up
              buttonheist scroll --identifier "myElement" -d down
            """
    )

    @OptionGroup var element: ElementTargetOptions

    @Option(name: .long, help: "Current-capture containerName from get_interface")
    var container: String?

    @Option(
        name: .shortAndLong,
        help: "Scroll direction: \(Self.catalogAllowedValuesDescription(for: .direction))"
    )
    var direction: String = Self.catalogDefaultString(for: .direction)

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions
    @OptionGroup var timeoutOption: TimeoutOption

    func validate() throws {
        if let container, container.isEmpty {
            throw ValidationError("--container must not be empty")
        }
        if container != nil, try element.hasTarget {
            throw ValidationError("--container cannot be combined with element target options")
        }
    }

    @ButtonHeistActor
    mutating func run() async throws {
        guard let scrollDirection = Self.catalogCanonicalStringValue(direction, for: .direction) else {
            throw ValidationError("Invalid direction '\(direction)'. Valid: \(Self.catalogAllowedValuesDescription(for: .direction))")
        }

        var request: CLIRequestParameters = [
            .direction: .string(scrollDirection),
            .timeout: .double(timeoutOption.timeout),
        ]
        let target: ElementTarget?
        if let container {
            request.set(.container, container)
            target = nil
        } else {
            target = try element.parsedTarget()
        }

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            command: Self.fenceCommand,
            arguments: Self.fenceArguments(request, target: target),
            statusMessage: "Sending scroll..."
        )
    }
}
