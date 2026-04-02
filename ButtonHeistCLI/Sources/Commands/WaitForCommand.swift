import ArgumentParser
import ButtonHeist

struct WaitForCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wait_for",
        abstract: "Wait for an element matching a predicate to appear or disappear",
        discussion: """
            Waits for an element matching the given predicate to appear (or \
            disappear with --absent). Uses settle-event polling, not busy-waiting. \
            Timeout is capped at 30 seconds.

            Examples:
              buttonheist wait_for btn_login
              buttonheist wait_for -l "Loading" -a -t 5
              buttonheist wait_for -l "Welcome" --traits staticText
            """
    )

    @OptionGroup var element: ElementTargetOptions

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Maximum wait time in seconds (default: 10, max: 30)")
    var timeout: Double = 10.0

    @Flag(name: .shortAndLong, help: "Wait for element to NOT exist (disappear)")
    var absent: Bool = false

    @ButtonHeistActor
    mutating func run() async throws {
        _ = try element.requireTarget()

        var request: [String: Any] = [
            "command": TheFence.Command.waitFor.rawValue,
            "timeout": timeout,
        ]
        try element.applyTo(&request)
        if absent { request["absent"] = true }

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: absent ? "Waiting for element to disappear..." : "Waiting for element to appear..."
        )
    }
}
