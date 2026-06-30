import ArgumentParser
@_spi(ButtonHeistTooling) import ButtonHeist
import ThePlans

struct ScrollToEdgeCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Scroll to the edge of a scroll view",
        discussion: """
            Scrolls an explicit or primary scroll view all the way to the
            specified edge. Defaults to top.

            Examples:
              buttonheist scroll_to_edge
              buttonheist scroll_to_edge btn_list
              buttonheist scroll_to_edge btn_list -e top
              buttonheist scroll_to_edge --identifier "longList" -e left
            """
    )

    @OptionGroup var element: ElementTargetOptions

    @Option(name: .long, help: "Current-capture containerName from get_interface")
    var container: String?

    @Option(
        name: .shortAndLong,
        help: "Edge to scroll to: \(Self.catalogAllowedValuesDescription(for: .edge))"
    )
    var edge: String = Self.catalogDefaultString(for: .edge)

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
        guard let scrollEdge = Self.catalogCanonicalStringValue(edge, for: .edge) else {
            throw ValidationError("Invalid edge '\(edge)'. Valid: \(Self.catalogAllowedValuesDescription(for: .edge))")
        }

        let target: ElementTarget?
        if container != nil {
            target = nil
        } else {
            target = try element.parsedTarget()
        }
        let arguments = Self.fenceArguments(
            target: target,
            CommandArgumentWriter.value(.edge, scrollEdge),
            CommandArgumentWriter.value(.timeout, timeoutOption.timeout),
            CommandArgumentWriter.optional(.container, container)
        )

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            command: Self.fenceCommand,
            arguments: arguments,
            statusMessage: "Sending scroll_to_edge..."
        )
    }
}
