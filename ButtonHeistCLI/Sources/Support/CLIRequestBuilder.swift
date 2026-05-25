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
}
