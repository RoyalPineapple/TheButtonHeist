import Foundation
import Darwin
import ButtonHeist

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

            let (response, requestId) = await processLine(trimmed)
            outputResponse(response, id: requestId)
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

    private func processLine(_ line: String) async -> (FenceResponse, PublicRequestId?) {
        let isMachineInput = line.hasPrefix("{")
        let parsedRequest: CLIParsedRequest
        do {
            parsedRequest = try CLIRequestBuilder.parsedRequest(from: line)
        } catch {
            let message = CLIRequestBuilder.diagnosticMessage(for: error)
            let requestId = (error as? CLIRequestBuildError)?.requestId
            if isMachineInput {
                return (.error("Invalid JSON: \(message)"), requestId)
            }
            return (.error(message), nil)
        }

        do {
            let response = try await fence.execute(command: parsedRequest.command, arguments: parsedRequest.arguments)
            return (response, parsedRequest.requestId)
        } catch {
            return (.failure(error), parsedRequest.requestId)
        }
    }

    // MARK: - Output

    private func outputResponse(_ response: FenceResponse, id: PublicRequestId?) {
        let presenter = FenceResponsePresenter(profile: .summary)
        switch format {
        case .human:
            writeOutput(presenter.humanText(for: response))
        case .compact:
            writeOutput(presenter.compactText(for: response))
        case .json:
            do {
                let data = try presenter.jsonData(for: response, requestId: id)
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
