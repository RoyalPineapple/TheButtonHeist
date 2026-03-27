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

    @Option(name: .long, help: "Match element by accessibility label (exact)")
    var label: String?

    @Option(name: .long, help: "Element heistId (from get_interface)")
    var heistId: String?

    @Option(name: .long, help: "Match element by accessibility identifier (exact)")
    var identifier: String?

    @Option(name: .long, help: "Match element by accessibility value (exact)")
    var value: String?

    @Option(name: .long, help: "Required traits (all must be present)")
    var traits: [String] = []

    @Option(name: .long, help: "Excluded traits (none may be present)")
    var excludeTraits: [String] = []

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
        guard heistId != nil || label != nil || identifier != nil || value != nil
            || !traits.isEmpty || !excludeTraits.isEmpty else {
            throw ValidationError("Must specify --heist-id or at least one match field (--label, --identifier, --value, --traits, or --exclude-traits)")
        }

        let hasMatcher = label != nil || identifier != nil || value != nil
            || !traits.isEmpty || !excludeTraits.isEmpty
        let matcher = hasMatcher ? ElementMatcher(
            label: label,
            identifier: identifier,
            value: value,
            traits: traits.isEmpty ? nil : traits,
            excludeTraits: excludeTraits.isEmpty ? nil : excludeTraits
        ) : nil

        var searchDirection: ScrollSearchDirection?
        if let direction {
            guard let dir = ScrollSearchDirection(rawValue: direction.lowercased()) else {
                throw ValidationError("Invalid direction '\(direction)'. Valid: down, up, left, right")
            }
            searchDirection = dir
        }

        let target = ScrollToVisibleTarget(
            heistId: heistId,
            match: matcher,
            maxScrolls: maxScrolls,
            direction: searchDirection
        )

        let connector = DeviceConnector(deviceFilter: connection.device, token: connection.token, quiet: connection.quiet)
        try await connector.connect()
        defer { connector.disconnect() }

        let message = ClientMessage.scrollToVisible(target)

        if !connection.quiet {
            logStatus("Searching for element...")
        }

        connector.send(message)

        let result = try await connector.waitForActionResult(timeout: timeout)
        outputActionResult(result, format: output.format, quiet: connection.quiet, verb: "Scroll to visible")
    }
}
