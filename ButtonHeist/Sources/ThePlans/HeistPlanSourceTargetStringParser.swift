import Foundation

extension HeistPlanSourceParser {
    mutating func parseTargetExpr() throws -> ElementTargetExpr {
        if let target = try parseTargetRefIfPresent() {
            return target
        }
        let name = try parseDotCallName(allowedPrefixes: [])
        switch name {
        case "label":
            try expectSymbol("(")
            let label = try parseStringMatchCallArgument(field: "label")
            try expectSymbol(")")
            return .predicate(ElementPredicateTemplate(label: label))
        case "identifier":
            try expectSymbol("(")
            let identifier = try parseStringMatchCallArgument(field: "identifier")
            try expectSymbol(")")
            return .predicate(ElementPredicateTemplate(identifier: identifier))
        case "value":
            try expectSymbol("(")
            let value = try parseStringMatchCallArgument(field: "value")
            try expectSymbol(")")
            return .predicate(ElementPredicateTemplate(value: value))
        case "element":
            try expectSymbol("(")
            let predicate = try parseElementPredicateTemplateFields()
            try expectSymbol(")")
            return .predicate(predicate)
        case "target":
            try expectSymbol("(")
            let predicate = try parseElementPredicateTemplate()
            try expectSymbol(",")
            try expectIdentifier("ordinal")
            try expectSymbol(":")
            let ordinal = try parseInteger()
            try expectSymbol(")")
            return .predicate(predicate, ordinal: ordinal)
        default:
            throw error(previous, "unsupported element target '.\(name)'")
        }
    }

    mutating func parseElementPredicateTemplate() throws -> ElementPredicateTemplate {
        let name = try parseDotCallName(allowedPrefixes: [])
        return try parseElementPredicateTemplate(named: name)
    }

    mutating func parseElementPredicateTemplate(named name: String) throws -> ElementPredicateTemplate {
        switch name {
        case "label":
            try expectSymbol("(")
            let label = try parseStringMatchCallArgument(field: "label")
            try expectSymbol(")")
            return ElementPredicateTemplate(label: label)
        case "identifier":
            try expectSymbol("(")
            let identifier = try parseStringMatchCallArgument(field: "identifier")
            try expectSymbol(")")
            return ElementPredicateTemplate(identifier: identifier)
        case "value":
            try expectSymbol("(")
            let value = try parseStringMatchCallArgument(field: "value")
            try expectSymbol(")")
            return ElementPredicateTemplate(value: value)
        case "element":
            try expectSymbol("(")
            let predicate = try parseElementPredicateTemplateFields()
            try expectSymbol(")")
            return predicate
        default:
            throw error(previous, "unsupported element predicate '.\(name)'")
        }
    }

    mutating func parseElementPredicate() throws -> ElementPredicate {
        let template = try parseElementPredicateTemplate()
        return try concretePredicate(from: template)
    }

    mutating func parseElementPredicateTemplateFields() throws -> ElementPredicateTemplate {
        var labelMatches: [StringMatch<StringExpr>] = []
        var identifierMatches: [StringMatch<StringExpr>] = []
        var valueMatches: [StringMatch<StringExpr>] = []
        var traits: [HeistTrait] = []
        var excludeTraits: [HeistTrait] = []
        if currentToken.isSymbol(")") {
            return ElementPredicateTemplate()
        }
        while true {
            if currentToken.isSymbol("."), lookaheadIdentifier(in: Set(["label", "identifier", "value"])) {
                switch try parseDotCallName(allowedPrefixes: []) {
                case "label":
                    try expectSymbol("(")
                    labelMatches.append(try parseStringMatchCallArgument(field: "label"))
                    try expectSymbol(")")
                case "identifier":
                    try expectSymbol("(")
                    identifierMatches.append(try parseStringMatchCallArgument(field: "identifier"))
                    try expectSymbol(")")
                case "value":
                    try expectSymbol("(")
                    valueMatches.append(try parseStringMatchCallArgument(field: "value"))
                    try expectSymbol(")")
                default:
                    throw error(previous, ".element(...) repeated checks accept .label, .identifier, and .value")
                }
            } else if consumeIdentifier("label") != nil {
                try expectSymbol(":")
                labelMatches.append(try parseStringMatchFieldValue(field: "label"))
            } else if consumeIdentifier("identifier") != nil {
                try expectSymbol(":")
                identifierMatches.append(try parseStringMatchFieldValue(field: "identifier"))
            } else if consumeIdentifier("value") != nil {
                try expectSymbol(":")
                valueMatches.append(try parseStringMatchFieldValue(field: "value"))
            } else if consumeIdentifier("traits") != nil {
                try expectSymbol(":")
                traits = try parseTraitArray(role: "traits")
            } else if consumeIdentifier("excludeTraits") != nil {
                try expectSymbol(":")
                excludeTraits = try parseTraitArray(role: "excludeTraits")
            } else {
                throw error(currentToken, ".element(...) accepts label, identifier, value, traits, and excludeTraits")
            }
            guard consumeSymbol(",") else { break }
        }
        return .element(
            labelMatches: labelMatches,
            identifierMatches: identifierMatches,
            valueMatches: valueMatches,
            traits: traits,
            excludeTraits: excludeTraits
        )
    }

    mutating func parseTraitArray(role: String) throws -> [HeistTrait] {
        try expectSymbol("[")
        var traits: [HeistTrait] = []
        if !consumeSymbol("]") {
            repeat {
                if case .string = currentToken.kind {
                    throw error(currentToken, "\(role) must use enum-style syntax like [.\(role == "traits" ? "button" : "header")], not string names")
                }
                traits.append(try parseEnumCase(HeistTrait.self, role: "accessibility trait"))
            } while consumeSymbol(",")
            try expectSymbol("]")
        }
        return traits
    }

