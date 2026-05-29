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
        parameters: CLIRequestParameters = [:],
        target: ElementTarget? = nil
    ) throws -> NormalizedOperation {
        var values = Dictionary(
            parameters.map { ($0.key.rawValue, $0.value) },
            uniquingKeysWith: { _, newest in newest }
        )
        if let target {
            values[FenceParameterKey.target.rawValue] = target.fenceArgumentValue
        }
        let arguments = TheFence.CommandArgumentEnvelope(values: values)
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
        let envelope: CLIMachineRequestEnvelope
        do {
            envelope = try CLIMachineRequestEnvelope.decode(from: line)
        } catch let error as CLIRequestBuildError {
            throw error
        } catch let error as DecodingError {
            throw ValidationError(diagnosticMessage(for: error))
        }
        let requestId = envelope.requestId
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

private extension ElementTarget {
    var fenceArgumentValue: HeistValue {
        switch self {
        case .heistId(let heistId):
            return .object([FenceParameterKey.heistId.rawValue: .string(heistId)])
        case .matcher(let matcher, let ordinal):
            var targetValue: [String: HeistValue] = [:]
            if let label = matcher.label { targetValue[FenceParameterKey.label.rawValue] = .string(label) }
            if let identifier = matcher.identifier { targetValue[FenceParameterKey.identifier.rawValue] = .string(identifier) }
            if let value = matcher.value { targetValue[FenceParameterKey.value.rawValue] = .string(value) }
            if let traits = matcher.traits {
                targetValue[FenceParameterKey.traits.rawValue] = .array(traits.map { .string($0.rawValue) })
            }
            if let excludeTraits = matcher.excludeTraits {
                targetValue[FenceParameterKey.excludeTraits.rawValue] = .array(excludeTraits.map { .string($0.rawValue) })
            }
            if let ordinal {
                targetValue[FenceParameterKey.ordinal.rawValue] = .int(ordinal)
            }
            return .object(targetValue)
        }
    }
}

private struct CLIMachineRequestEnvelope {
    let requestId: PublicRequestId?
    let arguments: TheFence.CommandArgumentObject

    static func decode(from line: String) throws -> Self {
        let requestId = try CLIMachineRequestIdBoundary.requestId(in: line)
        do {
            let decoded = try JSONDecoder().decode(CLIMachineRequestArguments.self, from: Data(line.utf8))
            return Self(requestId: requestId, arguments: decoded.arguments)
        } catch let error as CLIRequestBuildError {
            throw error
        } catch let error as DecodingError {
            throw CLIRequestBuildError(
                message: CLIRequestBuilder.diagnosticMessage(for: error),
                requestId: requestId
            )
        }
    }
}

private struct CLIMachineRequestArguments: Decodable {
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

private enum CLIMachineRequestIdBoundary {
    static func requestId(in line: String) throws -> PublicRequestId? {
        var reader = JSONTopLevelObjectReader(line)
        guard let lexeme = try reader.valueLexeme(forKey: "id") else {
            return nil
        }
        return try PublicRequestId(machineMetadataLexeme: lexeme)
    }
}

private extension PublicRequestId {
    init(machineMetadataLexeme lexeme: Substring) throws {
        if lexeme == "null" {
            self = .null
        } else if lexeme == "true" || lexeme == "false" {
            throw ValidationError("Public JSON request id does not support bool")
        } else if lexeme.first == "\"" {
            do {
                self = try .string(JSONDecoder().decode(String.self, from: Data(lexeme.utf8)))
            } catch {
                throw ValidationError("Invalid JSON string in request id metadata")
            }
        } else if lexeme.first == "{" || lexeme.first == "[" {
            throw ValidationError("Public JSON request id must be string, integer, unsigned integer, finite decimal, or null")
        } else {
            self = try Self(numberLexeme: String(lexeme))
        }
    }

    private init(numberLexeme token: String) throws {
        guard !token.isEmpty else {
            throw ValidationError("Public JSON request id must be string, integer, unsigned integer, finite decimal, or null")
        }
        if token.contains(".") || token.contains("e") || token.contains("E") {
            guard let value = Double(token), value.isFinite else {
                throw ValidationError("Public JSON request id must be finite")
            }
            self = .double(value)
        } else if token.hasPrefix("-") {
            guard let value = Int64(token) else {
                throw ValidationError("Public JSON request id integer is outside Int64 range")
            }
            self = .signedInteger(value)
        } else if let value = Int64(token) {
            self = .signedInteger(value)
        } else if let value = UInt64(token) {
            self = .unsignedInteger(value)
        } else {
            throw ValidationError("Public JSON request id integer is outside UInt64 range")
        }
    }
}

private struct JSONTopLevelObjectReader {
    private var index: String.Index
    private let source: String

    init(_ source: String) {
        self.source = source
        self.index = source.startIndex
    }

    mutating func valueLexeme(forKey expectedKey: String) throws -> Substring? {
        skipWhitespace()
        guard consume("{") else { return nil }
        skipWhitespace()
        guard !consume("}") else { return nil }
        while true {
            let key = try readString()
            skipWhitespace()
            try expect(":")
            skipWhitespace()
            let valueStart = index
            try skipValue()
            let value = source[valueStart..<index]
            if key == expectedKey {
                return value
            }
            skipWhitespace()
            if consume(",") {
                skipWhitespace()
                continue
            }
            return nil
        }
    }

    private mutating func skipWhitespace() {
        while let character = current, character == " " || character == "\n" || character == "\r" || character == "\t" {
            advance()
        }
    }

    private mutating func consume(_ character: Character) -> Bool {
        guard current == character else { return false }
        advance()
        return true
    }

    private mutating func expect(_ character: Character) throws {
        guard consume(character) else {
            throw ValidationError("Invalid JSON request metadata")
        }
    }

    private mutating func skipValue() throws {
        skipWhitespace()
        if current == "\"" {
            _ = try readStringToken()
        } else if current == "{" || current == "[" {
            try skipCompositeValue()
        } else if consumeLiteral("true") || consumeLiteral("false") || consumeLiteral("null") {
            return
        } else {
            try skipNumber()
        }
    }

    private mutating func readString() throws -> String {
        let token = try readStringToken()
        do {
            return try JSONDecoder().decode(String.self, from: Data(token.utf8))
        } catch {
            throw ValidationError("Invalid JSON string in request metadata")
        }
    }

    private mutating func readStringToken() throws -> Substring {
        guard consume("\"") else {
            throw ValidationError("Invalid JSON request metadata")
        }
        let start = source.index(before: index)
        var isEscaped = false
        while current != nil {
            let character = current
            advance()
            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                return source[start..<index]
            }
        }
        throw ValidationError("Unterminated JSON string in request metadata")
    }

    private mutating func skipCompositeValue() throws {
        let start = current
        let firstCloser: Character = start == "{" ? "}" : "]"
        var closers = [firstCloser]
        advance()
        var isEscaped = false
        var isInsideString = false
        while let character = current {
            advance()
            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = isInsideString
            } else if character == "\"" {
                isInsideString.toggle()
            } else if !isInsideString, character == "{" {
                closers.append("}")
            } else if !isInsideString, character == "[" {
                closers.append("]")
            } else if !isInsideString, character == closers.last {
                closers.removeLast()
                if closers.isEmpty { return }
            }
        }
        throw ValidationError("Unterminated JSON request metadata")
    }

    private mutating func skipNumber() throws {
        let start = index
        while let character = current,
              character == "-" || character == "+" || character == "." || character == "e" || character == "E" || character.isNumber {
            advance()
        }
        guard start != index else {
            throw ValidationError("Invalid JSON request metadata")
        }
    }

    private mutating func consumeLiteral(_ literal: String) -> Bool {
        guard source[index...].hasPrefix(literal) else { return false }
        index = source.index(index, offsetBy: literal.count)
        return true
    }

    private var current: Character? {
        index < source.endIndex ? source[index] : nil
    }

    private mutating func advance() {
        index = source.index(after: index)
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
