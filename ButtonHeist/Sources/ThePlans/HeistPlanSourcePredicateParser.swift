import Foundation

struct PropertyChangeFields<Value> {
    let before: Value?
    let after: Value?
}

extension HeistPlanSourceParser {
    mutating func parseAccessibilityPredicateExpr() throws -> AccessibilityPredicateExpr {
        if case .string = currentToken.kind {
            throw error(currentToken, "accessibility predicate requires an explicit accessibility property such as .exists(.label(...)) or .label(...)")
        }
        let name = try parseDotCallName(allowedPrefixes: [])
        switch name {
        case "change":
            try expectSymbol("(")
            var changes: [ChangeScopePredicateExpr] = []
            if !consumeSymbol(")") {
                repeat {
                    changes.append(try parseChangeScopePredicateExpr())
                } while consumeSymbol(",")
                try expectSymbol(")")
            }
            switch changes.count {
            case 0:
                return .changePredicate(.any)
            case 1:
                return .changePredicate(changes[0].change)
            default:
                return .changePredicate(.allScopes(NonEmptyArray(changes[0], rest: Array(changes.dropFirst()))))
            }
        case "noChange":
            return .noChangePredicate
        case "announcement":
            return .announcement(try parseAnnouncementPredicateExpr())
        case "exists":
            return .state(try parseExistsMissingState(name: name))
        case "missing":
            return .state(try parseExistsMissingState(name: name))
        case "all":
            return .state(try parseAllState())
        case "label", "identifier", "value", "hint", "traits",
             "actions", "customContent", "rotors", "exclude",
             "element":
            return .exists(try parseElementPredicateTemplate(named: name))
        case "appeared":
            return .changePredicate(.elementsScope([try parseAppearedElementDeltaPredicateExpr()]))
        case "disappeared":
            return .changePredicate(.elementsScope([try parseDisappearedElementDeltaPredicateExpr()]))
        case "updated":
            return .changePredicate(.elementsScope([try parseUpdatedElementDeltaPredicateExpr()]))
        case "screenChanged":
            return .changePredicate(try parseScreenChangedPredicateExpr().change)
        default:
            throw error(previous, "unsupported accessibility predicate '.\(name)'")
        }
    }

    mutating func parseAnnouncementPredicateExpr() throws -> AnnouncementPredicateExpr {
        guard consumeSymbol("(") else {
            return AnnouncementPredicateExpr()
        }
        if consumeSymbol(")") {
            return AnnouncementPredicateExpr()
        }
        let match: StringMatch<StringExpr>
        if lookaheadLabel("containing") {
            try expectIdentifier("containing")
            try expectSymbol(":")
            let token = currentToken
            match = try validatedAnnouncementStringMatch(.contains, value: try parseStringExpr(), token: token)
        } else {
            match = try parseStringMatchCallArgument(field: "announcement")
        }
        try expectSymbol(")")
        return AnnouncementPredicateExpr(match: match)
    }

    private func validatedAnnouncementStringMatch(
        _ mode: StringMatch<StringExpr>.Mode,
        value: StringExpr,
        token: HeistPlanSourceToken
    ) throws -> StringMatch<StringExpr> {
        let match = StringMatch(mode: mode, value: value)
        if match.valueIfPresent?.stringMatchLiteralIsEmpty == true {
            throw error(token, "announcement match value must not be empty")
        }
        return match
    }

    mutating func parseChangePredicateExpr() throws -> ChangePredicateExpr {
        try parseChangeScopePredicateExpr().change
    }

