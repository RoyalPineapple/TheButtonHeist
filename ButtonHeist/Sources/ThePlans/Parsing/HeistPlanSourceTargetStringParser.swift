import Foundation

private enum StringMatchEmptyLiteralPolicy {
    case reject
    case allowExact
}

extension HeistPlanSourceParser {
    mutating func parseTargetExpr() throws -> AccessibilityTarget {
        if let target = try parseTargetRefIfPresent() {
            return target
        }
        if case .string = currentToken.kind {
            throw error(currentToken, "target expression requires an explicit accessibility property such as .label(...)")
        }
        let name = try parseDotCallName()
        switch name {
        case "label", "identifier", "value", "hint", "traits",
             "actions", "customContent", "rotors", "exclude", "element":
            return .predicate(try parseElementPredicate(named: name))
        case "container":
            try expectSymbol("(")
            let predicate = try parseContainerPredicate()
            let ordinal: Int?
            if consumeSymbol(",") {
                try expectIdentifier("ordinal")
                try expectSymbol(":")
                let parsedOrdinal = try parseSignedInteger()
                guard parsedOrdinal >= 0 else {
                    throw error(previous, AccessibilityTargetGrammarError.negativeOrdinal(parsedOrdinal).diagnosticDescription)
                }
                ordinal = parsedOrdinal
            } else {
                ordinal = nil
            }
            try expectSymbol(")")
            return .container(predicate, ordinal: ordinal)
        case "target":
            try expectSymbol("(")
            let predicate = try parseElementPredicate()
            try expectSymbol(",")
            try expectIdentifier("ordinal")
            try expectSymbol(":")
            let ordinal = try parseSignedInteger()
            guard ordinal >= 0 else {
                throw error(previous, AccessibilityTargetGrammarError.negativeOrdinal(ordinal).diagnosticDescription)
            }
            try expectSymbol(")")
            return .predicate(predicate, ordinal: ordinal)
        case "within":
            try expectSymbol("(")
            try expectIdentifier("container")
            try expectSymbol(":")
            let container = try parseContainerPredicate()
            try expectSymbol(",")
            if currentToken.kind == .identifier("target"), nextToken.isSymbol(":") {
                throw error(currentToken, ".within(...) target argument is unlabeled")
            }
            let target = try parseTargetExpr()
            try expectSymbol(")")
            return .within(container: container, target: target)
        default:
            throw error(previous, "unsupported element target '.\(name)'")
        }
    }

    mutating func parseElementPredicate() throws -> ElementPredicate {
        let name = try parseDotCallName()
        return try parseElementPredicate(named: name)
    }

    mutating func parseElementPredicate(named name: String) throws -> ElementPredicate {
        if name == "element" {
            try expectSymbol("(")
            let predicate = try parseElementPredicateFields()
            try expectSymbol(")")
            return predicate
        }
        return ElementPredicate([
            try parseElementPredicateCheck(named: name, token: previous),
        ])
    }

    mutating func parseElementPredicateFields() throws -> ElementPredicate {
        var checks: [ElementPredicateCheck] = []
        if currentToken.isSymbol(")") {
            throw error(currentToken, ".element(...) requires at least one non-empty predicate check")
        }
        while true {
            if currentToken.isSymbol("."),
               case .identifier(let name) = nextToken.kind,
               Self.elementPredicateCheckNames.contains(name) {
                checks.append(try parseElementPredicateCheck())
            } else {
                throw error(
                    currentToken,
                    """
                    .element(...) accepts ordered checks like .label("Pay"), .identifier("id"), \
                    .traits([.button]), .actions([.activate]), .exclude(.traits([.notEnabled]))
                    """
                )
            }
            guard consumeSymbol(",") else { break }
        }
        return ElementPredicate(checks)
    }

    mutating func parseElementPredicateCheck() throws -> ElementPredicateCheck {
        let token = currentToken
        let name = try parseDotCallName()
        return try parseElementPredicateCheck(named: name, token: token)
    }

