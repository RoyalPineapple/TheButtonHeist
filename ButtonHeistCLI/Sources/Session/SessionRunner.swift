import Foundation
import Darwin
import ButtonHeist

@MainActor
final class SessionRunner {
    private let format: OutputFormat
    private let fence: TheFence
    private let sessionTimeout: TimeInterval
    private var isRunning = true
    private var shouldExit = false
    private nonisolated(unsafe) var lastCommandTime = ContinuousClock.now
    private var timeoutTask: Task<Void, Never>?

    init(
        deviceFilter: String?,
        connectionTimeout: Double,
        format: OutputFormat,
        force: Bool = false,
        token: String? = nil,
        sessionTimeout: Double = 0
    ) {
        self.format = format
        if sessionTimeout > 0 {
            self.sessionTimeout = sessionTimeout
        } else if let envValue = ProcessInfo.processInfo.environment["BUTTONHEIST_SESSION_TIMEOUT"],
                  let parsed = Double(envValue), parsed > 0 {
            self.sessionTimeout = parsed
        } else {
            self.sessionTimeout = 0
        }
        self.fence = TheFence(
            configuration: .init(
                deviceFilter: deviceFilter,
                connectionTimeout: connectionTimeout,
                forceSession: force,
                token: token,
                autoReconnect: true
            )
        )
        self.fence.onStatus = { message in
            logStatus(message)
        }
    }

    func run() async throws {
        try await fence.start()

        let isTTY = isatty(STDIN_FILENO) != 0
        if isTTY {
            logStatus("Session started. Send JSON commands or {\"command\":\"quit\"} to exit.")
            if sessionTimeout > 0 {
                logStatus("Idle timeout: \(Int(sessionTimeout))s")
            }
        }

        signal(SIGINT) { _ in Darwin.exit(0) }

        lastCommandTime = .now
        if sessionTimeout > 0 {
            startTimeoutMonitor()
        }

        while isRunning {
            if isTTY {
                fputs("> ", stderr)
                fflush(stderr)
            }

            guard let line = await Task.detached(operation: { Swift.readLine() }).value else {
                break
            }

            lastCommandTime = .now

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let (response, requestId) = await processLine(trimmed)
            outputResponse(response, id: requestId)

            if shouldExit { break }
        }

        timeoutTask?.cancel()
        fence.stop()
    }

    private func startTimeoutMonitor() {
        timeoutTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(SessionDefaults.timeoutCheckInterval))
                guard !Task.isCancelled, let self else { return }
                let elapsed = ContinuousClock.now - self.lastCommandTime
                if elapsed > .seconds(self.sessionTimeout) {
                    logStatus("Session idle timeout (\(Int(self.sessionTimeout))s) — exiting.")
                    self.isRunning = false
                    close(STDIN_FILENO)
                    return
                }
            }
        }
    }

    private func processLine(_ line: String) async -> (FenceResponse, Any?) {
        guard
            let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let command = object["command"] as? String
        else {
            return (.error("Invalid JSON or missing 'command' field"), nil)
        }

        let requestId = object["id"]

        do {
            let response = try await fence.execute(request: object)
            if command == "quit" || command == "exit" {
                shouldExit = true
                isRunning = false
            }
            return (response, requestId)
        } catch {
            if let fenceError = error as? FenceError, let message = fenceError.errorDescription {
                return (.error(message), requestId)
            }
            return (.error("Internal error: \(error.localizedDescription)"), requestId)
        }
    }

    private func outputResponse(_ response: FenceResponse, id: Any?) {
        switch format {
        case .human:
            writeOutput(response.humanFormatted())
        case .json:
            if var dictionary = response.jsonDict() {
                if let id {
                    dictionary["id"] = id
                }
                if let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]),
                   let json = String(data: data, encoding: .utf8) {
                    writeOutput(json)
                }
            }
        }
    }
}
