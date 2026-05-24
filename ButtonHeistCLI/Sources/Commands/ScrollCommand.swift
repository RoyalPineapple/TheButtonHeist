import ArgumentParser
import ButtonHeist

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
              buttonheist scroll --stable-id "main_scroll"
              buttonheist scroll -id "myElement" -d next
            """
    )

    @OptionGroup var element: ElementTargetOptions

    @Option(name: .customLong("stable-id"), help: "Scrollable container stableId from get_interface")
    var stableId: String?

    @Option(name: .shortAndLong, help: "Scroll direction: up, down, left, right, next, previous (default: down)")
    var direction: String = Self.catalogDefaultString(for: .direction)

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions
    @OptionGroup var timeoutOption: TimeoutOption

    @ButtonHeistActor
    mutating func run() async throws {
        guard let scrollDirection = ScrollDirection(rawValue: direction.lowercased()) else {
            throw ValidationError("Invalid direction '\(direction)'. Valid: \(ScrollDirection.allCases.map(\.rawValue).joined(separator: ", "))")
        }

        var request = Self.fenceRequest([
            .direction: .string(scrollDirection.rawValue),
            .timeout: .double(timeoutOption.timeout),
        ])
        if let stableId { request.set(.stableId, stableId) }
        try element.applyTo(&request)

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Sending scroll..."
        )
    }
}
