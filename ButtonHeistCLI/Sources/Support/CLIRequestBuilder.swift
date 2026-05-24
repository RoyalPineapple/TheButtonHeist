import ArgumentParser
import ButtonHeist
import Foundation

enum CLIRequestInputMode: Equatable {
    case human
    case machine
}

struct CLIParsedRequest {
    let request: [String: Any]
    let descriptor: FenceCommandDescriptor?
    let mode: CLIRequestInputMode

    var command: TheFence.Command? {
        descriptor?.command
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

        return try parseHumanTokens(tokenize(line))
    }

    static func parseHumanInput(_ line: String) -> [String: Any] {
        (try? parseHumanTokens(tokenize(line)).request) ?? [:]
    }

    static func parseHumanTokens(_ tokens: [String]) throws -> CLIParsedRequest {
        guard let first = tokens.first else {
            throw ValidationError("Unknown command. Type 'help' for available commands.")
        }

        let rawCommand = first.lowercased()
        let args = Array(tokens.dropFirst())
        var draft = try requestDraft(for: rawCommand)

        var positional: [String] = []
        for arg in args {
            if let eqIndex = arg.firstIndex(of: "="), eqIndex != arg.startIndex {
                let key = String(arg[arg.startIndex..<eqIndex])
                let value = String(arg[arg.index(after: eqIndex)...])
                try draft.setParameter(
                    named: key,
                    value: try parseHumanValue(value, forParameterNamed: key, descriptor: draft.descriptor)
                )
            } else {
                positional.append(arg)
            }
        }

        interpretPositionalArgs(positional, into: &draft)
        normalizeExpectationArgument(in: &draft)

        return CLIParsedRequest(
            request: draft.fenceRequest(),
            descriptor: draft.descriptor,
            mode: .human
        )
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
              case .string(let commandName)? = object[FenceParameterKey.command.rawValue] else {
            throw ValidationError("Expected JSON object with string field 'command'")
        }
        return CLIParsedRequest(
            request: object.mapValues(\.cliRawValue),
            descriptor: FenceCommandDescriptor.descriptor(canonicalName: commandName),
            mode: .machine
        )
    }

    static func diagnosticMessage(for error: Error) -> String {
        let description = String(describing: error)
        return description.isEmpty ? error.localizedDescription : description
    }

    private static func requestDraft(for rawCommand: String) throws -> RequestDraft {
        if let alias = TheFence.Command.humanAlias(named: rawCommand) {
            return RequestDraft(alias: alias)
        }

        if let descriptor = FenceCommandDescriptor.descriptor(namedForCLIInput: rawCommand) {
            return RequestDraft(descriptor: descriptor)
        }

        throw ValidationError("Unknown command '\(rawCommand)'. Type 'help' for available commands.")
    }

    private static func parseHumanValue(
        _ value: String,
        forParameterNamed parameterName: String,
        descriptor: FenceCommandDescriptor
    ) throws -> HeistValue {
        guard let spec = descriptor.parameters.first(where: { $0.key == parameterName }) else {
            throw ValidationError("Unknown parameter '\(parameterName)' for \(descriptor.canonicalName)")
        }

        switch spec.type {
        case .boolean:
            switch value.lowercased() {
            case "true":
                return .bool(true)
            case "false":
                return .bool(false)
            default:
                throw ValidationError("Invalid value '\(value)' for \(parameterName); expected true or false")
            }
        case .integer:
            if let intValue = Int(value) {
                return .int(intValue)
            }
            throw ValidationError("Invalid value '\(value)' for \(parameterName); expected integer")
        case .number:
            if let doubleValue = Double(value) {
                return .double(doubleValue)
            }
            throw ValidationError("Invalid value '\(value)' for \(parameterName); expected number")
        case .string, .stringArray, .object, .array:
            return .string(value)
        }
    }

    private static func normalizeExpectationArgument(in draft: inout RequestDraft) {
        guard case .string(let rawExpectation)? = draft[.expect],
              let expectation = try? TheFence.parseExpectationArgument(rawExpectation) else {
            return
        }
        draft[.expect] = expectation
    }

    private static func interpretPositionalArgs(
        _ positional: [String],
        into draft: inout RequestDraft
    ) {
        guard !positional.isEmpty else { return }

        switch draft.descriptor.humanPositionalSyntax {
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

private extension FenceCommandDescriptor {
    static func descriptor(namedForCLIInput name: String) -> FenceCommandDescriptor? {
        TheFence.Command.descriptors.first { descriptor in
            descriptor.canonicalName == name || descriptor.cliName == name
        }
    }

    static func descriptor(canonicalName name: String) -> FenceCommandDescriptor? {
        TheFence.Command.descriptors.first { descriptor in
            descriptor.canonicalName == name
        }
    }
}

private struct RequestDraft {
    let descriptor: FenceCommandDescriptor
    private var typedParameters: CLIRequestParameters

    init(descriptor: FenceCommandDescriptor, parameters: CLIRequestParameters = [:]) {
        self.descriptor = descriptor
        self.typedParameters = parameters
    }

    init(alias: FenceCommandAlias) {
        self.init(descriptor: alias.command.descriptor, parameters: alias.parameters)
    }

    subscript(_ key: FenceParameterKey) -> HeistValue? {
        get { typedParameters[key] }
        set { typedParameters[key] = newValue }
    }

    mutating func setParameter(named name: String, value: HeistValue) throws {
        guard let key = FenceParameterKey(rawValue: name) else {
            throw ValidationError("Parameter '\(name)' is not supported by CLI request rendering")
        }
        self[key] = value
    }

    func fenceRequest() -> [String: Any] {
        return CLIRequestBuilder.request(command: descriptor.command, parameters: typedParameters)
    }
}
