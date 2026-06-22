import Foundation

extension HeistPlanSourceParser {
    mutating func parseTrailingTimeout(defaultValue: Double?) throws -> Double? {
        guard consumeSymbol(",") else { return defaultValue }
        try expectIdentifier("timeout")
        try expectSymbol(":")
        return try parseDuration()
    }

    mutating func parseDuration() throws -> Double {
        if let number = try parseNumberIfPresent() {
            return number
        }
        if consumeSymbol(".") {
            return try parseDurationCall()
        }
        if consumeIdentifier("Double") != nil {
            try expectSymbol(".")
            return try parseDurationCall()
        }
        throw error(currentToken, "expected a timeout duration such as .seconds(1)")
    }

    mutating func parseDurationCall() throws -> Double {
        let method = try parseIdentifier()
        try expectSymbol("(")
        let value = try parseNumber()
        try expectSymbol(")")
        switch method {
        case "seconds":
            return value
        case "milliseconds":
            return value / 1_000
        default:
            throw error(previous, "unsupported duration '.\(method)'")
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

    mutating func parseEnumCase<T: RawRepresentable>(
        _ type: T.Type,
        role: String
    ) throws -> T where T.RawValue == String {
        if consumeSymbol(".") {}
        let token = currentToken
        let name = try parseIdentifier()
        guard let value = T(rawValue: name) else {
            throw error(token, "unknown \(role) '.\(name)'")
        }
        return value
    }

    mutating func parseQualifiedOrShorthandCall(
        allowedPrefixes: Set<String>,
        expectedName: String
    ) throws {
        let name = try parseDotCallName(allowedPrefixes: allowedPrefixes)
        guard name == expectedName else {
            throw error(previous, "expected .\(expectedName)(...)")
        }
    }

    mutating func parseDotCallName(allowedPrefixes: Set<String>) throws -> String {
        if consumeSymbol(".") {
            return try parseIdentifier()
        }
        let token = currentToken
        let first = try parseIdentifier()
        if consumeSymbol(".") {
            var prefix = first
            let second = try parseIdentifier()
            if consumeSymbol(".") {
                prefix += ".\(second)"
                guard allowedPrefixes.contains(prefix) else {
                    throw error(token, "unsupported ButtonHeist source type prefix '\(prefix)'")
                }
                return try parseIdentifier()
            }
            guard allowedPrefixes.contains(prefix) else {
                throw error(token, "unsupported ButtonHeist source type prefix '\(prefix)'")
            }
            return second
        }
        throw error(token, "expected a ButtonHeist expression beginning with '.'")
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

    mutating func parseTryPrefixIfPresent() throws -> HeistTryPrefix? {
        guard let token = consumeIdentifier("try") else { return nil }
        let forced = consumeSymbol("!")
        return HeistTryPrefix(token: token, forced: forced)
    }

    @discardableResult
    mutating func consumeIdentifier(_ name: String) -> HeistPlanSourceToken? {
        guard case .identifier(name) = currentToken.kind else { return nil }
        let token = currentToken
        advance()
        return token
    }

    mutating func consumeSymbol(_ symbol: Character) -> Bool {
        guard currentToken.isSymbol(symbol) else { return false }
        advance()
        return true
    }

    func nextTokenIsIdentifier(_ name: String) -> Bool {
        guard tokens.indices.contains(index + 1),
              case .identifier(name) = tokens[index + 1].kind else {
            return false
        }
        return true
    }

    func nextTokenIsSymbol(_ symbol: Character) -> Bool {
        guard tokens.indices.contains(index + 1) else { return false }
        return tokens[index + 1].isSymbol(symbol)
    }

    func tokenIsIdentifier(_ token: HeistPlanSourceToken, _ name: String) -> Bool {
        guard case .identifier(name) = token.kind else { return false }
        return true
    }

    func lookaheadIdentifier(_ offset: Int, _ name: String) -> Bool {
        guard tokens.indices.contains(index + offset),
              case .identifier(name) = tokens[index + offset].kind else {
            return false
        }
        return true
    }

    mutating func skipSemicolons() {
        while consumeSymbol(";") {}
    }

    func lookaheadLabel(_ label: String) -> Bool {
        guard case .identifier(label) = currentToken.kind else { return false }
        guard tokens.indices.contains(index + 1) else { return false }
        return tokens[index + 1].isSymbol(":")
    }

    func lookaheadIdentifier(in values: Set<String>) -> Bool {
        guard tokens.indices.contains(index + 1),
              case .identifier(let name) = tokens[index + 1].kind else {
            return false
        }
        return values.contains(name)
    }

    var startsRootHeistPlan: Bool {
        tokenIsIdentifier(currentToken, "HeistPlan")
    }

    var startsDefinition: Bool {
        tokenIsIdentifier(currentToken, "HeistDef")
    }

    var atEnd: Bool {
        currentToken.kind == .eof
    }

    var currentTokenIsIdentifier: Bool {
        if case .identifier = currentToken.kind { return true }
        return false
    }

    var currentToken: HeistPlanSourceToken {
        tokens[index]
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
