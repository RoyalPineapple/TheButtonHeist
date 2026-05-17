import ArgumentParser
import ButtonHeist

struct ElementSearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: TheFence.Command.elementSearch.rawValue,
        abstract: "Search for an element by scrolling",
        discussion: """
            Scrolls the current screen while looking for an element that matches \
            the specified criteria. Use when the element has not been seen yet. \
            All match fields are AND'd together.

            Examples:
              buttonheist element_search -l "Color Picker"
              buttonheist element_search -id "market.row.colorPicker"
              buttonheist element_search -l "Settings" --traits button
              buttonheist element_search -l "Color Picker" -d up
            """
    )

    @OptionGroup var element: ElementTargetOptions

    @Option(name: .shortAndLong, help: "Starting scroll direction: down, up, left, right (default: down)")
    var direction: String?

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 30.0

    @ButtonHeistActor
    mutating func run() async throws {
        _ = try element.requireTarget()

        if let direction {
            guard ScrollSearchDirection(rawValue: direction.lowercased()) != nil else {
                throw ValidationError("Invalid direction '\(direction)'. Valid: down, up, left, right")
            }
        }

        var request: [String: Any] = [
            "command": TheFence.Command.elementSearch.rawValue,
            "timeout": timeout,
        ]
        try element.applyTo(&request)
        if let direction { request["direction"] = direction.lowercased() }

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Searching for element..."
        )
    }
}
