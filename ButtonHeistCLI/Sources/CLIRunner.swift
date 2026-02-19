import Foundation
import Darwin
import ButtonHeist

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
    private let client = HeistClient()
    private var isRunning = true
    private var previousElements: [UIElement] = []
    private var oldTermios = termios()
    private var hasReceivedInterface = false
    private var exitCode: ExitCode = .success

    init(options: CLIOptions) {
        self.options = options
    }

    func run() async throws {
        setupSignalHandlers()
        setupClientCallbacks()

        if !options.quiet {
            logStatus("Searching for iOS devices...")
        }

        client.startDiscovery()

        // Handle timeout
        if options.timeout > 0 {
            Task {
                try? await Task.sleep(nanoseconds: UInt64(options.timeout) * 1_000_000_000)
                await MainActor.run {
                    if self.client.connectedDevice == nil {
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

        if exitCode != .success {
            Darwin.exit(exitCode.rawValue)
        }
    }

    private func setupSignalHandlers() {
        signal(SIGINT) { _ in
            Darwin.exit(0)
        }
    }

    private func setupClientCallbacks() {
        // Handle device discovery
        client.onDeviceDiscovered = { [weak self] device in
            guard let self = self else { return }
            if self.client.connectedDevice == nil {
                // Apply device filter if specified
                if let filter = self.options.device {
                    guard device.matches(filter: filter) else { return }
                }
                if !self.options.quiet {
                    logStatus("Found: \(self.client.displayName(for: device))")
                    logStatus("Connecting...")
                }
                self.client.connect(to: device)
            }
        }

        // Handle connection success
        client.onConnected = { [weak self] info in
            guard let self = self else { return }
            if !self.options.quiet {
                let displayName = self.client.connectedDeviceDisplayName ?? info.appName
                logStatus("Connected to \(displayName)")
            }
            if self.options.verbose {
                logStatus("  Bundle: \(info.bundleIdentifier)")
                logStatus("  Device: \(info.deviceName) - iOS \(info.systemVersion)")
            }

            // In watch mode with human format, enable keyboard
            if !self.options.once && self.options.format == .human {
                if !self.options.quiet {
                    logStatus("Commands: [r]efresh  [q]uit")
                }
                self.startKeyboardMonitoring()
            }
        }

        // Handle disconnection
        client.onDisconnected = { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                if !self.options.quiet {
                    logStatus("Error: Connection failed - \(error.localizedDescription)")
                }
                self.exitCode = .connectionFailed
            }
            self.isRunning = false
        }

        // Handle interface updates
        client.onInterfaceUpdate = { [weak self] payload in
            guard let self = self else { return }
            self.outputInterface(payload)
            self.hasReceivedInterface = true

            // In once mode, exit after first snapshot
            if self.options.once {
                self.isRunning = false
            }
        }
    }

    private func outputInterface(_ payload: Interface) {
        switch options.format {
        case .json:
            outputJSON(payload)
        case .human:
            outputHuman(payload)
        }
    }

    private func outputJSON(_ payload: Interface) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(payload),
           let json = String(data: data, encoding: .utf8) {
            writeOutput(json)
        }
    }

    private func outputHuman(_ payload: Interface) {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium

        var output = ""
        output += "Elements (\(formatter.string(from: payload.timestamp)))\n"
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

    private func formatElement(_ element: UIElement, changed: Bool) -> String {
        var output = ""
        let prefix = changed ? "* " : "  "
        let index = String(format: "[%2d]", element.order)
        let label = element.label ?? element.description

        output += "\(prefix)\(index) \(label)\n"

        if let value = element.value, !value.isEmpty {
            output += "       Value: \(value)\n"
        }
        if let id = element.identifier, !id.isEmpty {
            output += "       ID: \(id)\n"
        }
        if !element.actions.isEmpty {
            output += "       Actions: \(element.actions.map(\.description).joined(separator: ", "))\n"
        }

        let frame = "(\(Int(element.frameX)), \(Int(element.frameY))) \(Int(element.frameWidth))x\(Int(element.frameHeight))"
        output += "       Frame: \(frame)\n"

        return output
    }

    func stop() {
        isRunning = false
        tcsetattr(STDIN_FILENO, TCSANOW, &oldTermios)
        client.disconnect()
        client.stopDiscovery()
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
            client.requestInterface()
        case "q":
            stop()
        default:
            break
        }
    }
}
