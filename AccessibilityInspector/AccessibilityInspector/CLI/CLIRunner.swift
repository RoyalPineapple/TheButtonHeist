import Foundation
import Network
import Darwin
import AccessibilityBridgeProtocol

/// Print with immediate flush
func output(_ message: String) {
    fputs("\(message)\n", stderr)
}

/// CLI runner for the accessibility inspector
@MainActor
final class CLIRunner {
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var isRunning = true
    private var isSubscribed = false
    private var previousElements: [AccessibilityElementData] = []
    private var oldTermios = termios()

    func run() async {
        output("🔍 Accessibility Inspector CLI")
        output("==============================")
        output("")

        // Start browsing for devices
        output("Searching for iOS devices...")
        await browseForDevices()
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

        browser?.stateUpdateHandler = { state in
            switch state {
            case .failed(let error):
                output("❌ Browser failed: \(error)")
            case .cancelled:
                output("Browser cancelled")
            default:
                break
            }
        }

        browser?.start(queue: .main)

        // Keep running
        while isRunning {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) async {
        guard connection == nil else { return } // Already connected

        for result in results {
            if case let .service(name, _, _, _) = result.endpoint {
                output("✅ Found device: \(name)")
                output("   Connecting...")
                output("")
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
            output("✅ Connected!")
            output("")
            output("Commands: [r]efresh  [q]uit")
            output("")
            receiveMessages()
            startKeyboardMonitoring()
        case .failed(let error):
            output("❌ Connection failed: \(error)")
            connection = nil
        case .cancelled:
            output("Connection cancelled")
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
            output("⚠️ Failed to decode message")
            return
        }

        switch message {
        case .info(let info):
            printServerInfo(info)
            // Subscribe and request hierarchy
            send(.subscribe)
            send(.requestHierarchy)

        case .hierarchy(let payload):
            printHierarchy(payload)

        case .pong:
            break

        case .error(let errorMessage):
            output("❌ Server error: \(errorMessage)")
        }
    }

    private func printServerInfo(_ info: ServerInfo) {
        output("📱 Device Info")
        output("   App: \(info.appName)")
        output("   Bundle ID: \(info.bundleIdentifier)")
        output("   Device: \(info.deviceName)")
        output("   iOS: \(info.systemVersion)")
        output("   Screen: \(Int(info.screenWidth))×\(Int(info.screenHeight))")
        output("")
    }

    private func printHierarchy(_ payload: HierarchyPayload) {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        output("📋 Accessibility Hierarchy (\(formatter.string(from: payload.timestamp)))")
        output(String(repeating: "─", count: 60))

        if payload.elements.isEmpty {
            output("   (no elements)")
        } else {
            let previousSet = Set(previousElements)
            let currentSet = Set(payload.elements)
            let added = currentSet.subtracting(previousSet)

            for element in payload.elements {
                let indicator: String
                if previousElements.isEmpty {
                    indicator = "  "
                } else if added.contains(element) {
                    indicator = "🔄"
                } else {
                    indicator = "  "
                }
                printElement(element, indicator: indicator)
            }
        }

        output(String(repeating: "─", count: 60))
        output("Total: \(payload.elements.count) elements")

        // Show change indicator
        if !previousElements.isEmpty {
            let prevCount = previousElements.count
            let currCount = payload.elements.count
            if prevCount != currCount {
                output("Change: \(prevCount) → \(currCount) elements")
            }
        }

        // Store for next comparison
        previousElements = payload.elements

        output("")
        output("💡 Press [r] to refresh, [q] to quit")
        output("")
    }

    private func printElement(_ element: AccessibilityElementData, indicator: String = "  ") {
        let index = String(format: "[%2d]", element.traversalIndex)
        let traits = element.traits.isEmpty ? "" : " (\(element.traits.joined(separator: ", ")))"

        // Main line
        let label = element.label ?? element.description
        output("\(indicator) \(index) \(label)\(traits)")

        // Details (indented)
        if let value = element.value, !value.isEmpty {
            output("      Value: \(value)")
        }
        if let hint = element.hint, !hint.isEmpty {
            output("      Hint: \(hint)")
        }
        if let id = element.identifier, !id.isEmpty {
            output("      ID: \(id)")
        }
        if !element.customActions.isEmpty {
            output("      Actions: \(element.customActions.joined(separator: ", "))")
        }

        // Frame info
        let frame = "(\(Int(element.frameX)), \(Int(element.frameY))) \(Int(element.frameWidth))×\(Int(element.frameHeight))"
        output("      Frame: \(frame)")
        output("")
    }

    private func send(_ message: ClientMessage) {
        guard let data = try? JSONEncoder().encode(message) else { return }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "message", metadata: [metadata])

        connection?.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }

    func stop() {
        isRunning = false
        // Restore terminal settings
        tcsetattr(STDIN_FILENO, TCSANOW, &oldTermios)
        connection?.cancel()
        browser?.cancel()
    }

    // MARK: - Keyboard Input

    private func startKeyboardMonitoring() {
        // Set terminal to raw mode for immediate key reading
        tcgetattr(STDIN_FILENO, &oldTermios)
        var newTermios = oldTermios
        newTermios.c_lflag &= ~UInt(ICANON | ECHO)
        newTermios.c_cc.16 = 1  // VMIN - minimum chars to read
        newTermios.c_cc.17 = 0  // VTIME - timeout
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
            output("🔄 Refreshing...")
            send(.requestHierarchy)
        case "q":
            output("👋 Exiting...")
            stop()
        default:
            break
        }
    }
}