    mutating func parseChangeScopePredicateExpr() throws -> ChangeScopePredicateExpr {
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
            return .screen(assertions)
        case "screenChanged":
            return try parseScreenChangedPredicateExpr()
        case "elements":
            try expectSymbol("(")
            var assertions: [ElementDeltaPredicateExpr] = []
            if !consumeSymbol(")") {
                repeat {
                    assertions.append(try parseElementDeltaPredicateExpr())
                } while consumeSymbol(",")
                try expectSymbol(")")
            }
            return .elements(assertions)
        case "appeared":
            return .elements([try parseAppearedElementDeltaPredicateExpr()])
        case "disappeared":
            return .elements([try parseDisappearedElementDeltaPredicateExpr()])
        case "updated":
            return .elements([try parseUpdatedElementDeltaPredicateExpr()])
        default:
            throw error(previous, "unsupported change predicate '.\(name)'. Valid: screenChanged, screen, elements, appeared, disappeared, updated")
        }
    }

    mutating func parseScreenChangedPredicateExpr() throws -> ChangeScopePredicateExpr {
        guard consumeSymbol("(") else {
            return .screen([])
        }
        var assertions: [StatePredicateExpr] = []
        if !consumeSymbol(")") {
            repeat {
                assertions.append(try parseStatePredicateExpr())
            } while consumeSymbol(",")
            try expectSymbol(")")
        }
        return .screen(assertions)
    }

    mutating func parseStatePredicateExpr() throws -> StatePredicateExpr {
        let name = try parseDotCallName(allowedPrefixes: [])
        switch name {
        case "exists", "missing":
            return try parseExistsMissingState(name: name)
        case "all":
            return try parseAllState()
        case "label", "identifier", "value", "hint", "traits",
             "actions", "customContent", "rotors", "exclude",
             "element":
            return .exists(try parseElementPredicateTemplate(named: name))
        default:
            throw error(previous, "unsupported state predicate '.\(name)'")
        }
    }

    mutating func parseExistsMissingState(name: String) throws -> StatePredicateExpr {
        try expectSymbol("(")
        if currentToken.isSymbol(")") {
            throw error(currentToken, ".\(name) requires an element matcher or target")
        }
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
        return .all(NonEmptyArray(states[0], rest: Array(states.dropFirst())))
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
        if currentToken.isSymbol(")") {
            throw error(currentToken, ".appeared requires an element matcher")
        }
        let predicate = try parseElementPredicateTemplate()
        try expectSymbol(")")
        return .appearedElement(predicate)
    }

    mutating func parseDisappearedElementDeltaPredicateExpr() throws -> ElementDeltaPredicateExpr {
        try expectSymbol("(")
        if currentToken.isSymbol(")") {
            throw error(currentToken, ".disappeared requires an element matcher")
        }
        let predicate = try parseElementPredicateTemplate()
        try expectSymbol(")")
        return .disappearedElement(predicate)
    }

    mutating func parseUpdatedElementDeltaPredicateExpr() throws -> ElementDeltaPredicateExpr {
        try expectSymbol("(")
        if currentToken.isSymbol(")") {
            throw error(currentToken, ".updated(...) requires an update matcher")
        }
        if lookaheadLabel("element") {
            throw error(currentToken, "updated(element:) is not supported; use .updated(.label(...), .value(...))")
        }

        let update: ElementUpdatePredicateExpr
        if lookaheadElementUpdateMatcherFollowedByChange {
            let element = try parseElementPredicateTemplate()
            try expectSymbol(",")
            update = ElementUpdatePredicateExpr(element: element, change: try parsePropertyChangeExpr())
        } else if lookaheadElementUpdateMatcherOnly {
            throw error(currentToken, ".updated(...) with an element matcher also requires an update matcher")
        } else if startsElementUpdatePropertyChange {
            update = ElementUpdatePredicateExpr(change: try parsePropertyChangeExpr())
        } else {
            let element = try parseElementPredicateTemplate()
            guard consumeSymbol(",") else {
                throw error(currentToken, ".updated(...) with an element matcher also requires an update matcher")
            }
            update = ElementUpdatePredicateExpr(element: element, change: try parsePropertyChangeExpr())
        }
        try expectSymbol(")")
        return .updatedElement(update)
    }

    var lookaheadElementUpdateMatcherFollowedByChange: Bool {
        var parser = self
        guard (try? parser.parseElementPredicateTemplate()) != nil else { return false }
        return parser.consumeSymbol(",")
    }

    var lookaheadElementUpdateMatcherOnly: Bool {
        var parser = self
        guard (try? parser.parseElementPredicateTemplate()) != nil else { return false }
        guard parser.currentToken.isSymbol(")") else { return false }
        return !lookaheadIdentifier(1, "value")
    }

    var startsElementUpdatePropertyChange: Bool {
        currentToken.isSymbol(".") && lookaheadIdentifier(in: Self.validElementPropertyNames)
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
            let fields = try parseTypedPropertyChangeFields(property: "actions") {
                try $0.parseActionSetMatch(role: $1)
            }
            change = .actions(before: fields.before, after: fields.after)
        case "frame":
            let fields = try parseTypedPropertyChangeFields(property: "frame") {
                try $0.parseElementFrameMatch(role: $1)
            }
            change = .frame(before: fields.before, after: fields.after)
        case "activationPoint":
            let fields = try parseTypedPropertyChangeFields(property: "activationPoint") {
                try $0.parseElementPointMatch(role: $1)
            }
            change = .activationPoint(before: fields.before, after: fields.after)
        case "customContent":
            let fields = try parseTypedPropertyChangeFields(property: "customContent") {
                try $0.parseCustomContentMatch(role: $1)
            }
            change = .customContent(before: fields.before, after: fields.after)
        case "rotors":
            let fields = try parseTypedPropertyChangeFields(property: "rotors") {
                try $0.parseRotorSetMatch(role: $1)
            }
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
    ) throws -> PropertyChangeFields<StringMatch<StringExpr>> {
        var before: StringMatch<StringExpr>?
        var after: StringMatch<StringExpr>?
        if currentToken.isSymbol(")") {
            return PropertyChangeFields(before: nil, after: nil)
        }
        if allowsUnlabeledAfter && !currentTokenStartsFieldLabel {
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
                before = try parseStringPropertyUpdateFieldValue(field: "\(property) before")
            } else if lookaheadLabel("after") {
                try expectIdentifier("after")
                try expectSymbol(":")
                guard after == nil else {
                    throw error(previous, "\(property) update predicate accepts after only once")
                }
                after = try parseStringPropertyUpdateFieldValue(field: "\(property) after")
            } else {
                throw error(currentToken, "\(property) update predicate accepts before and after")
            }
            guard consumeSymbol(",") else { break }
        }
        if before != nil, after == nil {
            throw error(currentToken, "\(property) update predicate requires after when before is set")
        }
        return PropertyChangeFields(before: before, after: after)
    }

    var currentTokenStartsFieldLabel: Bool {
        guard case .identifier = currentToken.kind else { return false }
        return nextTokenIsSymbol(":")
    }

    mutating func parseTraitsPropertyChangeFields() throws -> PropertyChangeFields<TraitSetMatch> {
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
        if before != nil, after == nil {
            throw error(currentToken, "traits update predicate requires after when before is set")
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
        property: String,
        parseValue: (inout HeistPlanSourceParser, String) throws -> T
    ) throws -> PropertyChangeFields<T> {
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
                throw error(currentToken, "\(property) update predicate accepts before and after")
            }
            guard consumeSymbol(",") else { break }
        }
        if before != nil, after == nil {
            throw error(currentToken, "\(property) update predicate requires after when before is set")
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
            let customNameToken = currentToken
            let customName = try parseStringLiteral()
            do {
                try CustomActionTarget.validate(actionName: customName)
            } catch let validationError {
                throw error(customNameToken, String(describing: validationError))
            }
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
        let match = CustomContentMatch(label: label, value: value, isImportant: isImportant)
        guard match.hasPredicateLiteral else {
            throw error(previous, "\(role) match must include label, value, or isImportant")
        }
        return match
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

    private static var validElementPropertyNames: Set<String> {
        Set(validElementUpdateProperties.map(\.rawValue))
    }

    private static var validElementUpdateProperties: [ElementProperty] {
        ElementProperty.allCases.filter { $0 != .label && $0 != .identifier }
    }

    private static var validElementProperties: String {
        validElementUpdateProperties.map(\.rawValue).joined(separator: ", ")
    }
}