    private mutating func parseElementPredicateCheck(
        named name: String,
        token: HeistPlanSourceToken
    ) throws -> ElementPredicateCheck {
        switch name {
        case "label":
            try expectSymbol("(")
            let match = try parseStringMatchCallArgument(field: "label")
            try expectSymbol(")")
            return .label(match)
        case "identifier":
            try expectSymbol("(")
            let match = try parseStringMatchCallArgument(field: "identifier")
            try expectSymbol(")")
            return .identifier(match)
        case "value":
            try expectSymbol("(")
            let match = try parseStringMatchCallArgument(field: "value")
            try expectSymbol(")")
            return .value(match)
        case "hint":
            try expectSymbol("(")
            let match = try parseStringMatchCallArgument(field: "hint")
            try expectSymbol(")")
            return .hint(match)
        case "traits":
            try expectSymbol("(")
            let traits = try parseTraitArray(role: "traits")
            try rejectEmptyPredicateCollection(traits, role: "traits")
            try expectSymbol(")")
            return .traits(traits.heistTraitSet)
        case "actions":
            try expectSymbol("(")
            let actions = try parseActionArray(role: "actions")
            try rejectEmptyPredicateCollection(actions, role: "actions")
            try expectSymbol(")")
            return .actions(Set(actions))
        case "customContent":
            try expectSymbol("(")
            let match = try parseCustomContentMatchArgument(role: "customContent")
            try expectSymbol(")")
            return .customContent(match)
        case "rotors":
            try expectSymbol("(")
            let matches = try parseStringMatchArray(role: "rotors")
            try rejectEmptyPredicateCollection(matches, role: "rotors")
            try expectSymbol(")")
            return .rotors(matches)
        case "exclude":
            try expectSymbol("(")
            let check = try parseElementPredicateCheck()
            try expectSymbol(")")
            return .exclude(check)
        default:
            throw error(token, "element predicate checks accept .label, .identifier, .value, .hint, .traits, .actions, .customContent, .rotors, and .exclude")
        }
    }

    mutating func parseContainerPredicate() throws -> ContainerPredicate {
        let token = currentToken
        switch try parseDotCallName() {
        case "label":
            try expectSymbol("(")
            let label = try parseStringMatchCallArgument(field: "container label")
            try expectSymbol(")")
            return .label(label)
        case "value":
            try expectSymbol("(")
            let value = try parseStringMatchCallArgument(field: "container value")
            try expectSymbol(")")
            return .value(value)
        case "identifier":
            try expectSymbol("(")
            let identifier = try parseStringMatchCallArgument(field: "container identifier")
            try expectSymbol(")")
            return .identifier(identifier)
        case "type":
            try expectSymbol("(")
            let type = try parseEnumCase(AccessibilityContainerKind.self, role: "container kind")
            try expectSymbol(")")
            return .type(type)
        case "semanticGroup":
            return .semanticGroup
        case "none":
            return .type(.none)
        case "list":
            return .list
        case "landmark":
            return .landmark
        case "tabBar":
            return .tabBar
        case "scrollable":
            try expectSymbol("(")
            let required = try parseBoolLiteral()
            try expectSymbol(")")
            return .scrollable(required)
        case "actions":
            try expectSymbol("(")
            let actions = try parseContainerPredicateActions()
            try expectSymbol(")")
            return .actions(actions)
        case "dataTable":
            return try parseDataTableContainerPredicate()
        case "modalBoundary":
            return .modalBoundary
        case "matching":
            try expectSymbol("(")
            guard !consumeSymbol(")") else {
                throw error(previous, "container matching predicate requires at least one check")
            }
            let first = try parseContainerPredicateCheckExpr()
            var rest: [ContainerPredicateCheck] = []
            while consumeSymbol(",") {
                rest.append(try parseContainerPredicateCheckExpr())
            }
            try expectSymbol(")")
            return ContainerPredicate(checks: NonEmptyArray(first, rest: rest))
        default:
            throw error(
                token,
                "container predicates accept .none, .semanticGroup, .list, .landmark, .tabBar, " +
                ".label, .value, .identifier, .type, .dataTable(...), .modalBoundary, " +
                ".scrollable(...), .actions, and .matching"
            )
        }
    }

