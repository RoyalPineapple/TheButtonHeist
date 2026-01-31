# CLI Unix Standards Implementation Plan

## Overview

Update the `a11y-inspect` CLI tool to follow Unix/Linux conventions and Swift best practices using Apple's Swift ArgumentParser library.

## Current State Analysis

- All output goes to stderr via `fputs()`
- No command-line argument parsing
- No machine-readable output formats
- Uses emojis (problematic for piping)
- Only continuous watch mode
- No proper exit codes

### Key Files:
- `AccessibilityInspector/Package.swift` - needs ArgumentParser dependency
- `AccessibilityInspector/AccessibilityInspector/CLI/main.swift` - entry point
- `AccessibilityInspector/AccessibilityInspector/CLI/CLIRunner.swift` - core logic

## Desired End State

A Unix-standard CLI tool that:
```bash
# One-shot JSON output for scripting
a11y-inspect --once --format json | jq '.elements[] | .label'

# Quiet mode - just data, no status
a11y-inspect -q --once > hierarchy.json

# Watch mode with timeout
a11y-inspect --watch --timeout 30

# Human-readable (default)
a11y-inspect

# Show help
a11y-inspect --help
```

### Verification:
- `a11y-inspect --help` shows proper usage
- `a11y-inspect --once --format json` outputs valid JSON to stdout
- Exit code 0 on success, non-zero on errors
- Status messages go to stderr, data to stdout

## What We're NOT Doing

- Subcommands (keeping it simple with options)
- Color output configuration (can add later)
- Config file support
- Shell completion generation (ArgumentParser supports this, can add later)

## Implementation Approach

Use Swift ArgumentParser's `AsyncParsableCommand` for async support with Network framework.

---

## Phase 1: Add ArgumentParser Dependency

### Overview
Add Swift ArgumentParser to the package dependencies.

### Changes Required:

#### 1. Package.swift
**File**: `AccessibilityInspector/Package.swift`

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AccessibilityInspector",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../AccessibilityBridgeProtocol"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "AccessibilityInspector",
            dependencies: [
                .product(name: "AccessibilityBridgeProtocol", package: "AccessibilityBridgeProtocol")
            ],
            path: "AccessibilityInspector",
            exclude: ["CLI"]
        ),
        .executableTarget(
            name: "a11y-inspect",
            dependencies: [
                .product(name: "AccessibilityBridgeProtocol", package: "AccessibilityBridgeProtocol"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "AccessibilityInspector/CLI"
        )
    ]
)
```

### Success Criteria:

#### Automated Verification:
- [x] Package resolves: `cd AccessibilityInspector && swift package resolve`
- [x] Package builds: `cd AccessibilityInspector && swift build --product a11y-inspect`

---

## Phase 2: Create Command Structure

### Overview
Replace main.swift with ArgumentParser-based command structure.

### Changes Required:

#### 1. New main.swift with ArgumentParser
**File**: `AccessibilityInspector/AccessibilityInspector/CLI/main.swift`

```swift
import ArgumentParser
import Foundation

@main
struct A11yInspect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "a11y-inspect",
        abstract: "Inspect iOS app accessibility hierarchy over the network.",
        discussion: """
            Connects to an iOS app running the AccessibilityBridge server and displays
            the accessibility element hierarchy. Useful for accessibility testing and
            debugging SwiftUI/UIKit apps.

            Examples:
              a11y-inspect                     # Interactive watch mode
              a11y-inspect --once              # Single snapshot, then exit
              a11y-inspect --format json       # JSON output for scripting
              a11y-inspect -q --once | jq .    # Quiet mode, pipe to jq
            """,
        version: "1.0.0"
    )

    @Option(name: .shortAndLong, help: "Output format: human, json")
    var format: OutputFormat = .human

    @Flag(name: .shortAndLong, help: "Single snapshot then exit (default: watch mode)")
    var once: Bool = false

    @Flag(name: .shortAndLong, help: "Suppress status messages (only output data)")
    var quiet: Bool = false

    @Option(name: .shortAndLong, help: "Timeout in seconds waiting for device (0 = no timeout)")
    var timeout: Int = 0

    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose: Bool = false

    mutating func run() async throws {
        let options = CLIOptions(
            format: format,
            once: once,
            quiet: quiet,
            timeout: timeout,
            verbose: verbose
        )

        let runner = CLIRunner(options: options)
        try await runner.run()
    }
}

enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    case human
    case json
}

struct CLIOptions {
    let format: OutputFormat
    let once: Bool
    let quiet: Bool
    let timeout: Int
    let verbose: Bool
}
```

### Success Criteria:

#### Automated Verification:
- [x] `a11y-inspect --help` shows usage
- [x] `a11y-inspect --version` shows 1.0.0

---

## Phase 3: Update CLIRunner for Options

### Overview
Refactor CLIRunner to support the new options, proper stdout/stderr separation, and JSON output.

### Changes Required:

#### 1. CLIRunner.swift - Full Refactor
**File**: `AccessibilityInspector/AccessibilityInspector/CLI/CLIRunner.swift`

```swift
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
```

### Success Criteria:

#### Automated Verification:
- [x] Build succeeds: `swift build --product a11y-inspect`
- [x] Help works: `a11y-inspect --help`
- [x] Version works: `a11y-inspect --version`

#### Manual Verification:
- [x] `a11y-inspect --once --format json` outputs valid JSON to stdout
- [x] `a11y-inspect -q --once` shows no status messages
- [x] `a11y-inspect` in watch mode shows keyboard hints
- [x] Ctrl+C exits cleanly
- [x] Exit codes are correct (test with `echo $?`)

---

## Testing Strategy

### Automated Tests:
```bash
# Build
swift build --product a11y-inspect

# Help output
.build/debug/a11y-inspect --help | grep -q "Output format"

# Version
.build/debug/a11y-inspect --version | grep -q "1.0.0"
```

### Manual Testing:
1. Run app in simulator
2. Test each mode:
   - `a11y-inspect` - interactive watch
   - `a11y-inspect --once` - single shot
   - `a11y-inspect --format json --once` - JSON output
   - `a11y-inspect -q --once` - quiet mode
   - `a11y-inspect --timeout 5 --once` - with timeout
3. Verify stdout/stderr separation: `a11y-inspect --once 2>/dev/null | jq .`
4. Verify exit codes after failures

## References

- Swift ArgumentParser: https://github.com/apple/swift-argument-parser
- Current CLI: `AccessibilityInspector/AccessibilityInspector/CLI/`
