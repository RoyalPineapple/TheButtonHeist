import Foundation

extension HeistPlanSourceParser {
    mutating func parseAccessibilityPredicateExpr() throws -> AccessibilityPredicateExpr {
        let name = try parseDotCallName(allowedPrefixes: [])
        switch name {
        case "change":
            try expectSymbol("(")
            var changes: [ChangePredicateExpr] = []
            if !consumeSymbol(")") {
                repeat {
                    changes.append(try parseChangePredicateExpr())
                } while consumeSymbol(",")
                try expectSymbol(")")
            }
            return .changePredicate(changes.isEmpty ? .any : (changes.count == 1 ? changes[0] : .allScopes(changes)))
        case "noChange":
            return .noChangePredicate
        case "exists":
            return .state(try parseExistsMissingState(name: name))
        case "missing":
            return .state(try parseExistsMissingState(name: name))
        case "all":
            return .state(try parseAllState())
        case "label", "identifier", "value", "element":
            return .exists(try parseElementPredicateTemplate(named: name))
        default:
            throw error(previous, "unsupported accessibility predicate '.\(name)'")
        }
    }

    mutating func parseChangePredicateExpr() throws -> ChangePredicateExpr {
        let name = try parseDotCallName(allowedPrefixes: [])
        switch name {
        case "screen":
            try expectSymbol("(")
            var assertions: [StatePredicateExpr] = []
            if !consumeSymbol(")") {
                repeat {
                    assertions.append(try parseStatePredicateExpr())
                } while consumeSymbol(",")
                try expectSymbol(")")
            }
            return .screenScope(assertions)
        case "elements":
            try expectSymbol("(")
            var assertions: [ElementDeltaPredicateExpr] = []
            if !consumeSymbol(")") {
                repeat {
                    assertions.append(try parseElementDeltaPredicateExpr())
                } while consumeSymbol(",")
                try expectSymbol(")")
            }
            return .elementsScope(assertions)
        default:
            throw error(previous, "unsupported change predicate '.\(name)'")
        }
    }

    mutating func parseStatePredicateExpr() throws -> StatePredicateExpr {
        let name = try parseDotCallName(allowedPrefixes: [])
        switch name {
        case "exists", "missing":
            return try parseExistsMissingState(name: name)
        case "all":
            return try parseAllState()
        case "label", "identifier", "value", "element":
            return .exists(try parseElementPredicateTemplate(named: name))
        default:
            throw error(previous, "unsupported state predicate '.\(name)'")
        }
    }

    mutating func parseExistsMissingState(name: String) throws -> StatePredicateExpr {
        try expectSymbol("(")
        let state: StatePredicateExpr
        if let target = try parseTargetRefIfPresent() {
            state = name == "exists" ? .existsTarget(target) : .missingTarget(target)
        } else if startsTargetExpression {
            let target = try parseTargetExpr()
            state = name == "exists" ? .existsTarget(target) : .missingTarget(target)
        } else {
            let predicate = try parseElementPredicateTemplate()
            state = name == "exists" ? .exists(predicate) : .missing(predicate)
        }
        try expectSymbol(")")
        return state
    }

    mutating func parseAllState() throws -> StatePredicateExpr {
        try expectSymbol("(")
        try expectSymbol("[")
        var states: [StatePredicateExpr] = []
        if !consumeSymbol("]") {
            repeat {
                states.append(try parseStatePredicateExpr())
            } while consumeSymbol(",")
            try expectSymbol("]")
        }
        try expectSymbol(")")
        return .all(states)
    }

    mutating func parseElementDeltaPredicateExpr() throws -> ElementDeltaPredicateExpr {
        let name = try parseDotCallName(allowedPrefixes: [])
        switch name {
        case "appeared":
            try expectSymbol("(")
            let predicate = try parseElementPredicateTemplate()
            try expectSymbol(")")
            return .appearedElement(predicate)
        case "disappeared":
            try expectSymbol("(")
            let predicate = try parseElementPredicateTemplate()
            try expectSymbol(")")
            return .disappearedElement(predicate)
        case "updated":
            try expectSymbol("(")
            let update = try parseElementUpdatePredicate()
            try expectSymbol(")")
            return .updatedElement(update)
        default:
            throw error(previous, "unsupported element delta predicate '.\(name)'")
        }
    }

    mutating func parseElementUpdatePredicate() throws -> ElementUpdatePredicateExpr {
        var element: ElementPredicateTemplate?
        var property: ElementProperty?
        var from: StringMatch<StringExpr>?
        var to: StringMatch<StringExpr>?
        if currentToken.isSymbol(")") {
            return ElementUpdatePredicateExpr()
        }
        while true {
            if lookaheadLabel("property") {
                try expectIdentifier("property")
                try expectSymbol(":")
                property = try parseEnumCase(ElementProperty.self, role: "element property")
            } else if lookaheadLabel("from") {
                try expectIdentifier("from")
                try expectSymbol(":")
                from = try parseStringMatchFieldValue(field: "from")
            } else if lookaheadLabel("to") {
                try expectIdentifier("to")
                try expectSymbol(":")
                to = try parseStringMatchFieldValue(field: "to")
            } else if element == nil {
                element = try parseElementPredicateTemplate()
            } else {
                throw error(currentToken, "unsupported element update predicate argument")
            }
            guard consumeSymbol(",") else { break }
        }
        return ElementUpdatePredicateExpr(element: element, property: property, from: from, to: to)
    }
}