    mutating func parseSemanticContainerPredicate() throws -> SemanticContainerPredicate {
        let token = currentToken
        switch try parseDotCallName() {
        case "label":
            try expectSymbol("(")
            let label = try parseStringMatchCallArgument(field: "container label")
            try expectSymbol(")")
            return .label(label)
        case "value":
            try expectSymbol("(")
            let value = try parseStringMatchCallArgument(field: "container value")
            try expectSymbol(")")
            return .value(value)
        default:
            throw error(token, "semantic container predicates accept .label and .value")
        }
    }

    mutating func parseContainerPredicateCheckExpr() throws -> ContainerPredicateCheck {
        let token = currentToken
        switch try parseDotCallName() {
        case "type":
            try expectSymbol("(")
            let type = try parseEnumCase(AccessibilityContainerKind.self, role: "container kind")
            try expectSymbol(")")
            return .type(type)
        case "identifier":
            try expectSymbol("(")
            let match = try parseStringMatchCallArgument(field: "container identifier")
            try expectSymbol(")")
            return .identifier(match)
        case "semantic":
            try expectSymbol("(")
            let predicate = try parseSemanticContainerPredicate()
            try expectSymbol(")")
            return .semantic(predicate)
        case "rowCount":
            try expectSymbol("(")
            let rowCount = try parseContainerPredicateCount(role: "container rowCount")
            try expectSymbol(")")
            return .rowCount(rowCount)
        case "columnCount":
            try expectSymbol("(")
            let columnCount = try parseContainerPredicateCount(role: "container columnCount")
            try expectSymbol(")")
            return .columnCount(columnCount)
        case "modalBoundary":
            try expectSymbol("(")
            let required = try parseBoolLiteral()
            try expectSymbol(")")
            return .modalBoundary(required)
        case "scrollable":
            try expectSymbol("(")
            let required = try parseBoolLiteral()
            try expectSymbol(")")
            return .scrollable(required)
        case "actions":
            try expectSymbol("(")
            let actions = try parseContainerPredicateActions()
            try expectSymbol(")")
            return .actions(actions)
        default:
            throw error(
                token,
                "container predicate checks accept .type, .identifier, .semantic, .rowCount, "
                    + ".columnCount, .modalBoundary, .scrollable(...), and .actions"
            )
        }
    }

    mutating func parseDataTableContainerPredicate() throws -> ContainerPredicate {
        try expectSymbol("(")
        var rowCount: ContainerPredicateCount?
        var columnCount: ContainerPredicateCount?
        if !consumeSymbol(")") {
            repeat {
                if consumeLabel("rowCount") {
                    rowCount = try parseContainerPredicateCount(role: "container rowCount")
                } else if consumeLabel("columnCount") {
                    columnCount = try parseContainerPredicateCount(role: "container columnCount")
                } else {
                    throw error(currentToken, "dataTable accepts rowCount and columnCount")
                }
            } while consumeSymbol(",")
            try expectSymbol(")")
        }
        return .dataTable(rowCount: rowCount, columnCount: columnCount)
    }

    mutating func parseContainerPredicateCount(role: String) throws -> ContainerPredicateCount {
        guard currentToken.isSymbol(".") else {
            throw error(currentToken, "\(role) must use .init(...)")
        }
        try expectContextualInitializer(role: role)
        let token = currentToken
        let isNegative = consumeSymbol("-")
        let value = try parseInteger()
        try expectSymbol(")")
        guard !isNegative, let count = ContainerPredicateCount(exactly: value) else {
            throw error(token, "\(role) must be non-negative")
        }
        return count
    }

