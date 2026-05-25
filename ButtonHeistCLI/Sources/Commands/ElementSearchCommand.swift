import ArgumentParser
import ButtonHeist

struct ElementSearchCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
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

    @Option(name: .shortAndLong, help: "Starting scroll direction: \(Self.catalogAllowedValuesDescription(for: .direction))")
    var direction: String?

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 30.0

    @ButtonHeistActor
    mutating func run() async throws {
        _ = try element.requireTarget()

        let scrollDirection: String?
        if let direction {
            guard let parsedDirection = Self.catalogCanonicalStringValue(direction, for: .direction) else {
                throw ValidationError("Invalid direction '\(direction)'. Valid: \(Self.catalogAllowedValuesDescription(for: .direction))")
            }
            scrollDirection = parsedDirection
        } else {
            scrollDirection = nil
        }

        var request = Self.fenceRequest([.timeout: .double(timeout)])
        try element.applyTo(&request)
        if let scrollDirection { request.set(.direction, scrollDirection) }

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Searching for element..."
        )
    }
}
