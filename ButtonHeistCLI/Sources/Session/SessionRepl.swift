import ArgumentParser
import Foundation
import Darwin
import ButtonHeist

@ButtonHeistActor
final class ReplSession {

    // MARK: - Nested Types

    private enum State {
        case running(IdleMonitor?)
        case exiting
        case stopped
    }

    // MARK: - Properties

    private let format: OutputFormat
    private let fence: TheFence
    private let sessionTimeout: TimeInterval
    private var state: State = .stopped

    // MARK: - Init

    init(config: EnvironmentConfig, format: OutputFormat) {
        self.format = format
        self.sessionTimeout = config.sessionTimeout
        self.fence = TheFence(configuration: config.fenceConfiguration)
        self.fence.onStatus = { message in
            logStatus(message)
        }
    }

    // MARK: - REPL Loop

    func run() async throws {
        try await fence.start()

        let isTTY = isatty(STDIN_FILENO) != 0
        if isTTY {
            logStatus("Session started. Type 'help' for commands, 'quit' to exit.")
            if sessionTimeout > 0 {
                logStatus("Idle timeout: \(Int(sessionTimeout))s")
            }
        }

        // SIGINT closes stdin to unstick the blocking readLine; the loop sees
        // a nil line and breaks, then runs the same structured teardown the
        // idle-timeout path uses (idleMonitor.stop, state = .stopped,
        // fence.stop). close() is async-signal-safe; we deliberately do NOT
        // touch Swift state from here.
        signal(SIGINT) { _ in close(STDIN_FILENO) }

        let monitor = sessionTimeout > 0 ? makeTimeoutMonitor() : nil
        state = .running(monitor)

        loop: while case .running(let idleMonitor) = state {
            if isTTY {
                fputs("> ", stderr)
                fflush(stderr)
            }

            // Swift.readLine() is a blocking syscall; detaching from MainActor keeps the REPL responsive.
            // swiftlint:disable:next agent_no_task_detached
            guard let line = await Task.detached(operation: { Swift.readLine() }).value else {
                break
            }

            idleMonitor?.resetTimer()

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let (response, requestId) = await processLine(trimmed)
            outputResponse(response, id: requestId)

            if case .exiting = state { break loop }
        }

        if case .running(let idleMonitor) = state {
            idleMonitor?.stop()
        }
        state = .stopped
        fence.stop()
    }

    private func makeTimeoutMonitor() -> IdleMonitor {
        let monitor = IdleMonitor(timeout: sessionTimeout) { [weak self] in
            guard let self else { return }
            logStatus("Session idle timeout (\(Int(self.sessionTimeout))s) — exiting.")
            self.state = .exiting
            close(STDIN_FILENO)
        }
        monitor.resetTimer()
        return monitor
    }

    private func processLine(_ line: String) async -> (FenceResponse, Any?) {
        let request: [String: Any]

        if line.hasPrefix("{") {
            // JSON mode — machine interface
            do {
                request = try Self.parseMachineRequest(line)
            } catch {
                return (.error("Invalid JSON: \(error.localizedDescription)"), nil)
            }
        } else {
            // Human-friendly mode
            request = Self.parseHumanInput(line)
        }

        guard let command = request[.command] as? String else {
            return (.error("Unknown command. Type 'help' for available commands."), nil)
        }

        let requestId = request["id"]
        let parsedCommand = TheFence.Command(rawValue: command)

        // Enhanced help for human mode
        if parsedCommand == .help && format == .human && !line.hasPrefix("{") {
            return (.ok(message: Self.humanHelp), nil)
        }

        do {
            let response = try await fence.execute(request: request)
            if parsedCommand == .quit || parsedCommand == .exit {
                if case .running(let idleMonitor) = state {
                    idleMonitor?.stop()
                }
                state = .exiting
            }
            return (response, requestId)
        } catch {
            return (.failure(error), requestId)
        }
    }

    private static func parseMachineRequest(_ line: String) throws -> [String: Any] {
        let data = Data(line.utf8)
        let value = try JSONDecoder().decode(HeistValue.self, from: data)
        guard case .object(let object) = value,
              case .string? = object[FenceParameterKey.command.rawValue] else {
            throw ValidationError("Expected JSON object with string field 'command'")
        }
        return object.mapValues { $0.toAny() }
    }

    // MARK: - Output

