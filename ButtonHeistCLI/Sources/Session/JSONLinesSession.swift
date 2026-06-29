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
            // Swift.readLine() is a blocking syscall; detaching from MainActor keeps JSON-lines input responsive.
            // swiftlint:disable:next agent_no_task_detached
            guard let line = await Task.detached(operation: { Swift.readLine() }).value else {
                break
            }

            idleMonitor?.resetTimer()

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let envelope = await processLine(trimmed)
            outputResponse(envelope)
        }

        idleMonitor?.stop()
        idleMonitor = nil
        fence.stop()
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

    private func processLine(_ line: String) async -> CLIRunner.ResponseEnvelope {
        let parsedRequest: CLIParsedRequest
        do {
            parsedRequest = try CLIRequestBuilder.parsedRequest(from: line)
        } catch let error as CLIRequestBuildError {
            return CLIRunner.ResponseEnvelope(
                response: .error(error.diagnosticFailure),
                requestId: error.requestId
            )
        } catch {
            return CLIRunner.ResponseEnvelope(response: .failure(error))
        }

        do {
            let response = try await fence.execute(parsedRequest.operation)
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
