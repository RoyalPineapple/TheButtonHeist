import Foundation

extension HeistPlanSourceParser {
    mutating func parseAccessibilityPredicateExpr() throws -> AccessibilityPredicate {
        let name = try parseDotCallName(allowedPrefixes: [])
        switch name {
        case "changed":
            try expectSymbol("(")
            let scopeName = try parseDotCallName(allowedPrefixes: [])
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
                let name = try parseDotCallName(allowedPrefixes: [])
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
        let name = try parseDotCallName(allowedPrefixes: [])
        guard name == "exists" || name == "missing" else {
            throw error(previous, "screen assertion accepts only .exists and .missing")
        }
        let target = try parseCurrentTreeTarget()
        return name == "exists" ? .exists(target) : .missing(target)
    }

    mutating func parseElementsAssertion() throws -> ChangeDeclaration.ElementAssertion {
        let name = try parseDotCallName(allowedPrefixes: [])
        switch name {
        case "exists", "missing":
            let target = try parseCurrentTreeTarget()
            return name == "exists" ? .exists(target) : .missing(target)
        case "appeared":
            return try parseTemporalTarget(constructor: ChangeDeclaration.ElementAssertion.appeared)
        case "disappeared":
            return try parseTemporalTarget(constructor: ChangeDeclaration.ElementAssertion.disappeared)
        case "updated":
            return try parseUpdatedAssertion()
        default:
            throw error(
                previous,
                "unsupported elements assertion '.\(name)'. Valid: exists, missing, appeared, disappeared, updated"
            )
        }
    }

    mutating func parseTemporalTarget(
        constructor: (AccessibilityTarget) -> ChangeDeclaration.ElementAssertion
    ) throws -> ChangeDeclaration.ElementAssertion {
        try expectSymbol("(")
        let target = try parseTargetExpr()
        try expectSymbol(")")
        return constructor(target)
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
        let name = try parseDotCallName(allowedPrefixes: [])
        try expectSymbol("(")
        let change: ElementPropertyChange
        switch name {
        case "value":
            change = try parseStringPropertyChange(property: "value", allowsUnlabeledAfter: true) {
                .value(before: $0, after: $1)
            }
        case "hint":
            change = try parseStringPropertyChange(property: "hint") {
                .hint(before: $0, after: $1)
            }
        case "actions":
            change = try parseTypedPropertyChange(
                property: "actions",
                parseValue: { try $0.parseActionSetMatch(role: $1) },
                project: { .actions(before: $0, after: $1) }
            )
        case "frame":
            change = try parseTypedPropertyChange(
                property: "frame",
                parseValue: { try $0.parseElementFrameMatch(role: $1) },
                project: { .frame(before: $0, after: $1) }
            )
        case "activationPoint":
            change = try parseTypedPropertyChange(
                property: "activationPoint",
                parseValue: { try $0.parseElementPointMatch(role: $1) },
                project: { .activationPoint(before: $0, after: $1) }
            )
        case "customContent":
            change = try parseTypedPropertyChange(
                property: "customContent",
                parseValue: { try $0.parseCustomContentMatch(role: $1) },
                project: { .customContent(before: $0, after: $1) }
            )
        case "rotors":
            change = try parseTypedPropertyChange(
                property: "rotors",
                parseValue: { try $0.parseRotorSetMatch(role: $1) },
                project: { .rotors(before: $0, after: $1) }
            )
        case "traits":
            change = try parseTypedPropertyChange(
                property: "traits",
                parseValue: { try $0.parseTraitSetMatch(role: $1) },
                project: { .traits(before: $0, after: $1) }
            )
        default:
            throw error(previous, "unsupported element update property '.\(name)'. Valid: \(Self.validElementProperties)")
        }
        try expectSymbol(")")
        return change
    }

    fileprivate mutating func parseStringPropertyChange(
        property: String,
        allowsUnlabeledAfter: Bool = false,
        project: (StringMatch?, StringMatch?) -> ElementPropertyChange
    ) throws -> ElementPropertyChange {
        var before: StringMatch?
        var after: StringMatch?
        if currentToken.isSymbol(")") {
            return project(nil, nil)
        }
        if allowsUnlabeledAfter && !currentTokenStartsFieldLabel {
            return project(nil, try parseStringMatchCallArgument(field: "\(property) after"))
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
        return project(before, after)
    }

    var currentTokenStartsFieldLabel: Bool {
        guard case .identifier = currentToken.kind else { return false }
        return nextTokenIsSymbol(":")
    }

    mutating func parseTraitSetMatch(role: String) throws -> TraitSetMatch {
        try expectContextualInitializer(role: "trait set match")
        let match = try parseIncludeExclude(
            role: role,
            parseInclude: { parser, role in try parser.parseTraitArray(role: role) },
            parseExclude: { parser, role in try parser.parseTraitArray(role: role) },
            project: { TraitSetMatch(include: $0 ?? [], exclude: $1 ?? []) }
        )
        try expectSymbol(")")
        return match
    }

    fileprivate mutating func parseTypedPropertyChange<T>(
        property: String,
        parseValue: (inout HeistPlanSourceParser, String) throws -> T,
        project: (T?, T?) -> ElementPropertyChange
    ) throws -> ElementPropertyChange {
        var before: T?
        var after: T?
        if currentToken.isSymbol(")") {
            return project(nil, nil)
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
        return project(before, after)
    }

    mutating func parseActionSetMatch(role: String) throws -> ActionSetMatch {
        try expectContextualInitializer(role: "action set match")
        let match = try parseIncludeExclude(
            role: role,
            parseInclude: { parser, role in Set(try parser.parseActionArray(role: role)) },
            parseExclude: { parser, role in Set(try parser.parseActionArray(role: role)) },
            project: { ActionSetMatch(include: $0 ?? [], exclude: $1 ?? []) }
        )
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
        let fields = try parseIntegerMatchFields(
            role: role,
            allowed: ["x", "y", "width", "height"]
        )
        try expectSymbol(")")
        return ElementFrameMatch(
            x: fields["x"],
            y: fields["y"],
            width: fields["width"],
            height: fields["height"]
        )
    }

    mutating func parseElementPointMatch(role: String) throws -> ElementPointMatch {
        try expectContextualInitializer(role: "activation point match")
        let fields = try parseIntegerMatchFields(
            role: role,
            allowed: ["x", "y"]
        )
        try expectSymbol(")")
        return ElementPointMatch(x: fields["x"], y: fields["y"])
    }

    mutating func parseIntegerMatchFields(
        role: String,
        allowed: Set<String>
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

    mutating func parseCustomContentMatch(role: String) throws -> CustomContentMatch {
        try expectContextualInitializer(role: "custom content match")
        var label: StringMatch?
        var value: StringMatch?
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

    mutating func parseRotorSetMatch(role: String) throws -> RotorSetMatch {
        try expectContextualInitializer(role: "rotor set match")
        let match = try parseIncludeExclude(
            role: role,
            parseInclude: { parser, role in try parser.parseStringMatchArray(role: role) },
            parseExclude: { parser, role in try parser.parseStringMatchArray(role: role) },
            project: { RotorSetMatch(include: $0 ?? [], exclude: $1 ?? []) }
        )
        try expectSymbol(")")
        return match
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

    fileprivate mutating func parseIncludeExclude<Value, Result>(
        role: String,
        parseInclude: (inout HeistPlanSourceParser, String) throws -> Value,
        parseExclude: (inout HeistPlanSourceParser, String) throws -> Value,
        project: (Value?, Value?) -> Result
    ) throws -> Result {
        var include: Value?
        var exclude: Value?
        if !currentToken.isSymbol(")") {
            while true {
                if lookaheadLabel("include") {
                    try expectIdentifier("include")
                    try expectSymbol(":")
                    guard include == nil else {
                        throw error(previous, "\(role) accepts include only once")
                    }
                    include = try parseInclude(&self, "\(role) include")
                } else if lookaheadLabel("exclude") {
                    try expectIdentifier("exclude")
                    try expectSymbol(":")
                    guard exclude == nil else {
                        throw error(previous, "\(role) accepts exclude only once")
                    }
                    exclude = try parseExclude(&self, "\(role) exclude")
                } else {
                    throw error(currentToken, "\(role) accepts include and exclude")
                }
                guard consumeSymbol(",") else { break }
            }
        }
        return project(include, exclude)
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