    private func outputResponse(_ response: FenceResponse, id: Any?) {
        switch format {
        case .human:
            writeOutput(response.humanFormatted())
        case .compact:
            writeOutput(response.compactFormatted())
        case .json:
            var dictionary = response.jsonDict()
            if let id {
                dictionary["id"] = id
            }
            do {
                let data = try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])
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

// MARK: - Human-Friendly Input Parser

nonisolated extension ReplSession {

    static var humanHelp: String {
        let commandLines = descriptorHelpLines()
        let aliasLines = aliasHelpLines()
        let aliasSection = aliasLines.isEmpty ? "" : """

            Aliases:
        \(aliasLines.joined(separator: "\n"))
        """

        return """
        Commands (type a command, or use JSON for full control):

        Commands:
        \(commandLines.joined(separator: "\n"))
        \(aliasSection)

        Bare words are looked up as current heistId handles (from get_interface).
        Key=value pairs work for any parameter: tap identifier=btn x=100 y=200
        JSON input still works: {"command":"activate","heistId":"button_save"}
        """
    }

    private static func descriptorHelpLines() -> [String] {
        let descriptors = TheFence.Command.descriptors
            .filter { descriptor in descriptor.cliExposure != .notExposed }
            .sorted { $0.canonicalName < $1.canonicalName }
        let width = descriptors.map(\.canonicalName.count).max() ?? 0

        return descriptors.map { descriptor in
            "  \(padded(descriptor.canonicalName, to: width))  \(oneLineDescription(descriptor.description))"
        }
    }

    private static func aliasHelpLines() -> [String] {
        var aliases: [HelpAlias] = []
        for descriptor in TheFence.Command.descriptors {
            for alias in descriptor.humanAliases.keys {
                aliases.append(HelpAlias(alias: alias, command: descriptor.canonicalName))
            }
        }
        aliases.sort { lhs, rhs in
            lhs.alias == rhs.alias ? lhs.command < rhs.command : lhs.alias < rhs.alias
        }

        let width = aliases.map(\.alias.count).max() ?? 0
        return aliases.map { alias in
            "  \(padded(alias.alias, to: width))  -> \(alias.command)"
        }
    }

    private static func oneLineDescription(_ description: String) -> String {
        description
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
    }

    private static func padded(_ value: String, to width: Int) -> String {
        guard value.count < width else { return value }
        return value + String(repeating: " ", count: width - value.count)
    }

    private struct HelpAlias {
        let alias: String
        let command: String
    }

    private struct HumanCommandRequest {
        let command: TheFence.Command?
        let rawCommand: String
        private var typedParameters: CLIRequestParameters
        private var extraParameters: [(name: String, value: HeistValue)]

        init(command: TheFence.Command, parameters: CLIRequestParameters = [:]) {
            self.command = command
            self.rawCommand = command.rawValue
            self.typedParameters = parameters
            self.extraParameters = []
        }

        init(alias: FenceCommandAlias) {
            self.init(command: alias.command, parameters: alias.parameters)
        }

        init(rawCommand: String) {
            self.command = nil
            self.rawCommand = rawCommand
            self.typedParameters = [:]
            self.extraParameters = []
        }

        subscript(_ key: FenceParameterKey) -> HeistValue? {
            get { typedParameters[key] }
            set { typedParameters[key] = newValue }
        }

        mutating func setParameter(named name: String, value: HeistValue) {
            if let key = FenceParameterKey(rawValue: name) {
                self[key] = value
            } else {
                extraParameters.append((name, value))
            }
        }

        func fenceRequest() -> [String: Any] {
            var request: [String: Any]
            if let command {
                request = command.cliRequest(typedParameters)
            } else {
                request = FenceParameterKey.rawDictionary(typedParameters)
                request[.command] = rawCommand
            }
            for parameter in extraParameters {
                request[parameter.name] = parameter.value.toAny()
            }
            return request
        }
    }

    static func parseHumanInput(_ line: String) -> [String: Any] {
        let tokens = tokenize(line)
        guard let first = tokens.first else { return [:] }

        let rawCommand = first.lowercased()
        var request: HumanCommandRequest
        let args = Array(tokens.dropFirst())

        if let alias = TheFence.Command.humanAlias(named: rawCommand) {
            request = HumanCommandRequest(alias: alias)
        } else if let command = TheFence.Command(rawValue: rawCommand) {
            request = HumanCommandRequest(command: command)
        } else {
            request = HumanCommandRequest(rawCommand: rawCommand)
        }

        // Separate key=value pairs from positional tokens
        var positional: [String] = []
        for arg in args {
            if let eqIndex = arg.firstIndex(of: "="), eqIndex != arg.startIndex {
                let key = String(arg[arg.startIndex..<eqIndex])
                let value = String(arg[arg.index(after: eqIndex)...])
                request.setParameter(
                    named: key,
                    value: parseHumanValue(value, forParameterNamed: key, command: request.command)
                )
            } else {
                positional.append(arg)
            }
        }

        // Interpret positional arguments based on command context
        interpretPositionalArgs(positional: positional, into: &request)
        normalizeExpectationArgument(in: &request)

        return request.fenceRequest()
    }

    private static func parseHumanValue(
        _ value: String,
        forParameterNamed parameterName: String,
        command: TheFence.Command?
    ) -> HeistValue {
        guard let spec = command?.parameters.first(where: { $0.key == parameterName }) else {
            return parseHumanValue(value)
        }

        switch spec.type {
        case .boolean:
            switch value.lowercased() {
            case "true":
                return .bool(true)
            case "false":
                return .bool(false)
            default:
                return .string(value)
            }
        case .integer:
            if let intValue = Int(value) {
                return .int(intValue)
            }
            return .string(value)
        case .number:
            if let doubleValue = Double(value) {
                return .double(doubleValue)
            }
            return .string(value)
        case .string, .stringArray, .object, .array:
            return .string(value)
        }
    }

    private static func parseHumanValue(_ value: String) -> HeistValue {
        switch value.lowercased() {
        case "true":
            return .bool(true)
        case "false":
            return .bool(false)
        default:
            if let intValue = Int(value) {
                return .int(intValue)
            }
            if let doubleValue = Double(value) {
                return .double(doubleValue)
            }
            return .string(value)
        }
    }

    private static func normalizeExpectationArgument(in request: inout HumanCommandRequest) {
        guard case .string(let rawExpectation)? = request[.expect],
              let expectation = try? ExpectationArgumentParser.parse(rawExpectation) else {
            return
        }
        request[.expect] = expectation
    }

    private static func interpretPositionalArgs(
        positional: [String],
        into request: inout HumanCommandRequest
    ) {
        guard !positional.isEmpty else { return }

        switch request.command?.humanPositionalSyntax ?? .target {
        case .joinedText(let parameter):
            if request[parameter] == nil {
                request[parameter] = .string(positional.joined(separator: " "))
            }

        case .firstToken(let parameter):
            if request[parameter] == nil, let token = positional.first {
                request[parameter] = .string(token)
            }

        case .leadingEdgeThenTarget(let edgeValues):
            var remaining = positional
            if let first = remaining.first, edgeValues.contains(first.lowercased()) {
                request[.edge] = .string(first.lowercased())
                remaining.removeFirst()
            }
            applyElementTarget(remaining, into: &request)

        case .targetThenJoinedText(let parameter):
            if let first = positional.first {
                applyElementTarget([first], into: &request)
                if positional.count > 1 {
                    request[parameter] = .string(positional.dropFirst().joined(separator: " "))
                }
            }

        case .leadingDirectionThenTarget(let directionValues):
            var remaining = positional

            if let first = remaining.first, directionValues.contains(first.lowercased()) {
                request[.direction] = .string(first.lowercased())
                remaining.removeFirst()
            }
            applyGenericTargetOrCoordinates(remaining, into: &request)

        case .target:
            applyGenericTargetOrCoordinates(positional, into: &request)
        }
    }

    private static func applyGenericTargetOrCoordinates(
        _ tokens: [String],
        into request: inout HumanCommandRequest
    ) {
        if tokens.count >= 2,
           let x = Double(tokens[0]),
           let y = Double(tokens[1]) {
            request[.x] = .double(x)
            request[.y] = .double(y)
        } else {
            applyElementTarget(tokens, into: &request)
        }
    }

    private static func applyElementTarget(_ tokens: [String], into request: inout HumanCommandRequest) {
        guard let first = tokens.first else { return }
        request[.heistId] = .string(first)
    }

    private static func tokenize(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuote: Character?
        var iterator = line.makeIterator()

        while let ch = iterator.next() {
            if let quote = inQuote {
                if ch == quote {
                    inQuote = nil
                } else {
                    current.append(ch)
                }
            } else if ch == "\"" || ch == "'" {
                inQuote = ch
            } else if ch == " " || ch == "\t" {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}
