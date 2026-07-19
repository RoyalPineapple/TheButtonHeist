import Foundation
import Darwin
@_spi(ButtonHeistInternals) @_spi(ButtonHeistTooling) import ButtonHeist

@ButtonHeistActor
final class JSONLinesSession {

    // MARK: - Properties

    private let format: OutputFormat
    private let fence: TheFence
    private let sessionTimeout: TimeInterval
    private var idleMonitor: IdleMonitor?

    // MARK: - Init

    init(config: EnvironmentConfig, format: OutputFormat) {
        self.format = format
        self.sessionTimeout = config.sessionTimeout
        self.fence = TheFence(configuration: config.fenceConfiguration)
        self.fence.onStatus = { message in
            logStatus(message)
        }
    }

    // MARK: - JSON Lines Loop

    func run() async throws {
        try await fence.start()

        if sessionTimeout > 0 {
            logStatus("Idle timeout: \(Int(sessionTimeout))s")
        }

        // SIGINT closes stdin to unstick the blocking readLine; the loop sees a
        // nil line and runs the same structured teardown as EOF/idle timeout.
        signal(SIGINT) { _ in close(STDIN_FILENO) }

        idleMonitor = sessionTimeout > 0 ? makeTimeoutMonitor() : nil

        while true {
            guard let line = await Self.readInputLine() else {
                break
            }

            idleMonitor?.resetTimer()

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let envelope = await executeRequestLine(trimmed)
            outputResponse(envelope)
        }

        idleMonitor?.stop()
        idleMonitor = nil
        fence.stop()
    }

    /// Blocking standard input runs on Swift's generic executor rather than
    /// inheriting the session actor.
    @concurrent
    private nonisolated static func readInputLine() async -> String? {
        Swift.readLine()
    }

    private func makeTimeoutMonitor() -> IdleMonitor {
        let monitor = IdleMonitor(timeout: sessionTimeout) { [weak self] in
            guard let self else { return }
            logStatus("JSON-lines session idle timeout (\(Int(self.sessionTimeout))s) — exiting.")
            close(STDIN_FILENO)
        }
        monitor.resetTimer()
        return monitor
    }

    private func executeRequestLine(_ line: String) async -> CLIRunner.ResponseEnvelope {
        let parsedRequest: CLIParsedRequest
        do {
            parsedRequest = try CLIMachineRequestParser.parsedRequest(from: line)
        } catch let error as CLIMachineRequestError {
            return CLIRunner.ResponseEnvelope(
                response: .error(error.diagnosticFailure),
                requestId: error.requestId
            )
        } catch {
            return CLIRunner.ResponseEnvelope(response: .failure(error))
        }

        do {
            let operation = try fence.admit(parsedRequest.input)
            let response = try await fence.execute(operation)
            return CLIRunner.ResponseEnvelope(response: response, requestId: parsedRequest.requestId)
        } catch {
            return CLIRunner.ResponseEnvelope(response: .failure(error), requestId: parsedRequest.requestId)
        }
    }

    // MARK: - Output

    private func outputResponse(_ envelope: CLIRunner.ResponseEnvelope) {
        CLIRunner.output(.response(CLIRunner.FormattedResponse(envelope: envelope, format: format)))
    }
}