    mutating func parseContainerPredicateActions() throws -> ContainerPredicateActions {
        guard currentToken.isSymbol(".") else {
            throw error(currentToken, "container actions must use .init(...)")
        }
        try expectContextualInitializer(role: "container actions")
        guard !consumeSymbol(")") else {
            throw error(previous, "container actions predicate payload must not be empty")
        }
        let first = try parseElementAction(role: "container actions")
        var rest: [ElementAction] = []
        while consumeSymbol(",") {
            rest.append(try parseElementAction(role: "container actions"))
        }
        try expectSymbol(")")
        guard let actions = ContainerPredicateActions(Set([first] + rest)) else {
            throw error(previous, "container actions predicate payload must not be empty")
        }
        return actions
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

    func rejectEmptyPredicateCollection<C: Collection>(_ values: C, role: String) throws {
        guard values.isEmpty else { return }
        throw error(previous, "\(role) predicate payload must not be empty")
    }

    mutating func parseStringMatchCallArgument(field: String) throws -> StringMatch {
        if currentToken.isSymbol("."), nextToken.kind == .identifier("exact") {
            throw error(currentToken, "exact \(field) matches use the literal form: .\(field)(\"...\")")
        }
        if let label = stringMatchModeLabelIfPresent() {
            throw error(currentToken, "StringMatch modes use enum-case syntax; use `.\(field)(.\(label)(\"...\"))`")
        }
        if nextStringMatchMode != nil {
            return try parseStringMatchDotCall(field: field)
        }
        return try validatedStringMatch(.exact, value: try parseStringExpr(), field: field, token: previous)
    }

    mutating func parseStringMatchFieldValue(field: String) throws -> StringMatch {
        try parseStringMatchFieldValue(field: field, emptyLiteralPolicy: .reject)
    }

    mutating func parseStringPropertyUpdateFieldValue(field: String) throws -> StringMatch {
        try parseStringMatchFieldValue(field: field, emptyLiteralPolicy: .allowExact)
    }

    private mutating func parseStringMatchFieldValue(
        field: String,
        emptyLiteralPolicy: StringMatchEmptyLiteralPolicy
    ) throws -> StringMatch {
        if currentToken.isSymbol("."), nextToken.kind == .identifier("exact") {
            throw error(currentToken, "exact \(field) matches use the literal form: \(field): \"...\"")
        }
        if let label = stringMatchModeLabelIfPresent() {
            throw error(currentToken, "StringMatch modes use enum-case syntax; use `\(field): .\(label)(\"...\")`")
        }
        if nextStringMatchMode != nil {
            return try parseStringMatchDotCall(field: field, emptyLiteralPolicy: emptyLiteralPolicy)
        }
        return try validatedStringMatch(
            .exact,
            value: try parseStringExpr(),
            field: field,
            token: previous,
            emptyLiteralPolicy: emptyLiteralPolicy
        )
    }

    private mutating func parseStringMatchDotCall(
        field: String,
        emptyLiteralPolicy: StringMatchEmptyLiteralPolicy = .reject
    ) throws -> StringMatch {
        let token = currentToken
        let name = try parseDotCallName()
        guard let mode = stringMatchMode(named: name) else {
            throw error(token, "unsupported string match '.\(name)'")
        }
        if mode == .isEmpty {
            return .isEmpty
        }
        try expectSymbol("(")
        let value = try parseStringExpr()
        try expectSymbol(")")
        return try validatedStringMatch(
            mode,
            value: value,
            field: field,
            token: token,
            emptyLiteralPolicy: emptyLiteralPolicy
        )
    }

    func stringMatchModeLabelIfPresent() -> String? {
        guard case .identifier(let name) = currentToken.kind,
              nextToken.isSymbol(":"),
              StringMatch.Mode.sourceCallModes.contains(where: { $0.rawValue == name })
        else { return nil }
        return name
    }

    var nextStringMatchMode: StringMatch.Mode? {
        guard currentToken.isSymbol("."),
              case .identifier(let name) = nextToken.kind,
              let mode = StringMatch.Mode(rawValue: name),
              StringMatch.Mode.sourceCallModes.contains(mode)
        else { return nil }
        return mode
    }

    func stringMatchMode(named name: String) -> StringMatch.Mode? {
        StringMatch.Mode(rawValue: name)
    }

    private func validatedStringMatch(
        _ mode: StringMatch.Mode,
        value: AuthoredString,
        field: String,
        token: HeistPlanSourceToken,
        emptyLiteralPolicy: StringMatchEmptyLiteralPolicy = .reject
    ) throws -> StringMatch {
        let match = StringMatch(mode: mode, value: mode == .isEmpty ? nil : value)
        if match.value?.literalIsEmpty == true,
           !(emptyLiteralPolicy == .allowExact && mode == .exact) {
            throw error(token, "\(field) match value must not be empty")
        }
        return match
    }

    mutating func parseStringExpr() throws -> AuthoredString {
        if let string = try parseStringExprIfPresent() {
            return string
        }
        if case .identifier = currentToken.kind, nextToken.isSymbol("(") {
            throw error(
                currentToken,
                "arbitrary calls are not supported inside ButtonHeist DSL bodies; wrap the heist in Swift and pass values through parameters or RunHeist"
            )
        }
        throw error(currentToken, "expected a string literal or scoped string reference")
    }

    mutating func parseStringExprIfPresent() throws -> AuthoredString? {
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

    mutating func parseTargetRefIfPresent() throws -> AccessibilityTarget? {
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
            return nextToken.kind == .identifier("target") || nextToken.kind == .identifier("within")
        }
        return false
    }

    mutating func parseCustomContentMatchArgument(role: String) throws -> CustomContentMatch {
        if currentToken.isSymbol(".") {
            return try parseCustomContentMatch(role: role)
        }
        return try parseCustomContentFields(role: role)
    }

    mutating func parseCustomContentMatch(role: String) throws -> CustomContentMatch {
        try expectContextualInitializer(role: "custom content match")
        let match = try parseCustomContentFields(role: role)
        try expectSymbol(")")
        guard match.hasPredicateLiteral else {
            throw error(previous, "\(role) match must include label, value, or isImportant")
        }
        return match
    }

    private mutating func parseCustomContentFields(role: String) throws -> CustomContentMatch {
        var label: StringMatch?
        var value: StringMatch?
        var isImportant: Bool?
        if !currentToken.isSymbol(")") {
            while true {
                if consumeLabel("label") {
                    guard label == nil else {
                        throw error(previous, "\(role) accepts label only once")
                    }
                    label = try parseStringMatchFieldValue(field: "\(role) label")
                } else if consumeLabel("value") {
                    guard value == nil else {
                        throw error(previous, "\(role) accepts value only once")
                    }
                    value = try parseStringMatchFieldValue(field: "\(role) value")
                } else if consumeLabel("isImportant") {
                    guard isImportant == nil else {
                        throw error(previous, "\(role) accepts isImportant only once")
                    }
                    isImportant = try parseBoolLiteral()
                } else {
                    throw error(currentToken, "\(role) accepts label, value, and isImportant")
                }
                guard consumeSymbol(",") else { break }
            }
        }
        return CustomContentMatch(label: label, value: value, isImportant: isImportant)
    }

    private static let elementPredicateCheckNames: Set<String> = [
        "label", "identifier", "value", "hint", "traits", "actions", "customContent", "rotors", "exclude",
    ]

}

private extension StringMatch.Mode {
    static var sourceCallModes: [Self] {
        [.contains, .prefix, .suffix, .isEmpty]
    }
}
