import Foundation

extension HeistPlanSourceParser {
    mutating func parseAccessibilityPredicateExpr() throws -> AccessibilityPredicateExpr {
        let name = try parseDotCallName(
            allowedPrefixes: ["AccessibilityPredicate", "AccessibilityPredicateExpr"]
        )
        switch name {
        case "changed":
            try expectSymbol("(")
            let change = try parseChangePredicateExpr()
            try expectSymbol(")")
            return .changed(change)
        case "present":
            return .state(try parsePresentAbsentState(name: name))
        case "absent":
            return .state(try parsePresentAbsentState(name: name))
        case "all":
            return .state(try parseAllState())
        case "label", "identifier", "value", "element":
            return .present(try parseElementPredicateTemplate(named: name))
        default:
            throw error(previous, "unsupported accessibility predicate '.\(name)'")
        }
    }

    mutating func parseChangePredicateExpr() throws -> ChangePredicateExpr {
        let name = try parseDotCallName(allowedPrefixes: ["AccessibilityPredicate.Change", "ChangePredicateExpr"])
        switch name {
        case "screen":
            try expectSymbol("(")
            var state: StatePredicateExpr?
            if !consumeSymbol(")") {
                try expectIdentifier("where")
                try expectSymbol(":")
                state = try parseStatePredicateExpr()
                try expectSymbol(")")
            }
            return .screen(where: state)
        case "elements":
            if consumeSymbol("(") {
                try expectSymbol(")")
            }
            return .elements
        case "updated":
            try expectSymbol("(")
            let update = try parseElementUpdatePredicate()
            try expectSymbol(")")
            return .updated(update)
        default:
            throw error(previous, "unsupported change predicate '.\(name)'")
        }
    }

    mutating func parseStatePredicateExpr() throws -> StatePredicateExpr {
        let name = try parseDotCallName(
            allowedPrefixes: ["AccessibilityPredicate.State", "StatePredicateExpr"]
        )
        switch name {
        case "present", "absent":
            return try parsePresentAbsentState(name: name)
        case "all":
            return try parseAllState()
        default:
            throw error(previous, "unsupported state predicate '.\(name)'")
        }
    }

    mutating func parsePresentAbsentState(name: String) throws -> StatePredicateExpr {
        try expectSymbol("(")
        let state: StatePredicateExpr
        if let target = try parseTargetRefIfPresent() {
            state = name == "present" ? .presentTarget(target) : .absentTarget(target)
        } else if startsTargetExpression {
            let target = try parseTargetExpr()
            state = name == "present" ? .presentTarget(target) : .absentTarget(target)
        } else {
            let predicate = try parseElementPredicateTemplate()
            state = name == "present" ? .present(predicate) : .absent(predicate)
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

    mutating func parseElementUpdatePredicate() throws -> ElementUpdatePredicateExpr {
        var element: ElementPredicateTemplate?
        var property: ElementProperty?
        var from: StringExpr?
        var to: StringExpr?
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
                from = try parseStringExpr()
            } else if lookaheadLabel("to") {
                try expectIdentifier("to")
                try expectSymbol(":")
                to = try parseStringExpr()
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
