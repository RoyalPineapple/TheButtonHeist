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
            logStatus(TheFence.Command.cliSessionStartupPrompt)
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

    private func processLine(_ line: String) async -> (FenceResponse, PublicRequestId?) {
        let isMachineInput = line.hasPrefix("{")
        let parsedRequest: CLIParsedRequest
        do {
            parsedRequest = try CLIRequestBuilder.parsedRequest(
                from: line,
                acceptsHumanInput: format != .json
            )
        } catch {
            let message = CLIRequestBuilder.diagnosticMessage(for: error)
            let requestId = (error as? CLIRequestBuildError)?.requestId
            if isMachineInput {
                return (.error("Invalid JSON: \(message)"), requestId)
            }
            return (.error(message), nil)
        }

        // Enhanced help for human mode
        if parsedRequest.command == .help && format == .human && parsedRequest.mode == .human {
            return (.ok(message: TheFence.Command.cliSessionHelp), nil)
        }

        do {
            let response = try await fence.execute(command: parsedRequest.command, arguments: parsedRequest.arguments)
            if parsedRequest.command == .quit {
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

    private func outputResponse(_ response: FenceResponse, id: PublicRequestId?) {
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
