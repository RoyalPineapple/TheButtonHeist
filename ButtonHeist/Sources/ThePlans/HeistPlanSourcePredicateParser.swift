import Foundation

struct PropertyChangeFields<Value> {
    let before: Value?
    let after: Value?
}

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
                \(ElementProperty.parserSupportedSourceNameList)
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
        guard let descriptor = ElementProperty.parserSupportedSourceDescriptor(named: name) else {
            throw error(previous, "unsupported element update property '.\(name)'. Valid: \(ElementProperty.parserSupportedSourceNameList)")
        }
        let change: AnyPropertyChangeExpr
        switch descriptor.property {
        case .label:
            let fields = try parseStringPropertyChangeFields(descriptor: descriptor)
            change = .label(before: fields.before, after: fields.after)
        case .identifier:
            let fields = try parseStringPropertyChangeFields(descriptor: descriptor)
            change = .identifier(before: fields.before, after: fields.after)
        case .value:
            let fields = try parseStringPropertyChangeFields(descriptor: descriptor)
            change = .value(before: fields.before, after: fields.after)
        case .traits:
            let fields = try parseTraitsPropertyChangeFields(descriptor: descriptor)
            change = .traits(before: fields.before, after: fields.after)
        case .hint:
            let fields = try parseStringPropertyChangeFields(descriptor: descriptor)
            change = .hint(before: fields.before, after: fields.after)
        case .actions:
            let fields = try parseTypedPropertyChangeFields(descriptor: descriptor) {
                try $0.parseActionSetMatch(role: $1)
            }
            change = .actions(before: fields.before, after: fields.after)
        case .frame:
            let fields = try parseTypedPropertyChangeFields(descriptor: descriptor) {
                try $0.parseElementFrameMatch(role: $1)
            }
            change = .frame(before: fields.before, after: fields.after)
        case .activationPoint:
            let fields = try parseTypedPropertyChangeFields(descriptor: descriptor) {
                try $0.parseElementPointMatch(role: $1)
            }
            change = .activationPoint(before: fields.before, after: fields.after)
        case .customContent:
            let fields = try parseTypedPropertyChangeFields(descriptor: descriptor) {
                try $0.parseCustomContentMatch(role: $1)
            }
            change = .customContent(before: fields.before, after: fields.after)
        case .rotors:
            let fields = try parseTypedPropertyChangeFields(descriptor: descriptor) {
                try $0.parseRotorSetMatch(role: $1)
            }
            change = .rotors(before: fields.before, after: fields.after)
        }
        try expectSymbol(")")
        return change
    }

    mutating func parseStringPropertyChangeFields(
        descriptor: ElementProperty.SourceDescriptor
    ) throws -> PropertyChangeFields<StringMatch<StringExpr>> {
        let property = descriptor.sourceName
        var before: StringMatch<StringExpr>?
        var after: StringMatch<StringExpr>?
        if currentToken.isSymbol(")") {
            return PropertyChangeFields(before: nil, after: nil)
        }
        if descriptor.allowsUnlabeledAfter && !lookaheadLabel("before") && !lookaheadLabel("after") {
            return PropertyChangeFields(
                before: nil,
                after: try parseStringMatchCallArgument(field: "\(property) after")
            )
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
                throw error(currentToken, "\(property) update predicate accepts \(descriptor.expectedFieldList)")
            }
            guard consumeSymbol(",") else { break }
        }
        return PropertyChangeFields(before: before, after: after)
    }

    mutating func parseTraitsPropertyChangeFields(
        descriptor: ElementProperty.SourceDescriptor
    ) throws -> PropertyChangeFields<TraitSetMatch> {
        let property = descriptor.sourceName
        var before: TraitSetMatch?
        var after: TraitSetMatch?
        if currentToken.isSymbol(")") {
            return PropertyChangeFields(before: nil, after: nil)
        }
        while true {
            if lookaheadLabel("before") {
                try expectIdentifier("before")
                try expectSymbol(":")
                guard before == nil else {
                    throw error(previous, "\(property) update predicate accepts before only once")
                }
                before = try parseTraitSetMatch(role: "\(property) before")
            } else if lookaheadLabel("after") {
                try expectIdentifier("after")
                try expectSymbol(":")
                guard after == nil else {
                    throw error(previous, "\(property) update predicate accepts after only once")
                }
                after = try parseTraitSetMatch(role: "\(property) after")
            } else {
                throw error(currentToken, "\(property) update predicate accepts \(descriptor.expectedFieldList)")
            }
            guard consumeSymbol(",") else { break }
        }
        return PropertyChangeFields(before: before, after: after)
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

    mutating func parseTypedPropertyChangeFields<T>(
        descriptor: ElementProperty.SourceDescriptor,
        parseValue: (inout HeistPlanSourceParser, String) throws -> T
    ) throws -> PropertyChangeFields<T> {
        let property = descriptor.sourceName
        var before: T?
        var after: T?
        if currentToken.isSymbol(")") {
            return PropertyChangeFields(before: nil, after: nil)
        }
        while true {
            if lookaheadLabel("before") {
                try expectIdentifier("before")
                try expectSymbol(":")
                guard before == nil else {
                    throw error(previous, "\(property) update predicate accepts before only once")
                }
                before = try parseValue(&self, "\(property) before")
            } else if lookaheadLabel("after") {
                try expectIdentifier("after")
                try expectSymbol(":")
                guard after == nil else {
                    throw error(previous, "\(property) update predicate accepts after only once")
                }
                after = try parseValue(&self, "\(property) after")
            } else {
                throw error(currentToken, "\(property) update predicate accepts \(descriptor.expectedFieldList)")
            }
            guard consumeSymbol(",") else { break }
        }
        return PropertyChangeFields(before: before, after: after)
    }

    mutating func parseActionSetMatch(role: String) throws -> ActionSetMatch {
        try expectSymbol(".")
        let mode = try parseIdentifier()
        try expectSymbol("(")
        let match: ActionSetMatch
        switch mode {
        case "include":
            match = ActionSetMatch(include: Set(try parseActionArray(role: role)))
        case "exclude":
            match = ActionSetMatch(exclude: Set(try parseActionArray(role: role)))
        case "match":
            var include: Set<ElementAction> = []
            var exclude: Set<ElementAction> = []
            if !currentToken.isSymbol(")") {
                while true {
                    if lookaheadLabel("include") {
                        try expectIdentifier("include")
                        try expectSymbol(":")
                        include = Set(try parseActionArray(role: "\(role) include"))
                    } else if lookaheadLabel("exclude") {
                        try expectIdentifier("exclude")
                        try expectSymbol(":")
                        exclude = Set(try parseActionArray(role: "\(role) exclude"))
                    } else {
                        throw error(currentToken, "action set match accepts include and exclude")
                    }
                    guard consumeSymbol(",") else { break }
                }
            }
            match = ActionSetMatch(include: include, exclude: exclude)
        default:
            throw error(previous, "unsupported action set match '.\(mode)'. Valid: include, exclude, match")
        }
        try expectSymbol(")")
        return match
    }

    mutating func parseActionArray(role: String) throws -> [ElementAction] {
        try expectSymbol("[")
        var actions: [ElementAction] = []
        if !consumeSymbol("]") {
            repeat {
                actions.append(try parseElementAction(role: role))
            } while consumeSymbol(",")
            try expectSymbol("]")
        }
        return actions
    }

    mutating func parseElementAction(role: String) throws -> ElementAction {
        guard consumeSymbol(".") else {
            throw error(currentToken, "\(role) actions must use enum-style syntax like [.activate]")
        }
        let token = currentToken
        let name = try parseIdentifier()
        switch name {
        case "activate":
            return .activate
        case "increment":
            return .increment
        case "decrement":
            return .decrement
        case "custom":
            try expectSymbol("(")
            let customName = try parseStringLiteral()
            try expectSymbol(")")
            return .custom(customName)
        default:
            throw error(token, "unsupported action '.\(name)'. Valid: activate, increment, decrement, custom")
        }
    }

    mutating func parseElementFrameMatch(role: String) throws -> ElementFrameMatch {
        try expectSymbol(".")
        let mode = try parseIdentifier()
        try expectSymbol("(")
        let fields = try parseIntegerMatchFields(
            role: role,
            allowed: ["x", "y", "width", "height"],
            required: mode == "exact" ? ["x", "y", "width", "height"] : []
        )
        try expectSymbol(")")
        switch mode {
        case "exact":
            return ElementFrameMatch.exact(
                x: fields["x"]!,
                y: fields["y"]!,
                width: fields["width"]!,
                height: fields["height"]!
            )
        case "match":
            return ElementFrameMatch.match(
                x: fields["x"],
                y: fields["y"],
                width: fields["width"],
                height: fields["height"]
            )
        default:
            throw error(previous, "unsupported frame match '.\(mode)'. Valid: exact, match")
        }
    }

    mutating func parseElementPointMatch(role: String) throws -> ElementPointMatch {
        try expectSymbol(".")
        let mode = try parseIdentifier()
        try expectSymbol("(")
        let fields = try parseIntegerMatchFields(
            role: role,
            allowed: ["x", "y"],
            required: mode == "exact" ? ["x", "y"] : []
        )
        try expectSymbol(")")
        switch mode {
        case "exact":
            return ElementPointMatch.exact(x: fields["x"]!, y: fields["y"]!)
        case "match":
            return ElementPointMatch.match(x: fields["x"], y: fields["y"])
        default:
            throw error(previous, "unsupported activation point match '.\(mode)'. Valid: exact, match")
        }
    }

    mutating func parseIntegerMatchFields(
        role: String,
        allowed: Set<String>,
        required: Set<String>
    ) throws -> [String: Int] {
        var fields: [String: Int] = [:]
        if !currentToken.isSymbol(")") {
            while true {
                let token = currentToken
                let name = try parseIdentifier()
                guard allowed.contains(name) else {
                    throw error(token, "\(role) does not accept '\(name)'")
                }
                try expectSymbol(":")
                guard fields[name] == nil else {
                    throw error(token, "\(role) accepts \(name) only once")
                }
                fields[name] = try parseSignedInteger()
                guard consumeSymbol(",") else { break }
            }
        }
        for name in required where fields[name] == nil {
            throw error(currentToken, "\(role) requires \(name)")
        }
        return fields
    }

    mutating func parseSignedInteger() throws -> Int {
        let token = currentToken
        let value = try parseNumber()
        guard value.rounded(.towardZero) == value,
              value >= Double(Int.min),
              value <= Double(Int.max) else {
            throw error(token, "expected an integer")
        }
        return Int(value)
    }

    mutating func parseCustomContentMatch(role: String) throws -> CustomContentMatch<StringExpr> {
        try expectSymbol(".")
        let mode = try parseIdentifier()
        guard mode == "match" else {
            throw error(previous, "unsupported custom content match '.\(mode)'. Valid: match")
        }
        try expectSymbol("(")
        var label: StringMatch<StringExpr>?
        var value: StringMatch<StringExpr>?
        var isImportant: Bool?
        if !currentToken.isSymbol(")") {
            while true {
                if lookaheadLabel("label") {
                    try expectIdentifier("label")
                    try expectSymbol(":")
                    guard label == nil else {
                        throw error(previous, "\(role) accepts label only once")
                    }
                    label = try parseStringMatchFieldValue(field: "\(role) label")
                } else if lookaheadLabel("value") {
                    try expectIdentifier("value")
                    try expectSymbol(":")
                    guard value == nil else {
                        throw error(previous, "\(role) accepts value only once")
                    }
                    value = try parseStringMatchFieldValue(field: "\(role) value")
                } else if lookaheadLabel("isImportant") {
                    try expectIdentifier("isImportant")
                    try expectSymbol(":")
                    guard isImportant == nil else {
                        throw error(previous, "\(role) accepts isImportant only once")
                    }
                    isImportant = try parseBoolLiteral()
                } else {
                    throw error(currentToken, "custom content match accepts label, value, and isImportant")
                }
                guard consumeSymbol(",") else { break }
            }
        }
        try expectSymbol(")")
        return CustomContentMatch(label: label, value: value, isImportant: isImportant)
    }

    mutating func parseRotorSetMatch(role: String) throws -> RotorSetMatch<StringExpr> {
        try expectSymbol(".")
        let mode = try parseIdentifier()
        try expectSymbol("(")
        let match: RotorSetMatch<StringExpr>
        switch mode {
        case "include":
            match = RotorSetMatch(include: try parseStringMatchArray(role: role))
        case "exclude":
            match = RotorSetMatch(exclude: try parseStringMatchArray(role: role))
        case "match":
            var include: [StringMatch<StringExpr>] = []
            var exclude: [StringMatch<StringExpr>] = []
            if !currentToken.isSymbol(")") {
                while true {
                    if lookaheadLabel("include") {
                        try expectIdentifier("include")
                        try expectSymbol(":")
                        include = try parseStringMatchArray(role: "\(role) include")
                    } else if lookaheadLabel("exclude") {
                        try expectIdentifier("exclude")
                        try expectSymbol(":")
                        exclude = try parseStringMatchArray(role: "\(role) exclude")
                    } else {
                        throw error(currentToken, "rotor set match accepts include and exclude")
                    }
                    guard consumeSymbol(",") else { break }
                }
            }
            match = RotorSetMatch(include: include, exclude: exclude)
        default:
            throw error(previous, "unsupported rotor set match '.\(mode)'. Valid: include, exclude, match")
        }
        try expectSymbol(")")
        return match
    }

    mutating func parseStringMatchArray(role: String) throws -> [StringMatch<StringExpr>] {
        try expectSymbol("[")
        var matches: [StringMatch<StringExpr>] = []
        if !consumeSymbol("]") {
            repeat {
                matches.append(try parseStringMatchFieldValue(field: role))
            } while consumeSymbol(",")
            try expectSymbol("]")
        }
        return matches
    }

}
