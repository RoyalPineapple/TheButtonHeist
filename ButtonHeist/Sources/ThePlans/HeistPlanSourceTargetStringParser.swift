import Foundation

extension HeistPlanSourceParser {
    mutating func parseTargetExpr() throws -> ElementTargetExpr {
        if let target = try parseTargetRefIfPresent() {
            return target
        }
        let name = try parseDotCallName(allowedPrefixes: ["ElementTarget", "ElementTargetExpr"])
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
        let name = try parseDotCallName(allowedPrefixes: [
            "ElementPredicate",
            "ElementPredicateTemplate",
            "ElementTarget",
            "ElementTargetExpr",
        ])
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
        var label: StringMatch<StringExpr>?
        var identifier: StringMatch<StringExpr>?
        var value: StringMatch<StringExpr>?
        var traits: [HeistTrait] = []
        var excludeTraits: [HeistTrait] = []
        if currentToken.isSymbol(")") {
            return .element()
        }
        while true {
            if consumeIdentifier("label") != nil {
                try expectSymbol(":")
                label = try parseStringMatchFieldValue(field: "label")
            } else if consumeIdentifier("identifier") != nil {
                try expectSymbol(":")
                identifier = try parseStringMatchFieldValue(field: "identifier")
            } else if consumeIdentifier("value") != nil {
                try expectSymbol(":")
                value = try parseStringMatchFieldValue(field: "value")
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
            label: label,
            identifier: identifier,
            value: value,
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
        let label = try concreteStringMatch(template.label, role: "label")
        let identifier = try concreteStringMatch(template.identifier, role: "identifier")
        let value = try concreteStringMatch(template.value, role: "value")
        return ElementPredicate(
            label: label,
            identifier: identifier,
            value: value,
            traits: template.traits,
            excludeTraits: template.excludeTraits
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
        if let mode = try parseStringMatchModeLabelIfPresent() {
            let value = try parseStringExpr()
            return try validatedStringMatch(mode.mode, value: value, field: field, token: mode.token)
        }
        return .exact(try parseStringExpr())
    }

    mutating func parseStringMatchFieldValue(field: String) throws -> StringMatch<StringExpr> {
        if startsStringMatchDotCall {
            let token = currentToken
            let name = try parseDotCallName(allowedPrefixes: ["StringMatch"])
            guard let mode = stringMatchMode(named: name) else {
                throw error(token, "unsupported string match '.\(name)'")
            }
            try expectSymbol("(")
            let value = try parseStringExpr()
            try expectSymbol(")")
            return try validatedStringMatch(mode, value: value, field: field, token: token)
        }
        return .exact(try parseStringExpr())
    }

    mutating func parseStringMatchModeLabelIfPresent() throws -> (mode: StringMatch<StringExpr>.Mode, token: HeistPlanSourceToken)? {
        for name in ["exact", "contains", "prefix", "suffix"] where lookaheadLabel(name) {
            let token = currentToken
            try expectIdentifier(name)
            try expectSymbol(":")
            guard let mode = stringMatchMode(named: name) else { return nil }
            return (mode, token)
        }
        return nil
    }

    var startsStringMatchDotCall: Bool {
        if currentToken.isSymbol(".") {
            return lookaheadIdentifier(in: ["exact", "contains", "prefix", "suffix"])
        }
        if case .identifier(let name) = currentToken.kind {
            return name == "StringMatch"
        }
        return false
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
        if case .identifier(let name) = currentToken.kind {
            return ["ElementTarget", "ElementTargetExpr"].contains(name)
        }
        return false
    }

}
