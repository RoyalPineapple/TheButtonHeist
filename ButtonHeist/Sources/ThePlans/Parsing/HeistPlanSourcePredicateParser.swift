import Foundation

extension HeistPlanSourceParser {
    mutating func parseAccessibilityPredicateExpr() throws -> AccessibilityPredicate {
        let name = try parseDotCallName()
        switch name {
        case "changed":
            try expectSymbol("(")
            let scopeName = try parseDotCallName()
            let predicate: AccessibilityPredicate
            switch scopeName {
            case "screen": predicate = .changed(try parseScreenDelta())
            case "elements": predicate = .changed(try parseElementsDelta())
            default: throw error(previous, "unsupported changed scope '.\(scopeName)'. Valid: screen, elements")
            }
            try expectSymbol(")")
            return predicate
        case "noChange":
            return .noChange
        case "announcement":
            return try parseAnnouncementPredicate()
        case "exists", "missing":
            let target = try parseCurrentTreeTarget()
            return name == "exists" ? .exists(target) : .missing(target)
        default:
            throw error(previous, "unsupported accessibility predicate '.\(name)'")
        }
    }

    mutating func parseAnnouncementPredicate() throws -> AccessibilityPredicate {
        guard consumeSymbol("(") else { return .announcement }
        if consumeSymbol(")") {
            throw error(previous, "empty announcement predicate must use .announcement")
        }
        let expression = try parseStringMatchCallArgument(field: "announcement")
        try expectSymbol(")")
        return .announcement(expression)
    }

    mutating func parseScreenDelta() throws -> ChangeDeclaration {
        try expectSymbol("(")
        var assertions: [ChangeDeclaration.ScreenAssertion] = []
        if !consumeSymbol(")") {
            try expectSymbol("[")
            repeat {
                let name = try parseDotCallName()
                guard name == "exists" || name == "missing" else {
                    throw error(previous, "screen assertions accept only .exists and .missing")
                }
                let target = try parseCurrentTreeTarget()
                assertions.append(name == "exists" ? .exists(target) : .missing(target))
            } while consumeSymbol(",")
            try expectSymbol("]")
            try expectSymbol(")")
        }
        return .screen(assertions)
    }

    mutating func parseElementsDelta() throws -> ChangeDeclaration {
        try expectSymbol("(")
        var assertions: [ChangeDeclaration.ElementAssertion] = []
        if !consumeSymbol(")") {
            try expectSymbol("[")
            repeat {
                assertions.append(try parseElementsAssertion())
            } while consumeSymbol(",")
            try expectSymbol("]")
            try expectSymbol(")")
        }
        return .elements(assertions)
    }

    mutating func parseCurrentTreeTarget() throws -> AccessibilityTarget {
        try expectSymbol("(")
        let target = try parseTargetExpr()
        try expectSymbol(")")
        return target
    }

    mutating func parseScreenAssertion() throws -> ChangeDeclaration.ScreenAssertion {
        let name = try parseDotCallName()
        guard name == "exists" || name == "missing" else {
            throw error(previous, "screen assertion accepts only .exists and .missing")
        }
        let target = try parseCurrentTreeTarget()
        return name == "exists" ? .exists(target) : .missing(target)
    }

    mutating func parseElementsAssertion() throws -> ChangeDeclaration.ElementAssertion {
        let name = try parseDotCallName()
        switch name {
        case "exists", "missing":
            let target = try parseCurrentTreeTarget()
            return name == "exists" ? .exists(target) : .missing(target)
        case "appeared":
            return .appeared(try parseCurrentTreeTarget())
        case "disappeared":
            return .disappeared(try parseCurrentTreeTarget())
        case "updated":
            return try parseUpdatedAssertion()
        default:
            throw error(
                previous,
                "unsupported elements assertion '.\(name)'. Valid: exists, missing, appeared, disappeared, updated"
            )
        }
    }

