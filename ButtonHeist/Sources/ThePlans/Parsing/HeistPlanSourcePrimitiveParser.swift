import Foundation

extension HeistPlanSourceParser {
    mutating func parseTrailingTimeout(defaultValue: WaitTimeout?) throws -> WaitTimeout? {
        guard consumeSymbol(",") else { return defaultValue }
        try expectIdentifier("timeout")
        try expectSymbol(":")
        return try parseDuration()
    }

    mutating func parseDuration() throws -> WaitTimeout {
        let durationToken = currentToken
        let seconds = try parseNumber()
        do {
            return try WaitTimeout(validatingSeconds: seconds)
        } catch let validationError {
            throw error(durationToken, String(describing: validationError))
        }
    }

    mutating func parseInteger() throws -> Int {
        let token = currentToken
        guard case .number(let text) = token.kind, let value = Int(text) else {
            throw error(token, "expected an integer")
        }
        advance()
        return value
    }

    mutating func parseNumber() throws -> Double {
        guard let value = try parseNumberIfPresent() else {
            throw error(currentToken, "expected a number")
        }
        return value
    }

    mutating func parseNumberIfPresent() throws -> Double? {
        var sign = 1.0
        let signToken = currentToken
        if consumeSymbol("-") {
            sign = -1.0
        }
        guard case .number(let text) = currentToken.kind else {
            if sign < 0 {
                throw error(signToken, "expected a number after '-'")
            }
            return nil
        }
        guard let value = Double(text) else {
            throw error(currentToken, "invalid number '\(text)'")
        }
        advance()
        return sign * value
    }

    mutating func parseStringLiteral() throws -> String {
        let token = currentToken
        guard case .string(let value) = token.kind else {
            throw error(token, "expected a string literal")
        }
        advance()
        return value
    }

    mutating func parseReferenceNameLiteral(role: String) throws -> HeistReferenceName {
        let token = currentToken
        let value = try parseStringLiteral()
        do {
            return try HeistReferenceName(validating: value)
        } catch let validationError {
            throw error(token, "\(role) \(validationError)")
        }
    }

    mutating func parseEnumCase<T: RawRepresentable & CaseIterable>(
        _ type: T.Type,
        role: String
    ) throws -> T where T.RawValue == String, T.AllCases: Collection {
        guard consumeSymbol(".") else {
            let example = T.allCases.first.map { ".\($0.rawValue)" } ?? ".case"
            throw error(currentToken, "\(role) must use canonical dotted enum-case syntax like \(example)")
        }
        let token = currentToken
        let name = try parseIdentifier()
        guard let value = T(rawValue: name) else {
            throw error(token, "unknown \(role) '.\(name)'")
        }
        return value
    }

    mutating func parseDotCallName() throws -> String {
        let token = currentToken
        guard consumeSymbol(".") else {
            throw error(token, "expected a ButtonHeist expression beginning with '.'")
        }
        return try parseIdentifier()
    }

    mutating func parseCalleeName() throws -> [String] {
        let token = currentToken
        let first = try parseIdentifier()
        if first == "in" {
            throw error(token, "unexpected closure parameter separator")
        }
        var names = [first]
        while consumeSymbol(".") {
            names.append(try parseIdentifier())
        }
        return names
    }

    mutating func parseIdentifier() throws -> String {
        let token = currentToken
        guard case .identifier(let name) = token.kind else {
            throw error(token, "expected an identifier")
        }
        advance()
        return name
    }

    mutating func parseBoolLiteral() throws -> Bool {
        let token = currentToken
        let value = try parseIdentifier()
        switch value {
        case "true":
            return true
        case "false":
            return false
        default:
            throw error(token, "expected boolean literal true or false")
        }
    }

    mutating func expectIdentifier(_ expected: String) throws {
        let token = currentToken
        let actual = try parseIdentifier()
        guard actual == expected else {
            throw error(token, "expected '\(expected)'")
        }
    }

    mutating func expectSymbol(_ symbol: Character) throws {
        let token = currentToken
        guard consumeSymbol(symbol) else {
            throw error(token, "expected '\(symbol)'")
        }
    }

    mutating func expect(_ kind: HeistPlanSourceTokenKind) throws {
        let token = currentToken
        guard token.kind == kind else {
            throw error(token, "expected \(kind.description)")
        }
        advance()
    }

    @discardableResult
    mutating func consumeIdentifier(_ name: String) -> HeistPlanSourceToken? {
        guard case .identifier(name) = currentToken.kind else { return nil }
        let token = currentToken
        advance()
        return token
    }

    mutating func consumeLabel(_ name: String) -> Bool {
        guard currentToken.kind == .identifier(name), nextToken.isSymbol(":") else {
            return false
        }
        advance()
        advance()
        return true
    }

    mutating func consumeSymbol(_ symbol: Character) -> Bool {
        guard currentToken.isSymbol(symbol) else { return false }
        advance()
        return true
    }

    mutating func skipSemicolons() {
        while consumeSymbol(";") {}
    }

    var startsRootHeistPlan: Bool {
        currentToken.kind == .identifier("HeistPlan")
    }

    var startsDefinition: Bool {
        currentToken.kind == .identifier("HeistDef") || currentToken.kind == .identifier("Namespace")
    }

    var atEnd: Bool {
        currentToken.kind == .eof
    }

    var currentToken: HeistPlanSourceToken {
        tokens[index]
    }

    var nextToken: HeistPlanSourceToken {
        tokens[min(index + 1, tokens.index(before: tokens.endIndex))]
    }

    var previous: HeistPlanSourceToken {
        tokens[max(tokens.startIndex, index - 1)]
    }

    mutating func advance() {
        if index < tokens.count - 1 {
            index += 1
        }
    }

}
