import Foundation
import Darwin
import ButtonHeist

@MainActor
final class SessionRunner {
    private let format: OutputFormat
    private let mastermind: TheMastermind
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
        self.mastermind = TheMastermind(
            configuration: .init(
                deviceFilter: deviceFilter,
                connectionTimeout: connectionTimeout,
                forceSession: force,
                token: token,
                autoReconnect: true
            )
        )
        self.mastermind.onStatus = { message in
            logStatus(message)
        }
    }

    func run() async throws {
        try await mastermind.start()

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

        mastermind.stop()
    }

    private func processLine(_ line: String) async -> (MastermindResponse, Any?) {
        guard
            let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let command = object["command"] as? String
        else {
            return (.error("Invalid JSON or missing 'command' field"), nil)
        }

        let requestId = object["id"]

        do {
            let response = try await mastermind.execute(request: object)
            if command == "quit" || command == "exit" {
                shouldExit = true
                isRunning = false
            }
            return (response, requestId)
        } catch {
            if let mastermindError = error as? MastermindError, let message = mastermindError.errorDescription {
                return (.error(message), requestId)
            }
            return (.error("Internal error: \(error.localizedDescription)"), requestId)
        }
    }

    private func outputResponse(_ response: MastermindResponse, id: Any?) {
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
