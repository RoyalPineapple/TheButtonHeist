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

    @OptionGroup var selection: ScrollSelectionInput

    @Option(
        name: .shortAndLong,
        help: "Edge to scroll to: \(Self.catalogAllowedValuesDescription(for: FenceParameters.scrollEdge))"
    )
    var edge: String = Self.catalogDefaultArgument(for: FenceParameters.scrollEdge)

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions
    @OptionGroup var timeoutOption: TimeoutOption

    @ButtonHeistActor
    mutating func run() async throws {
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            command: Self.fenceCommand,
            arguments: try requestArguments(),
            statusMessage: "Sending scroll_to_edge..."
        )
    }

    func requestArguments() throws -> TheFence.CommandArgumentEnvelope {
        guard let scrollEdge = Self.catalogCanonicalValue(edge, for: FenceParameters.scrollEdge) else {
            throw ValidationError("Invalid edge '\(edge)'. Valid: \(Self.catalogAllowedValuesDescription(for: FenceParameters.scrollEdge))")
        }

        let scrollSelection = try selection.scrollSelection()
        return Self.fenceArguments(
            target: scrollSelection.cliTarget,
            CommandArgumentWriter.value(FenceParameters.scrollEdge, scrollEdge),
            CommandArgumentWriter.value(.timeout, timeoutOption.timeout),
            CommandArgumentWriter.optional(.containerName, scrollSelection.cliContainerName?.rawValue)
        )
    }
}
