import Foundation
import Darwin
import ButtonHeist

@MainActor
final class SessionRunner {
    private let format: OutputFormat
    private let fence: TheFence
    private var isRunning = true
    private var shouldExit = false

    init(
        deviceFilter: String?,
        connectionTimeout: Double,
        format: OutputFormat,
        force: Bool = false,
        token: String? = nil
    ) {
        self.format = format
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
        }

        signal(SIGINT) { _ in Darwin.exit(0) }

        while isRunning {
            if isTTY {
                fputs("> ", stderr)
                fflush(stderr)
            }

            guard let line = await Task.detached(operation: { Swift.readLine() }).value else {
                break
            }

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let (response, requestId) = await processLine(trimmed)
            outputResponse(response, id: requestId)

            if shouldExit { break }
        }

        fence.stop()
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
