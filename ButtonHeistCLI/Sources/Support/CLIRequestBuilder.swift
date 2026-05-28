import ArgumentParser
import ButtonHeist
import Foundation

enum CLIRequestInputMode: Equatable {
    case human
    case machine
}

struct CLIParsedRequest {
    let operation: NormalizedOperation
    let requestId: PublicRequestId?
    let descriptor: FenceCommandDescriptor?
    let mode: CLIRequestInputMode

    var command: TheFence.Command? {
        descriptor?.command
    }
}

struct CLIRequestBuildError: Error, CustomStringConvertible {
    let message: String
    let requestId: PublicRequestId?

    var description: String { message }
}

enum CLIRequestBuilder {

    static func operation(
        command: TheFence.Command,
        parameters: CLIRequestParameters = [:]
    ) throws -> NormalizedOperation {
        let arguments = TheFence.CommandArgumentEnvelope(
            values: Dictionary(
                parameters.map { ($0.key.rawValue, $0.value) },
                uniquingKeysWith: { _, newest in newest }
            )
        )
        switch FenceOperationCatalog.normalizeCommand(command, arguments: arguments) {
        case .success(let operation):
            return operation
        case .failure(let error):
            throw ValidationError(error.message)
        }
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

    static func parseHumanTokens(_ tokens: [String]) throws -> CLIParsedRequest {
        guard let first = tokens.first else {
            throw ValidationError("Unknown command. Type 'help' for available commands.")
        }

        let fenceRequest = try FenceCommandDescriptor.humanRequest(
            commandName: first,
            arguments: Array(tokens.dropFirst())
        )

        return CLIParsedRequest(
            operation: try operation(command: fenceRequest.command, parameters: fenceRequest.parameters),
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
        let requestId = try CLIMachineRequestIdScanner.requestId(in: line)
        let data = Data(line.utf8)
        let envelope: CLIMachineRequestEnvelope
        do {
            envelope = try JSONDecoder().decode(CLIMachineRequestEnvelope.self, from: data)
        } catch let error as DecodingError {
            throw ValidationError(diagnosticMessage(for: error))
        }
        do {
            let operation: NormalizedOperation
            switch FenceOperationCatalog.normalizeCommandObject(envelope.arguments, context: "JSON input") {
            case .success(let normalizedOperation):
                operation = normalizedOperation
            case .failure(let error):
                throw ValidationError(error.message)
            }
            return CLIParsedRequest(
                operation: operation,
                requestId: requestId,
                descriptor: operation.command.descriptor,
                mode: .machine
            )
        } catch let error as CLIRequestBuildError {
            throw error
        } catch {
            throw CLIRequestBuildError(
                message: diagnosticMessage(for: error),
                requestId: requestId
            )
        }
    }

    static func diagnosticMessage(for error: Error) -> String {
        let description = String(describing: error)
        return description.isEmpty ? error.localizedDescription : description
    }
}

private struct CLIMachineRequestEnvelope: Decodable {
    let arguments: TheFence.CommandArgumentObject

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var values: [String: HeistValue] = [:]
        for key in container.allKeys {
            if key.stringValue == "id" {
                continue
            } else {
                values[key.stringValue] = try container.decode(HeistValue.self, forKey: key)
            }
        }
        arguments = TheFence.CommandArgumentObject(values: values, fieldPrefix: nil)
    }
}

private enum CLIMachineRequestIdScanner {
    static func requestId(in line: String) throws -> PublicRequestId? {
        var parser = Parser(line)
        try parser.skipWhitespace()
        guard parser.consume("{") else { return nil }
        try parser.skipWhitespace()
        guard !parser.consume("}") else { return nil }
        while true {
            let key = try parser.readString()
            try parser.skipWhitespace()
            try parser.expect(":")
            try parser.skipWhitespace()
            if key == "id" {
                return try parser.readRequestId()
            }
            try parser.skipValue()
            try parser.skipWhitespace()
            if parser.consume(",") {
                try parser.skipWhitespace()
                continue
            }
            return nil
        }
    }

    private struct Parser {
        var index: String.Index
        let line: String

