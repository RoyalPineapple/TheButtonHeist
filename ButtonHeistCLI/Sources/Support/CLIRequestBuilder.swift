import ArgumentParser
import ButtonHeist
import Foundation

enum CLIRequestInputMode: Equatable {
    case human
    case machine
}

struct CLIParsedRequest {
    let request: [String: Any]
    let requestId: PublicRequestId?
    let descriptor: FenceCommandDescriptor?
    let mode: CLIRequestInputMode

    var command: TheFence.Command? {
        descriptor?.command
    }
}

enum CLIRequestBuilder {

    static func request(
        command: TheFence.Command,
        parameters: CLIRequestParameters = [:]
    ) -> [String: Any] {
        var request = FenceParameterKey.rawDictionary(parameters)
        request[.command] = command.descriptor.canonicalName
        return request
    }

    static func parsedRequest(from line: String, acceptsHumanInput: Bool = true) throws -> CLIParsedRequest {
        if line.hasPrefix("{") {
            return try parseMachineRequest(line)
        }

        guard acceptsHumanInput else {
            throw ValidationError("Expected JSON object input for JSON session mode")
        }
        return try parseHumanTokens(tokenize(line))
    }

    static func parseHumanInput(_ line: String) throws -> [String: Any] {
        try parseHumanTokens(tokenize(line)).request
    }

    static func parseHumanTokens(_ tokens: [String]) throws -> CLIParsedRequest {
        guard let first = tokens.first else {
            throw ValidationError("Unknown command. Type 'help' for available commands.")
        }

        let fenceRequest = try FenceCommandDescriptor.humanRequest(
            commandName: first,
            arguments: Array(tokens.dropFirst())
        )

        return CLIParsedRequest(
            request: request(command: fenceRequest.command, parameters: fenceRequest.parameters),
            requestId: nil,
            descriptor: fenceRequest.descriptor,
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
              case .string(_)? = object[FenceParameterKey.command.rawValue] else {
            throw ValidationError("Expected JSON object with string field 'command'")
        }
        let descriptor = try validateCanonicalCommandObject(object, context: "JSON input")
        let requestId = try object["id"].map(PublicRequestId.init(value:))
        return CLIParsedRequest(
            request: object.mapValues(\.cliRawValue),
            requestId: requestId,
            descriptor: descriptor,
            mode: .machine
        )
    }

    @discardableResult
    static func validateCanonicalCommandObject(
        _ object: [String: HeistValue],
        context: String,
        requireBatchExecutable: Bool = false
    ) throws -> FenceCommandDescriptor {
        guard case .string(let commandName)? = object[FenceParameterKey.command.rawValue] else {
            throw ValidationError("\(context) must include string field 'command'")
        }
        guard let descriptor = FenceCommandDescriptor.descriptor(canonicalName: commandName) else {
            throw ValidationError("Unknown command '\(commandName)'. \(context) requires a canonical command name.")
        }
        if requireBatchExecutable, !descriptor.isBatchExecutable {
            throw ValidationError("\(context) command '\(commandName)' is not supported in run_batch")
        }

        let allowedKeys = Set([FenceParameterKey.command.rawValue, "id"] + descriptor.parameters.map(\.key))
        let unsupportedKeys = object.keys.filter { !allowedKeys.contains($0) }.sorted()
        if let unsupportedKey = unsupportedKeys.first {
            throw ValidationError("Unknown parameter '\(unsupportedKey)' for \(commandName)")
        }

        return descriptor
    }

    static func diagnosticMessage(for error: Error) -> String {
        let description = String(describing: error)
        return description.isEmpty ? error.localizedDescription : description
    }
}
