import ArgumentParser
import ButtonHeist

struct ScrollCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scroll",
        abstract: "Scroll a scroll view by one page",
        discussion: """
            Scrolls the nearest scroll view ancestor of a target element by
            approximately one page in the given direction via direct content
            offset manipulation.

            Examples:
              buttonheist scroll --identifier "buttonheist.longList.item-5" --direction up
              buttonheist scroll --index 3 --direction down
              buttonheist scroll --identifier "myElement" --direction next
            """
    )

    @OptionGroup var element: ElementTargetOptions

    @Option(name: .long, help: "Scroll direction: up, down, left, right, next, previous")
    var direction: String

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
        element.applyTo(&request)

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Sending scroll..."
        )
    }
}