    mutating func parseUpdatedAssertion() throws -> ChangeDeclaration.ElementAssertion {
        try expectSymbol("(")
        let target = try parseTargetExpr()
        try expectSymbol(",")
        let change = try parsePropertyChangeExpr()
        try expectSymbol(")")
        return .updated(target, change)
    }
    mutating func parsePropertyChangeExpr() throws -> ElementPropertyChange {
        let name = try parseDotCallName()
        try expectSymbol("(")
        let change: ElementPropertyChange
        switch name {
        case "value":
            var before: StringMatch?
            var after: StringMatch?
            try parsePropertyChangeFields(
                property: name,
                allowsUnlabeledAfter: true
            ) { parser, isBefore, isLabeled, role in
                let value = try isLabeled
                    ? parser.parseStringPropertyUpdateFieldValue(field: role)
                    : parser.parseStringMatchCallArgument(field: role)
                if isBefore { before = value } else { after = value }
            }
            change = .value(before: before, after: after)
        case "hint":
            var before: StringMatch?
            var after: StringMatch?
            try parsePropertyChangeFields(property: name) { parser, isBefore, _, role in
                let value = try parser.parseStringPropertyUpdateFieldValue(field: role)
                if isBefore { before = value } else { after = value }
            }
            change = .hint(before: before, after: after)
        case "actions":
            var before: ActionSetMatch?
            var after: ActionSetMatch?
            try parsePropertyChangeFields(property: name) { parser, isBefore, _, role in
                let value = try parser.parseActionSetMatch(role: role)
                if isBefore { before = value } else { after = value }
            }
            change = .actions(before: before, after: after)
        case "frame":
            var before: ElementFrameMatch?
            var after: ElementFrameMatch?
            try parsePropertyChangeFields(property: name) { parser, isBefore, _, role in
                let value = try parser.parseElementFrameMatch(role: role)
                if isBefore { before = value } else { after = value }
            }
            change = .frame(before: before, after: after)
        case "activationPoint":
            var before: ElementPointMatch?
            var after: ElementPointMatch?
            try parsePropertyChangeFields(property: name) { parser, isBefore, _, role in
                let value = try parser.parseElementPointMatch(role: role)
                if isBefore { before = value } else { after = value }
            }
            change = .activationPoint(before: before, after: after)
        case "customContent":
            var before: CustomContentMatch?
            var after: CustomContentMatch?
            try parsePropertyChangeFields(property: name) { parser, isBefore, _, role in
                let value = try parser.parseCustomContentMatch(role: role)
                if isBefore { before = value } else { after = value }
            }
            change = .customContent(before: before, after: after)
        case "rotors":
            var before: RotorSetMatch?
            var after: RotorSetMatch?
            try parsePropertyChangeFields(property: name) { parser, isBefore, _, role in
                let value = try parser.parseRotorSetMatch(role: role)
                if isBefore { before = value } else { after = value }
            }
            change = .rotors(before: before, after: after)
        case "traits":
            var before: TraitSetMatch?
            var after: TraitSetMatch?
            try parsePropertyChangeFields(property: name) { parser, isBefore, _, role in
                let value = try parser.parseTraitSetMatch(role: role)
                if isBefore { before = value } else { after = value }
            }
            change = .traits(before: before, after: after)
        default:
            throw error(previous, "unsupported element update property '.\(name)'. Valid: \(Self.validElementProperties)")
        }
        try expectSymbol(")")
        return change
    }

    private mutating func parsePropertyChangeFields(
        property: String,
        allowsUnlabeledAfter: Bool = false,
        parse: (inout HeistPlanSourceParser, Bool, Bool, String) throws -> Void
    ) throws {
        guard !currentToken.isSymbol(")") else { return }
        let startsFieldLabel: Bool
        if case .identifier = currentToken.kind {
            startsFieldLabel = nextToken.isSymbol(":")
        } else {
            startsFieldLabel = false
        }
        if allowsUnlabeledAfter, !startsFieldLabel {
            try parse(&self, false, false, "\(property) after")
            return
        }
        var parsedBefore = false
        var parsedAfter = false
        while true {
            let isBefore: Bool
            if consumeLabel("before") {
                guard !parsedBefore else {
                    throw error(previous, "\(property) update predicate accepts before only once")
                }
                parsedBefore = true
                isBefore = true
            } else if consumeLabel("after") {
                guard !parsedAfter else {
                    throw error(previous, "\(property) update predicate accepts after only once")
                }
                parsedAfter = true
                isBefore = false
            } else {
                throw error(currentToken, "\(property) update predicate accepts before and after")
            }
            try parse(&self, isBefore, true, "\(property) \(isBefore ? "before" : "after")")
            guard consumeSymbol(",") else { break }
        }
        if parsedBefore, !parsedAfter {
            throw error(currentToken, "\(property) update predicate requires after when before is set")
        }
    }

    mutating func parseTraitSetMatch(role: String) throws -> TraitSetMatch {
        try expectContextualInitializer(role: "trait set match")
        var include: [HeistTrait] = []
        var exclude: [HeistTrait] = []
        try parseIncludeExclude(role: role) { parser, isInclude, fieldRole in
            let traits = try parser.parseTraitArray(role: fieldRole)
            if isInclude { include = traits } else { exclude = traits }
        }
        try expectSymbol(")")
        return TraitSetMatch(include: include, exclude: exclude)
    }

