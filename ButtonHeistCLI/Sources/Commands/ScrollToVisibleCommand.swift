import ArgumentParser
import ButtonHeist

struct ScrollToVisibleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scroll_to_visible",
        abstract: "Search for an element by scrolling through the nearest scroll view",
        discussion: """
            Scrolls through the nearest scroll view searching for an element that matches \
            the specified criteria. All match fields are AND'd together. For UITableView and \
            UICollectionView, provides exhaustive search with item count tracking.

            Examples:
              buttonheist scroll_to_visible --heist-id buttonheist.longList.last
              buttonheist scroll_to_visible --label "Color Picker"
              buttonheist scroll_to_visible --identifier "market.row.colorPicker"
              buttonheist scroll_to_visible --label "Settings" --traits button
              buttonheist scroll_to_visible --label "Color Picker" --direction up --max-scrolls 30
            """
    )

    @OptionGroup var element: ElementTargetOptions

    @Option(name: .long, help: "Maximum scroll attempts (default: 20)")
    var maxScrolls: Int?

    @Option(name: .long, help: "Starting scroll direction: down, up, left, right (default: down)")
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
            "command": TheFence.Command.scrollToVisible.rawValue,
            "timeout": timeout,
        ]
        element.applyTo(&request)
        if let maxScrolls { request["maxScrolls"] = maxScrolls }
        if let direction { request["direction"] = direction.lowercased() }

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Searching for element..."
        )
    }
}
