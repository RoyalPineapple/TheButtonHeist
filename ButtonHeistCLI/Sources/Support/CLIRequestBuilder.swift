import ArgumentParser
import ButtonHeist
import Foundation

enum CLIRequestInputMode: Equatable {
    case human
    case machine
}

struct CLIParsedRequest {
    let request: [String: Any]
    let mode: CLIRequestInputMode

    var commandName: String? {
        request[.command] as? String
    }

    var command: TheFence.Command? {
        commandName.flatMap(TheFence.Command.init(rawValue:))
    }

    var requestId: Any? {
        request["id"]
    }
}

enum CLIRequestBuilder {

    static func request(
        command: TheFence.Command,
        parameters: CLIRequestParameters = [:]
    ) -> [String: Any] {
        var request = FenceParameterKey.rawDictionary(parameters)
        request[.command] = command.rawValue
        return request
    }

    static func parsedRequest(from line: String) throws -> CLIParsedRequest {
        if line.hasPrefix("{") {
            return try parseMachineRequest(line)
        }

        return parseHumanTokens(tokenize(line))
    }

    static func parseHumanInput(_ line: String) -> [String: Any] {
        parseHumanTokens(tokenize(line)).request
    }

    static func parseHumanTokens(_ tokens: [String]) -> CLIParsedRequest {
        guard let first = tokens.first else {
            return CLIParsedRequest(request: [:], mode: .human)
        }

        let rawCommand = first.lowercased()
        let args = Array(tokens.dropFirst())
        var draft = requestDraft(for: rawCommand)

        var positional: [String] = []
        for arg in args {
            if let eqIndex = arg.firstIndex(of: "="), eqIndex != arg.startIndex {
                let key = String(arg[arg.startIndex..<eqIndex])
                let value = String(arg[arg.index(after: eqIndex)...])
                draft.setParameter(
                    named: key,
                    value: parseHumanValue(value, forParameterNamed: key, command: draft.command)
                )
            } else {
                positional.append(arg)
            }
        }

        interpretPositionalArgs(positional, into: &draft)
        normalizeExpectationArgument(in: &draft)

        return CLIParsedRequest(request: draft.fenceRequest(), mode: .human)
    }

    static func tokenize(_ line: String) -> [String] {
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

    static func parseMachineRequest(_ line: String) throws -> CLIParsedRequest {
        let data = Data(line.utf8)
        let value = try JSONDecoder().decode(HeistValue.self, from: data)
        guard case .object(let object) = value,
              case .string? = object[FenceParameterKey.command.rawValue] else {
            throw ValidationError("Expected JSON object with string field 'command'")
        }
        return CLIParsedRequest(request: object.mapValues { $0.toAny() }, mode: .machine)
    }

    private static func requestDraft(for rawCommand: String) -> RequestDraft {
        if let alias = TheFence.Command.humanAlias(named: rawCommand) {
            return RequestDraft(alias: alias)
        }

        if let descriptor = TheFence.Command.descriptor(namedForCLIInput: rawCommand) {
            return RequestDraft(command: descriptor.command)
        }

        return RequestDraft(rawCommand: rawCommand)
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

    private static func normalizeExpectationArgument(in draft: inout RequestDraft) {
        guard case .string(let rawExpectation)? = draft[.expect],
              let expectation = try? ExpectationArgumentParser.parse(rawExpectation) else {
            return
        }
        draft[.expect] = expectation
    }

    private static func interpretPositionalArgs(
        _ positional: [String],
        into draft: inout RequestDraft
    ) {
        guard !positional.isEmpty else { return }

        switch draft.command?.humanPositionalSyntax ?? .target {
        case .joinedText(let parameter):
            if draft[parameter] == nil {
                draft[parameter] = .string(positional.joined(separator: " "))
            }

        case .firstToken(let parameter):
            if draft[parameter] == nil, let token = positional.first {
                draft[parameter] = .string(token)
            }

        case .leadingEdgeThenTarget(let edgeValues):
            var remaining = positional
            if let first = remaining.first, edgeValues.contains(first.lowercased()) {
                draft[.edge] = .string(first.lowercased())
                remaining.removeFirst()
            }
            applyElementTarget(remaining, into: &draft)

        case .targetThenJoinedText(let parameter):
            if let first = positional.first {
                applyElementTarget([first], into: &draft)
                if positional.count > 1 {
                    draft[parameter] = .string(positional.dropFirst().joined(separator: " "))
                }
            }

        case .leadingDirectionThenTarget(let directionValues):
            var remaining = positional
            if let first = remaining.first, directionValues.contains(first.lowercased()) {
                draft[.direction] = .string(first.lowercased())
                remaining.removeFirst()
            }
            applyGenericTargetOrCoordinates(remaining, into: &draft)

        case .target:
            applyGenericTargetOrCoordinates(positional, into: &draft)
        }
    }

    private static func applyGenericTargetOrCoordinates(
        _ tokens: [String],
        into draft: inout RequestDraft
    ) {
        if tokens.count >= 2,
           let x = Double(tokens[0]),
           let y = Double(tokens[1]) {
            draft[.x] = .double(x)
            draft[.y] = .double(y)
        } else {
            applyElementTarget(tokens, into: &draft)
        }
    }

    private static func applyElementTarget(_ tokens: [String], into draft: inout RequestDraft) {
        guard let first = tokens.first else { return }
        draft[.heistId] = .string(first)
    }
}

private extension TheFence.Command {
    static func descriptor(namedForCLIInput name: String) -> FenceCommandDescriptor? {
        descriptors.first { descriptor in
            descriptor.canonicalName == name || descriptor.cliName == name
        }
    }
}

private struct RequestDraft {
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
            request = CLIRequestBuilder.request(command: command, parameters: typedParameters)
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
