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
        case "label", "identifier", "value", "traits", "excludeTraits", "element":
            return .exists(try parseElementPredicateTemplate(named: name))
        case "appeared":
            return .changePredicate(.elementsScope([try parseAppearedElementDeltaPredicateExpr()]))
        case "disappeared":
            return .changePredicate(.elementsScope([try parseDisappearedElementDeltaPredicateExpr()]))
        case "updated":
            return .changePredicate(.elementsScope([try parseUpdatedElementDeltaPredicateExpr()]))
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
        case "appeared":
            return .elementsScope([try parseAppearedElementDeltaPredicateExpr()])
        case "disappeared":
            return .elementsScope([try parseDisappearedElementDeltaPredicateExpr()])
        case "updated":
            return .elementsScope([try parseUpdatedElementDeltaPredicateExpr()])
        default:
            throw error(previous, "unsupported change predicate '.\(name)'. Valid: screen, elements, appeared, disappeared, updated")
        }
    }

    mutating func parseStatePredicateExpr() throws -> StatePredicateExpr {
        let name = try parseDotCallName(allowedPrefixes: [])
        switch name {
        case "exists", "missing":
            return try parseExistsMissingState(name: name)
        case "all":
            return try parseAllState()
        case "label", "identifier", "value", "traits", "excludeTraits", "element":
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
        var states: [StatePredicateExpr] = [try parseStatePredicateExpr()]
        while consumeSymbol(",") {
            states.append(try parseStatePredicateExpr())
        }
        try expectSymbol(")")
        return .all(states)
    }

    mutating func parseElementDeltaPredicateExpr() throws -> ElementDeltaPredicateExpr {
        let name = try parseDotCallName(allowedPrefixes: [])
        switch name {
        case "appeared":
            return try parseAppearedElementDeltaPredicateExpr()
        case "disappeared":
            return try parseDisappearedElementDeltaPredicateExpr()
        case "updated":
            return try parseUpdatedElementDeltaPredicateExpr()
        default:
            throw error(previous, "unsupported element delta predicate '.\(name)'")
        }
    }

    mutating func parseAppearedElementDeltaPredicateExpr() throws -> ElementDeltaPredicateExpr {
        try expectSymbol("(")
        let predicate = try parseElementPredicateTemplate()
        try expectSymbol(")")
        return .appearedElement(predicate)
    }

    mutating func parseDisappearedElementDeltaPredicateExpr() throws -> ElementDeltaPredicateExpr {
        try expectSymbol("(")
        let predicate = try parseElementPredicateTemplate()
        try expectSymbol(")")
        return .disappearedElement(predicate)
    }

    mutating func parseUpdatedElementDeltaPredicateExpr() throws -> ElementDeltaPredicateExpr {
        try expectSymbol("(")
        let update = try parseElementUpdatePredicate()
        try expectSymbol(")")
        return .updatedElement(update)
    }

    mutating func parseElementUpdatePredicate() throws -> ElementUpdatePredicateExpr {
        var element: ElementPredicateTemplate?
        var change: AnyPropertyChangeExpr?
        if currentToken.isSymbol(")") {
            return ElementUpdatePredicateExpr()
        }
        while true {
            if lookaheadLabel("element") {
                try expectIdentifier("element")
                try expectSymbol(":")
                guard element == nil else {
                    throw error(previous, "element update predicate accepts element only once")
                }
                element = try parseElementPredicateTemplate()
            } else if currentToken.isSymbol(".") {
                guard change == nil else {
                    throw error(previous, "element update predicate accepts one property change")
                }
                change = try parsePropertyChangeExpr()
            } else {
                let message = """
                element update predicate accepts element: and one property change: \
                value, traits, hint, actions, frame, activationPoint, customContent, rotors
                """
                throw error(currentToken, message)
            }
            guard consumeSymbol(",") else { break }
        }
        return ElementUpdatePredicateExpr(element: element, change: change)
    }

    mutating func parsePropertyChangeExpr() throws -> AnyPropertyChangeExpr {
        let name = try parseDotCallName(allowedPrefixes: [])
        try expectSymbol("(")
        let change: AnyPropertyChangeExpr
        switch name {
        case "value":
            let fields = try parseStringPropertyChangeFields(property: "value", allowsUnlabeledAfter: true)
            change = .value(before: fields.before, after: fields.after)
        case "hint":
            let fields = try parseStringPropertyChangeFields(property: "hint")
            change = .hint(before: fields.before, after: fields.after)
        case "actions":
            let fields = try parseStringPropertyChangeFields(property: "actions")
            change = .actions(before: fields.before, after: fields.after)
        case "frame":
            let fields = try parseStringPropertyChangeFields(property: "frame")
            change = .frame(before: fields.before, after: fields.after)
        case "activationPoint":
            let fields = try parseStringPropertyChangeFields(property: "activationPoint")
            change = .activationPoint(before: fields.before, after: fields.after)
        case "customContent":
            let fields = try parseStringPropertyChangeFields(property: "customContent")
            change = .customContent(before: fields.before, after: fields.after)
        case "rotors":
            let fields = try parseStringPropertyChangeFields(property: "rotors")
            change = .rotors(before: fields.before, after: fields.after)
        case "traits":
            let fields = try parseTraitsPropertyChangeFields()
            change = .traits(before: fields.before, after: fields.after)
        default:
            throw error(previous, "unsupported element update property '.\(name)'. Valid: \(Self.validElementProperties)")
        }
        try expectSymbol(")")
        return change
    }

    mutating func parseStringPropertyChangeFields(
        property: String,
        allowsUnlabeledAfter: Bool = false
    ) throws -> (before: StringMatch<StringExpr>?, after: StringMatch<StringExpr>?) {
        var before: StringMatch<StringExpr>?
        var after: StringMatch<StringExpr>?
        if currentToken.isSymbol(")") {
            return (nil, nil)
        }
        if allowsUnlabeledAfter && !lookaheadLabel("before") && !lookaheadLabel("after") {
            return (nil, try parseStringMatchCallArgument(field: "\(property) after"))
        }
        while true {
            if lookaheadLabel("before") {
                try expectIdentifier("before")
                try expectSymbol(":")
                guard before == nil else {
                    throw error(previous, "\(property) update predicate accepts before only once")
                }
                before = try parseStringMatchFieldValue(field: "\(property) before")
            } else if lookaheadLabel("after") {
                try expectIdentifier("after")
                try expectSymbol(":")
                guard after == nil else {
                    throw error(previous, "\(property) update predicate accepts after only once")
                }
                after = try parseStringMatchFieldValue(field: "\(property) after")
            } else {
                throw error(currentToken, "\(property) update predicate accepts before and after")
            }
            guard consumeSymbol(",") else { break }
        }
        return (before, after)
    }

    mutating func parseTraitsPropertyChangeFields() throws -> (before: TraitSetMatch?, after: TraitSetMatch?) {
        var before: TraitSetMatch?
        var after: TraitSetMatch?
        if currentToken.isSymbol(")") {
            return (nil, nil)
        }
        while true {
            if lookaheadLabel("before") {
                try expectIdentifier("before")
                try expectSymbol(":")
                guard before == nil else {
                    throw error(previous, "traits update predicate accepts before only once")
                }
                before = try parseTraitSetMatch(role: "traits before")
            } else if lookaheadLabel("after") {
                try expectIdentifier("after")
                try expectSymbol(":")
                guard after == nil else {
                    throw error(previous, "traits update predicate accepts after only once")
                }
                after = try parseTraitSetMatch(role: "traits after")
            } else {
                throw error(currentToken, "traits update predicate accepts before and after")
            }
            guard consumeSymbol(",") else { break }
        }
        return (before, after)
    }

    mutating func parseTraitSetMatch(role: String) throws -> TraitSetMatch {
        try expectSymbol(".")
        let mode = try parseIdentifier()
        try expectSymbol("(")
        let match: TraitSetMatch
        switch mode {
        case "include":
            match = TraitSetMatch(include: try parseTraitArray(role: role))
        case "exclude":
            match = TraitSetMatch(exclude: try parseTraitArray(role: role))
        case "match":
            var include: [HeistTrait] = []
            var exclude: [HeistTrait] = []
            if !currentToken.isSymbol(")") {
                while true {
                    if lookaheadLabel("include") {
                        try expectIdentifier("include")
                        try expectSymbol(":")
                        include = try parseTraitArray(role: "\(role) include")
                    } else if lookaheadLabel("exclude") {
                        try expectIdentifier("exclude")
                        try expectSymbol(":")
                        exclude = try parseTraitArray(role: "\(role) exclude")
                    } else {
                        throw error(currentToken, "trait set match accepts include and exclude")
                    }
                    guard consumeSymbol(",") else { break }
                }
            }
            match = TraitSetMatch(include: include, exclude: exclude)
        default:
            throw error(previous, "unsupported trait set match '.\(mode)'. Valid: include, exclude, match")
        }
        try expectSymbol(")")
        return match
    }

    private static var validElementProperties: String {
        ElementProperty.allCases.map(\.rawValue).joined(separator: ", ")
    }
}