    mutating func parseActionSetMatch(role: String) throws -> ActionSetMatch {
        try expectContextualInitializer(role: "action set match")
        var include: Set<ElementAction> = []
        var exclude: Set<ElementAction> = []
        try parseIncludeExclude(role: role) { parser, isInclude, fieldRole in
            let actions = Set(try parser.parseActionArray(role: fieldRole))
            if isInclude { include = actions } else { exclude = actions }
        }
        try expectSymbol(")")
        return ActionSetMatch(include: include, exclude: exclude)
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
        case "typeText":
            return .typeText
        case "increment":
            return .increment
        case "decrement":
            return .decrement
        case "custom":
            try expectSymbol("(")
            let customNameToken = currentToken
            let customName = try parseStringLiteral()
            let admittedName: CustomActionName
            do {
                admittedName = try CustomActionName(validating: customName)
            } catch let validationError {
                throw error(customNameToken, String(describing: validationError))
            }
            try expectSymbol(")")
            return .custom(admittedName)
        default:
            throw error(token, "unsupported action '.\(name)'. Valid: activate, typeText, increment, decrement, custom")
        }
    }

    mutating func parseElementFrameMatch(role: String) throws -> ElementFrameMatch {
        try expectContextualInitializer(role: "frame match")
        let fields = try parseIntegerMatchFields(role: role, allowsSize: true)
        try expectSymbol(")")
        return ElementFrameMatch(
            x: fields.x,
            y: fields.y,
            width: fields.width,
            height: fields.height
        )
    }

    mutating func parseElementPointMatch(role: String) throws -> ElementPointMatch {
        try expectContextualInitializer(role: "activation point match")
        let fields = try parseIntegerMatchFields(role: role, allowsSize: false)
        try expectSymbol(")")
        return ElementPointMatch(x: fields.x, y: fields.y)
    }

    mutating func parseIntegerMatchFields(
        role: String,
        allowsSize: Bool
    ) throws -> (x: Int?, y: Int?, width: Int?, height: Int?) {
        var fields: (x: Int?, y: Int?, width: Int?, height: Int?) = (nil, nil, nil, nil)
        if !currentToken.isSymbol(")") {
            while true {
                let token = currentToken
                let name = try parseIdentifier()
                guard name == "x" || name == "y" || (allowsSize && (name == "width" || name == "height")) else {
                    throw error(token, "\(role) does not accept '\(name)'")
                }
                try expectSymbol(":")
                let isDuplicate = switch name {
                case "x": fields.x != nil
                case "y": fields.y != nil
                case "width": fields.width != nil
                case "height": fields.height != nil
                default: false
                }
                guard !isDuplicate else {
                    throw error(token, "\(role) accepts \(name) only once")
                }
                let value = try parseSignedInteger()
                switch name {
                case "x": fields.x = value
                case "y": fields.y = value
                case "width": fields.width = value
                case "height": fields.height = value
                default:
                    preconditionFailure("admitted integer match field must be assignable")
                }
                guard consumeSymbol(",") else { break }
            }
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

    mutating func parseRotorSetMatch(role: String) throws -> RotorSetMatch {
        try expectContextualInitializer(role: "rotor set match")
        var include: [StringMatch] = []
        var exclude: [StringMatch] = []
        try parseIncludeExclude(role: role) { parser, isInclude, fieldRole in
            let matches = try parser.parseStringMatchArray(role: fieldRole)
            if isInclude { include = matches } else { exclude = matches }
        }
        try expectSymbol(")")
        return RotorSetMatch(include: include, exclude: exclude)
    }

    mutating func expectContextualInitializer(role: String) throws {
        try expectSymbol(".")
        let token = currentToken
        let name = try parseIdentifier()
        guard name == "init" else {
            throw error(token, "\(role) must use .init(...)")
        }
        try expectSymbol("(")
    }

    private mutating func parseIncludeExclude(
        role: String,
        parse: (inout HeistPlanSourceParser, Bool, String) throws -> Void
    ) throws {
        var parsedInclude = false
        var parsedExclude = false
        if !currentToken.isSymbol(")") {
            while true {
                let isInclude: Bool
                if consumeLabel("include") {
                    guard !parsedInclude else {
                        throw error(previous, "\(role) accepts include only once")
                    }
                    parsedInclude = true
                    isInclude = true
                } else if consumeLabel("exclude") {
                    guard !parsedExclude else {
                        throw error(previous, "\(role) accepts exclude only once")
                    }
                    parsedExclude = true
                    isInclude = false
                } else {
                    throw error(currentToken, "\(role) accepts include and exclude")
                }
                try parse(&self, isInclude, "\(role) \(isInclude ? "include" : "exclude")")
                guard consumeSymbol(",") else { break }
            }
        }
    }

    mutating func parseStringMatchArray(role: String) throws -> [StringMatch] {
        try expectSymbol("[")
        var matches: [StringMatch] = []
        if !consumeSymbol("]") {
            repeat {
                matches.append(try parseStringMatchFieldValue(field: role))
            } while consumeSymbol(",")
            try expectSymbol("]")
        }
        return matches
    }

    private static var validElementPropertyNames: Set<String> {
        Set(ElementProperty.updateProperties.map(\.rawValue))
    }

    private static var validElementProperties: String {
        ElementProperty.updatePropertyNameList
    }
}
