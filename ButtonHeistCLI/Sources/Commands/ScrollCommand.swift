import ArgumentParser
import ButtonHeist

struct ScrollCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scroll",
        abstract: "Scroll a scroll view by one page",
        discussion: """
            Scrolls the nearest scroll view ancestor of a target element by
            approximately one page in the given direction. Defaults to down.

            Examples:
              buttonheist scroll btn_list
              buttonheist scroll btn_list -d up
              buttonheist scroll -id "myElement" -d next
            """
    )

    @OptionGroup var element: ElementTargetOptions

    @Option(name: .shortAndLong, help: "Scroll direction: up, down, left, right, next, previous (default: down)")
    var direction: String = "down"

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        _ = try element.requireTarget()

        guard ScrollDirection(rawValue: direction.lowercased()) != nil else {
            throw ValidationError("Invalid direction '\(direction)'. Valid: up, down, left, right, next, previous")
        }

        var request: [String: Any] = [
            "command": TheFence.Command.scroll.rawValue,
            "direction": direction.lowercased(),
            "timeout": timeout,
        ]
        try element.applyTo(&request)

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Sending scroll..."
        )
    }
}
