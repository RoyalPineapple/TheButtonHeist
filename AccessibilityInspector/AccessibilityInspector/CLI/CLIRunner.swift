import Foundation
import Network
import Darwin
import AccessibilityBridgeProtocol

// MARK: - Output Helpers

/// Write to stderr (status messages)
func logStatus(_ message: String) {
    fputs("\(message)\n", stderr)
}

/// Write to stdout (data output)
func writeOutput(_ message: String) {
    print(message)
    fflush(stdout)
}

// MARK: - Exit Codes

enum ExitCode: Int32 {
    case success = 0
    case connectionFailed = 1
    case noDeviceFound = 2
    case timeout = 3
    case unknown = 99
}

// MARK: - CLI Runner

@MainActor
final class CLIRunner {
    private let options: CLIOptions
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var isRunning = true
    private var previousElements: [AccessibilityElementData] = []
    private var oldTermios = termios()
    private var hasReceivedHierarchy = false
    private var exitCode: ExitCode = .success

    init(options: CLIOptions) {
        self.options = options
    }

    func run() async throws {
        setupSignalHandlers()

        if !options.quiet {
            logStatus("Searching for iOS devices...")
        }

        await browseForDevices()

        if exitCode != .success {
            Darwin.exit(exitCode.rawValue)
        }
    }

    private func setupSignalHandlers() {
        signal(SIGINT) { _ in
            Darwin.exit(0)
        }
    }

