import Foundation
import TheScore

/// Canonical request projected from human CLI tokens.
public struct FenceHumanCommandRequest: Sendable, Equatable {
    public let descriptor: FenceCommandDescriptor
    public let parameters: [FenceParameterKey: HeistValue]

    public var command: TheFence.Command { descriptor.command }

    public init(
        descriptor: FenceCommandDescriptor,
        parameters: [FenceParameterKey: HeistValue]
    ) {
        self.descriptor = descriptor
        self.parameters = parameters
    }
}

public struct FenceHumanCommandParsingError: Error, LocalizedError, CustomStringConvertible, Sendable {
    public let message: String

    public var description: String { message }
    public var errorDescription: String? { message }

    public init(_ message: String) {
        self.message = message
    }
}

public extension FenceCommandDescriptor {
    static func descriptor(canonicalName name: String) -> FenceCommandDescriptor? {
        TheFence.Command(rawValue: name)?.descriptor
    }

    static func humanRequest(
        commandName rawCommandName: String,
        arguments: [String]
    ) throws -> FenceHumanCommandRequest {
        var draft = try FenceHumanRequestDraft(commandName: rawCommandName)

        var positional: [String] = []
        for argument in arguments {
            if let eqIndex = argument.firstIndex(of: "="), eqIndex != argument.startIndex {
                let key = String(argument[argument.startIndex..<eqIndex])
                let value = String(argument[argument.index(after: eqIndex)...])
                try draft.setParameter(named: key, rawValue: value)
            } else {
                positional.append(argument)
            }
        }

        try draft.applyPositionalArguments(positional)
        return draft.request
    }

    fileprivate static func descriptor(forCLIInputName name: String) -> FenceCommandDescriptor? {
        return TheFence.Command.descriptors.first { descriptor in
            descriptor.cliExposure != .notExposed
                && descriptor.canonicalName == name
        }
    }

    fileprivate func humanValue(_ value: String, forParameterNamed parameterName: String) throws -> HeistValue {
        guard let spec = parameters.first(where: { $0.key == parameterName }) else {
            throw FenceHumanCommandParsingError("Unknown parameter '\(parameterName)' for \(canonicalName)")
        }

        switch spec.type {
        case .boolean:
            switch value {
            case "true":
                return .bool(true)
            case "false":
                return .bool(false)
            default:
                throw FenceHumanCommandParsingError(
                    "Invalid value '\(value)' for \(parameterName); expected true or false"
                )
            }
        case .integer:
            if let intValue = Int(value) {
                return .int(intValue)
            }
            throw FenceHumanCommandParsingError("Invalid value '\(value)' for \(parameterName); expected integer")
        case .number:
            if let doubleValue = Double(value) {
                return .double(doubleValue)
            }
            throw FenceHumanCommandParsingError("Invalid value '\(value)' for \(parameterName); expected number")
        case .string, .stringArray, .object, .array:
            return .string(value)
        }
    }
}

private struct FenceHumanRequestDraft {
    let descriptor: FenceCommandDescriptor
    private var parameters: [FenceParameterKey: HeistValue]

    init(commandName: String) throws {
        if let descriptor = FenceCommandDescriptor.descriptor(forCLIInputName: commandName) {
            self.init(descriptor: descriptor)
        } else {
            throw FenceHumanCommandParsingError("Unknown command '\(commandName)'. Type 'help' for available commands.")
        }
    }

    private init(
        descriptor: FenceCommandDescriptor,
        parameters: [FenceParameterKey: HeistValue] = [:]
    ) {
        self.descriptor = descriptor
        self.parameters = parameters
    }

    var request: FenceHumanCommandRequest {
        FenceHumanCommandRequest(descriptor: descriptor, parameters: parameters)
    }

    subscript(_ key: FenceParameterKey) -> HeistValue? {
        get { parameters[key] }
        set { parameters[key] = newValue }
    }

    mutating func setParameter(named name: String, rawValue: String) throws {
        guard let key = FenceParameterKey(rawValue: name) else {
            throw FenceHumanCommandParsingError("Parameter '\(name)' is not supported by CLI request rendering")
        }
        self[key] = try descriptor.humanValue(rawValue, forParameterNamed: name)
        try normalizeExpectationArgument()
    }

    mutating func applyPositionalArguments(_ positional: [String]) throws {
        guard !positional.isEmpty else { return }

        switch descriptor.humanPositionalSyntax {
        case .joinedText(let parameter):
            if self[parameter] == nil {
                self[parameter] = .string(positional.joined(separator: " "))
            }

        case .firstToken(let parameter):
            if self[parameter] == nil, let token = positional.first {
                self[parameter] = .string(token)
            }

        case .leadingEdgeThenTarget(let edgeValues):
            var remaining = positional
            if let first = remaining.first, edgeValues.contains(first) {
                self[.edge] = .string(first)
                remaining.removeFirst()
            }
            applyElementTarget(remaining)

        case .targetThenJoinedText(let parameter):
            if let first = positional.first {
                applyElementTarget([first])
                if positional.count > 1 {
                    self[parameter] = .string(positional.dropFirst().joined(separator: " "))
                }
            }

        case .leadingDirectionThenTarget(let directionValues):
            var remaining = positional
            if let first = remaining.first, directionValues.contains(first) {
                self[.direction] = .string(first)
                remaining.removeFirst()
            }
            applyGenericTargetOrCoordinates(remaining)

        case .target:
            applyGenericTargetOrCoordinates(positional)
        }

        try normalizeExpectationArgument()
    }

    private mutating func normalizeExpectationArgument() throws {
        guard case .string(let rawExpectation)? = self[.expect] else {
            return
        }
        do {
            self[.expect] = try TheFence.parseExpectationArgument(rawExpectation)
        } catch {
            throw FenceHumanCommandParsingError(
                "Invalid expectation '\(rawExpectation)' for \(descriptor.canonicalName): " +
                    Self.errorDescription(for: error)
            )
        }
    }

    private static func errorDescription(for error: Error) -> String {
        if let description = (error as? LocalizedError)?.errorDescription, !description.isEmpty {
            return description
        }
        let description = String(describing: error)
        return description.isEmpty ? error.localizedDescription : description
    }

    private mutating func applyGenericTargetOrCoordinates(_ tokens: [String]) {
        if tokens.count >= 2,
           let x = Double(tokens[0]),
           let y = Double(tokens[1]) {
            self[.x] = .double(x)
            self[.y] = .double(y)
        } else {
            applyElementTarget(tokens)
        }
    }

    private mutating func applyElementTarget(_ tokens: [String]) {
        guard let first = tokens.first else { return }
        self[.heistId] = .string(first)
    }
}