    mutating func concretePredicate(from template: ElementPredicateTemplate) throws -> ElementPredicate {
        return ElementPredicate(
            labelMatches: try concreteStringMatches(template.labelMatches, role: "label"),
            identifierMatches: try concreteStringMatches(template.identifierMatches, role: "identifier"),
            valueMatches: try concreteStringMatches(template.valueMatches, role: "value"),
            traits: template.traits,
            excludeTraits: template.excludeTraits
        )
    }

    mutating func concreteStringMatches(
        _ matches: [StringMatch<StringExpr>],
        role: String
    ) throws -> [StringMatch<String>] {
        try matches.map { try concreteStringMatch($0, role: role) }
    }

    mutating func concreteStringMatch(
        _ match: StringMatch<StringExpr>,
        role: String
    ) throws -> StringMatch<String> {
        StringMatch<String>(
            mode: StringMatch<String>.Mode(rawValue: match.mode.rawValue) ?? .exact,
            value: try concreteString(match.value, role: role)
        )
    }

    mutating func concreteStringMatch(
        _ match: StringMatch<StringExpr>?,
        role: String
    ) throws -> StringMatch<String>? {
        guard let match else { return nil }
        return StringMatch<String>(
            mode: StringMatch<String>.Mode(rawValue: match.mode.rawValue) ?? .exact,
            value: try concreteString(match.value, role: role)
        )
    }

    func concreteString(_ string: StringExpr, role: String) throws -> String {
        switch string {
        case .literal(let value):
            return value
        case .ref:
            throw HeistPlanSourceCompilerError(
                message: "\(role) refs are not supported in this predicate position",
                sourceName: sourceName,
                offset: currentToken.marker.offset,
                line: currentToken.marker.line,
                column: currentToken.marker.column
            )
        }
    }

    mutating func parseStringMatchCallArgument(field: String) throws -> StringMatch<StringExpr> {
        if let label = stringMatchModeLabelTokenIfPresent() {
            throw error(label.token, "StringMatch modes use enum-case syntax; use `.\(field)(.\(label.name)(\"...\"))`")
        }
        if startsStringMatchDotCall {
            return try parseStringMatchDotCall(field: field)
        }
        return StringMatch(try parseStringExpr())
    }

    mutating func parseStringMatchFieldValue(field: String) throws -> StringMatch<StringExpr> {
        if let label = stringMatchModeLabelTokenIfPresent() {
            throw error(label.token, "StringMatch modes use enum-case syntax; use `\(field): .\(label.name)(\"...\")`")
        }
        if startsStringMatchDotCall {
            return try parseStringMatchDotCall(field: field)
        }
        return StringMatch(try parseStringExpr())
    }

    mutating func parseStringMatchDotCall(field: String) throws -> StringMatch<StringExpr> {
        let token = currentToken
        let name = try parseDotCallName(allowedPrefixes: [])
        guard let mode = stringMatchMode(named: name) else {
            throw error(token, "unsupported string match '.\(name)'")
        }
        try expectSymbol("(")
        let value = try parseStringExpr()
        try expectSymbol(")")
        return try validatedStringMatch(mode, value: value, field: field, token: token)
    }

    func stringMatchModeLabelTokenIfPresent() -> (name: String, token: HeistPlanSourceToken)? {
        for name in stringMatchModeNames where lookaheadLabel(name) {
            return (name, currentToken)
        }
        return nil
    }

    var startsStringMatchDotCall: Bool {
        if currentToken.isSymbol(".") {
            return lookaheadIdentifier(in: stringMatchModeNames)
        }
        return false
    }

    var stringMatchModeNames: Set<String> {
        Set(StringMatch<StringExpr>.Mode.allCases.map(\.rawValue))
    }

    func stringMatchMode(named name: String) -> StringMatch<StringExpr>.Mode? {
        StringMatch<StringExpr>.Mode(rawValue: name)
    }

    func validatedStringMatch(
        _ mode: StringMatch<StringExpr>.Mode,
        value: StringExpr,
        field: String,
        token: HeistPlanSourceToken
    ) throws -> StringMatch<StringExpr> {
        let match = StringMatch(mode: mode, value: value)
        if match.hasInvalidEmptyBroadLiteral {
            throw error(token, "\(field) \(mode.rawValue) match value must not be empty")
        }
        return match
    }

    mutating func parseStringExpr() throws -> StringExpr {
        if let string = try parseStringExprIfPresent() {
            return string
        }
        if currentTokenIsIdentifier, nextTokenIsSymbol("(") {
            throw error(
                currentToken,
                "arbitrary calls are not supported inside ButtonHeist DSL bodies; wrap the heist in Swift and pass values through parameters or RunHeist"
            )
        }
        throw error(currentToken, "expected a string literal or scoped string reference")
    }

    mutating func parseStringExprIfPresent() throws -> StringExpr? {
        if case .string(let value) = currentToken.kind {
            advance()
            return .literal(value)
        }
        if case .identifier(let name) = currentToken.kind, let reference = scope.stringReference(for: name) {
            advance()
            return .ref(reference)
        }
        return nil
    }

    mutating func parseTargetRefIfPresent() throws -> ElementTargetExpr? {
        if case .identifier(let name) = currentToken.kind, let reference = scope.targetReference(for: name) {
            advance()
            return .ref(reference)
        }
        return nil
    }

    var startsTargetExpression: Bool {
        if case .identifier(let name) = currentToken.kind, scope.targetReference(for: name) != nil {
            return true
        }
        if currentToken.isSymbol(".") {
            return lookaheadIdentifier(in: ["target"])
        }
        return false
    }

}