        init(_ line: String) {
            self.line = line
            self.index = line.startIndex
        }

        mutating func skipWhitespace() throws {
            while let character = current, character == " " || character == "\n" || character == "\r" || character == "\t" {
                advance()
            }
        }

        mutating func consume(_ character: Character) -> Bool {
            guard current == character else { return false }
            advance()
            return true
        }

        mutating func expect(_ character: Character) throws {
            guard consume(character) else {
                throw ValidationError("Invalid JSON request id metadata")
            }
        }

        mutating func readRequestId() throws -> PublicRequestId {
            if consumeLiteral("null") {
                return .null
            }
            if consumeLiteral("true") || consumeLiteral("false") {
                throw ValidationError("Public JSON request id does not support bool")
            }
            if current == "\"" {
                return try .string(readString())
            }
            guard current != "{" && current != "[" else {
                throw ValidationError("Public JSON request id must be string, integer, unsigned integer, finite decimal, or null")
            }
            return try readNumberRequestId()
        }

        mutating func readNumberRequestId() throws -> PublicRequestId {
            let token = readNumberToken()
            guard !token.isEmpty else {
                throw ValidationError("Public JSON request id must be string, integer, unsigned integer, finite decimal, or null")
            }
            if token.contains(".") || token.contains("e") || token.contains("E") {
                guard let value = Double(token), value.isFinite else {
                    throw ValidationError("Public JSON request id must be finite")
                }
                return .double(value)
            }
            if token.hasPrefix("-") {
                guard let value = Int64(token) else {
                    throw ValidationError("Public JSON request id integer is outside Int64 range")
                }
                return .signedInteger(value)
            }
            if let value = Int64(token) {
                return .signedInteger(value)
            }
            guard let value = UInt64(token) else {
                throw ValidationError("Public JSON request id integer is outside UInt64 range")
            }
            return .unsignedInteger(value)
        }

        mutating func skipValue() throws {
            try skipWhitespace()
            if current == "\"" {
                _ = try readStringToken()
            } else if consume("{") {
                try skipObjectBody()
            } else if consume("[") {
                try skipArrayBody()
            } else if consumeLiteral("true") || consumeLiteral("false") || consumeLiteral("null") {
                return
            } else {
                _ = readNumberToken()
            }
        }

        mutating func skipObjectBody() throws {
            try skipWhitespace()
            guard !consume("}") else { return }
            while true {
                _ = try readString()
                try skipWhitespace()
                try expect(":")
                try skipValue()
                try skipWhitespace()
                if consume("}") { return }
                try expect(",")
                try skipWhitespace()
            }
        }

        mutating func skipArrayBody() throws {
            try skipWhitespace()
            guard !consume("]") else { return }
            while true {
                try skipValue()
                try skipWhitespace()
                if consume("]") { return }
                try expect(",")
                try skipWhitespace()
            }
        }

        mutating func readString() throws -> String {
            let token = try readStringToken()
            do {
                return try JSONDecoder().decode(String.self, from: Data(token.utf8))
            } catch {
                throw ValidationError("Invalid JSON string in request metadata")
            }
        }

        mutating func readStringToken() throws -> Substring {
            guard consume("\"") else {
                throw ValidationError("Invalid JSON request id metadata")
            }
            let start = line.index(before: index)
            var isEscaped = false
            while current != nil {
                let character = current
                advance()
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    return line[start..<index]
                }
            }
            throw ValidationError("Unterminated JSON string in request metadata")
        }

        mutating func readNumberToken() -> String {
            let start = index
            while let character = current,
                  character == "-" || character == "+" || character == "." || character == "e" || character == "E" || character.isNumber {
                advance()
            }
            return String(line[start..<index])
        }

        mutating func consumeLiteral(_ literal: String) -> Bool {
            guard line[index...].hasPrefix(literal) else { return false }
            index = line.index(index, offsetBy: literal.count)
            return true
        }

        var current: Character? {
            index < line.endIndex ? line[index] : nil
        }

        mutating func advance() {
            index = line.index(after: index)
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
