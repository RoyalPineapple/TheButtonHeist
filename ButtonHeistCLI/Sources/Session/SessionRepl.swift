import Foundation
import Darwin
import ButtonHeist

@ButtonHeistActor
final class ReplSession {

    // MARK: - Nested Types

    private enum State {
        case running(IdleMonitor?)
        case exiting
        case stopped
    }

    // MARK: - Properties

    private let format: OutputFormat
    private let fence: TheFence
    private let sessionTimeout: TimeInterval
    private var state: State = .stopped

    // MARK: - Init

    init(config: EnvironmentConfig, format: OutputFormat) {
        self.format = format
        self.sessionTimeout = config.sessionTimeout
        self.fence = TheFence(configuration: config.fenceConfiguration)
        self.fence.onStatus = { message in
            logStatus(message)
        }
    }

    // MARK: - REPL Loop

    func run() async throws {
        try await fence.start()

        let isTTY = isatty(STDIN_FILENO) != 0
        if isTTY {
            logStatus("Session started. Type 'help' for commands, 'quit' to exit.")
            if sessionTimeout > 0 {
                logStatus("Idle timeout: \(Int(sessionTimeout))s")
            }
        }

        // SIGINT closes stdin to unstick the blocking readLine; the loop sees
        // a nil line and breaks, then runs the same structured teardown the
        // idle-timeout path uses (idleMonitor.stop, state = .stopped,
        // fence.stop). close() is async-signal-safe; we deliberately do NOT
        // touch Swift state from here.
        signal(SIGINT) { _ in close(STDIN_FILENO) }

        let monitor = sessionTimeout > 0 ? makeTimeoutMonitor() : nil
        state = .running(monitor)

        loop: while case .running(let idleMonitor) = state {
            if isTTY {
                fputs("> ", stderr)
                fflush(stderr)
            }

            // Swift.readLine() is a blocking syscall; detaching from MainActor keeps the REPL responsive.
            // swiftlint:disable:next agent_no_task_detached
            guard let line = await Task.detached(operation: { Swift.readLine() }).value else {
                break
            }

            idleMonitor?.resetTimer()

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let (response, requestId) = await processLine(trimmed)
            outputResponse(response, id: requestId)

            if case .exiting = state { break loop }
        }

        if case .running(let idleMonitor) = state {
            idleMonitor?.stop()
        }
        state = .stopped
        fence.stop()
    }

    private func makeTimeoutMonitor() -> IdleMonitor {
        let monitor = IdleMonitor(timeout: sessionTimeout) { [weak self] in
            guard let self else { return }
            logStatus("Session idle timeout (\(Int(self.sessionTimeout))s) — exiting.")
            self.state = .exiting
            close(STDIN_FILENO)
        }
        monitor.resetTimer()
        return monitor
    }

    private func processLine(_ line: String) async -> (FenceResponse, Any?) {
        let isMachineInput = line.hasPrefix("{")
        let parsedRequest: CLIParsedRequest
        do {
            parsedRequest = try CLIRequestBuilder.parsedRequest(from: line)
        } catch {
            let message = CLIRequestBuilder.diagnosticMessage(for: error)
            if isMachineInput {
                return (.error("Invalid JSON: \(message)"), nil)
            }
            return (.error(message), nil)
        }

        let request = parsedRequest.request
        guard request[.command] is String else {
            return (.error("Unknown command. Type 'help' for available commands."), nil)
        }

        // Enhanced help for human mode
        if parsedRequest.command == .help && format == .human && parsedRequest.mode == .human {
            return (.ok(message: Self.humanHelp), nil)
        }

        do {
            let response = try await fence.execute(request: request)
            if parsedRequest.command == .quit || parsedRequest.command == .exit {
                if case .running(let idleMonitor) = state {
                    idleMonitor?.stop()
                }
                state = .exiting
            }
            return (response, parsedRequest.requestId)
        } catch {
            return (.failure(error), parsedRequest.requestId)
        }
    }

    // MARK: - Output

    private func outputResponse(_ response: FenceResponse, id: Any?) {
        switch format {
        case .human:
            writeOutput(response.humanFormatted())
        case .compact:
            writeOutput(response.compactFormatted())
        case .json:
            do {
                let data = try response.jsonData(requestId: id)
                if let json = String(data: data, encoding: .utf8) {
                    writeOutput(json)
                } else {
                    logStatus("Failed to encode JSON data as UTF-8")
                }
            } catch {
                logStatus("Failed to serialize response as JSON: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Human-Friendly Help

nonisolated extension ReplSession {

    static var humanHelp: String {
        let commandLines = descriptorHelpLines()
        let aliasLines = aliasHelpLines()
        let aliasSection = aliasLines.isEmpty ? "" : """

            Aliases:
        \(aliasLines.joined(separator: "\n"))
        """

        return """
        Commands (type a command, or use JSON for full control):

        Commands:
        \(commandLines.joined(separator: "\n"))
        \(aliasSection)

        Bare words are looked up as current heistId handles (from get_interface).
        Key=value pairs work for any parameter: tap identifier=btn x=100 y=200
        JSON input still works: {"command":"activate","heistId":"button_save"}
        """
    }

    private static func descriptorHelpLines() -> [String] {
        let descriptors = TheFence.Command.descriptors
            .filter { descriptor in descriptor.cliName != nil }
            .sorted { $0.canonicalName < $1.canonicalName }
        let width = descriptors.map(\.canonicalName.count).max() ?? 0

        return descriptors.map { descriptor in
            "  \(padded(descriptor.canonicalName, to: width))  \(oneLineDescription(descriptor.description))"
        }
    }

    private static func aliasHelpLines() -> [String] {
        var aliases = TheFence.Command.humanCommandAliases.map { entry in
            (alias: entry.key, command: entry.value.command.canonicalName)
        }
        aliases.sort { lhs, rhs in
            lhs.alias == rhs.alias ? lhs.command < rhs.command : lhs.alias < rhs.alias
        }

        let width = aliases.map(\.alias.count).max() ?? 0
        return aliases.map { alias in
            "  \(padded(alias.alias, to: width))  -> \(alias.command)"
        }
    }

    private static func oneLineDescription(_ description: String) -> String {
        description
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
    }

    private static func padded(_ value: String, to width: Int) -> String {
        guard value.count < width else { return value }
        return value + String(repeating: " ", count: width - value.count)
    }

    static func parseHumanInput(_ line: String) throws -> [String: Any] {
        try CLIRequestBuilder.parseHumanInput(line)
    }
}