    private func browseForDevices() async {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(
            for: .bonjour(type: accessibilityBridgeServiceType, domain: "local."),
            using: parameters
        )

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                await self?.handleBrowseResults(results)
            }
        }

        browser?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleBrowserState(state)
            }
        }

        browser?.start(queue: .main)

        // Handle timeout
        if options.timeout > 0 {
            Task {
                try? await Task.sleep(nanoseconds: UInt64(options.timeout) * 1_000_000_000)
                if await self.connection == nil {
                    await MainActor.run {
                        if !self.options.quiet {
                            logStatus("Timeout: No device found within \(self.options.timeout) seconds")
                        }
                        self.exitCode = .timeout
                        self.isRunning = false
                    }
                }
            }
        }

        // Keep running
        while isRunning {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func handleBrowserState(_ state: NWBrowser.State) {
        switch state {
        case .failed(let error):
            if !options.quiet {
                logStatus("Error: Browser failed - \(error.localizedDescription)")
            }
            exitCode = .connectionFailed
            isRunning = false
        case .cancelled:
            if options.verbose {
                logStatus("Browser cancelled")
            }
        default:
            break
        }
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) async {
        guard connection == nil else { return }

        for result in results {
            if case let .service(name, _, _, _) = result.endpoint {
                if !options.quiet {
                    logStatus("Found device: \(name)")
                    logStatus("Connecting...")
                }
                await connect(to: result.endpoint)
                return
            }
        }
    }

    private func connect(to endpoint: NWEndpoint) async {
        let parameters = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        connection = NWConnection(to: endpoint, using: parameters)

        connection?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleConnectionState(state)
            }
        }

        connection?.start(queue: .main)
    }

    private func handleConnectionState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            if !options.quiet {
                logStatus("Connected")
            }
            receiveMessages()

            // In watch mode with human format, enable keyboard
            if !options.once && options.format == .human {
                if !options.quiet {
                    logStatus("Commands: [r]efresh  [q]uit")
                }
                startKeyboardMonitoring()
            }

        case .failed(let error):
            if !options.quiet {
                logStatus("Error: Connection failed - \(error.localizedDescription)")
            }
            exitCode = .connectionFailed
            connection = nil
            isRunning = false

        case .cancelled:
            if options.verbose {
                logStatus("Connection cancelled")
            }
            connection = nil

        default:
            break
        }
    }

    private func receiveMessages() {
        connection?.receiveMessage { [weak self] data, context, isComplete, error in
            Task { @MainActor in
                if let data = data {
                    self?.handleReceivedData(data)
                }
                if error == nil {
                    self?.receiveMessages()
                }
            }
        }
    }

    private func handleReceivedData(_ data: Data) {
        guard let message = try? JSONDecoder().decode(ServerMessage.self, from: data) else {
            if !options.quiet {
                logStatus("Warning: Failed to decode message")
            }
            return
        }

        switch message {
        case .info(let info):
            if options.verbose {
                logStatus("App: \(info.appName) (\(info.bundleIdentifier))")
                logStatus("Device: \(info.deviceName) - iOS \(info.systemVersion)")
            }
            send(.subscribe)
            send(.requestHierarchy)

        case .hierarchy(let payload):
            outputHierarchy(payload)
            hasReceivedHierarchy = true

            // In once mode, exit after first hierarchy
            if options.once {
                isRunning = false
            }

        case .pong:
            break

        case .error(let errorMessage):
            if !options.quiet {
                logStatus("Error: \(errorMessage)")
            }
        }
    }

    private func outputHierarchy(_ payload: HierarchyPayload) {
        switch options.format {
        case .json:
            outputJSON(payload)
        case .human:
            outputHuman(payload)
        }
    }

    private func outputJSON(_ payload: HierarchyPayload) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(payload),
           let json = String(data: data, encoding: .utf8) {
            writeOutput(json)
        }
    }

    private func outputHuman(_ payload: HierarchyPayload) {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium

        var output = ""
        output += "Accessibility Hierarchy (\(formatter.string(from: payload.timestamp)))\n"
        output += String(repeating: "-", count: 60) + "\n"

        if payload.elements.isEmpty {
            output += "  (no elements)\n"
        } else {
            let previousSet = Set(previousElements)
            let currentSet = Set(payload.elements)
            let added = currentSet.subtracting(previousSet)

            for element in payload.elements {
                let changed = !previousElements.isEmpty && added.contains(element)
                output += formatElement(element, changed: changed)
            }
        }

        output += String(repeating: "-", count: 60) + "\n"
        output += "Total: \(payload.elements.count) elements\n"

        if !previousElements.isEmpty {
            let prevCount = previousElements.count
            let currCount = payload.elements.count
            if prevCount != currCount {
                output += "Change: \(prevCount) -> \(currCount) elements\n"
            }
        }

        previousElements = payload.elements
        writeOutput(output)
    }

    private func formatElement(_ element: AccessibilityElementData, changed: Bool) -> String {
        var output = ""
        let prefix = changed ? "* " : "  "
        let index = String(format: "[%2d]", element.traversalIndex)
        let traits = element.traits.isEmpty ? "" : " (\(element.traits.joined(separator: ", ")))"
        let label = element.label ?? element.description

        output += "\(prefix)\(index) \(label)\(traits)\n"

        if let value = element.value, !value.isEmpty {
            output += "       Value: \(value)\n"
        }
        if let hint = element.hint, !hint.isEmpty {
            output += "       Hint: \(hint)\n"
        }
        if let id = element.identifier, !id.isEmpty {
            output += "       ID: \(id)\n"
        }
        if !element.customActions.isEmpty {
            output += "       Actions: \(element.customActions.joined(separator: ", "))\n"
        }

        let frame = "(\(Int(element.frameX)), \(Int(element.frameY))) \(Int(element.frameWidth))x\(Int(element.frameHeight))"
        output += "       Frame: \(frame)\n"

        return output
    }

    private func send(_ message: ClientMessage) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "message", metadata: [metadata])
        connection?.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }

    func stop() {
        isRunning = false
        tcsetattr(STDIN_FILENO, TCSANOW, &oldTermios)
        connection?.cancel()
        browser?.cancel()
    }

    // MARK: - Keyboard Input (watch mode only)

    private func startKeyboardMonitoring() {
        tcgetattr(STDIN_FILENO, &oldTermios)
        var newTermios = oldTermios
        newTermios.c_lflag &= ~UInt(ICANON | ECHO)
        newTermios.c_cc.16 = 1
        newTermios.c_cc.17 = 0
        tcsetattr(STDIN_FILENO, TCSANOW, &newTermios)

        Task.detached {
            let stdin = FileHandle.standardInput
            while await self.isRunning {
                let data = stdin.availableData
                if data.isEmpty { continue }
                if let str = String(data: data, encoding: .utf8) {
                    for char in str {
                        await MainActor.run {
                            self.handleKeypress(char)
                        }
                    }
                }
            }
        }
    }

    private func handleKeypress(_ char: Character) {
        switch char.lowercased() {
        case "r", "\n", "\r":
            if !options.quiet {
                logStatus("Refreshing...")
            }
            send(.requestHierarchy)
        case "q":
            stop()
        default:
            break
        }
    }
}
