import Foundation

struct StringMatchModeLabelToken {
    let name: String
    let token: HeistPlanSourceToken
}

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
        let name = try parseDotCallName(allowedPrefixes: [])
        switch name {
        case "label", "identifier", "value", "hint", "traits",
             "actions", "customContent", "rotors", "exclude", "element":
            return .predicate(try parseElementPredicateTemplate(named: name))
        case "container":
            try expectSymbol("(")
            let predicate = try parseContainerPredicateExpr()
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
            let predicate = try parseElementPredicateTemplate()
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
            let container = try parseContainerPredicateExpr()
            try expectSymbol(",")
            if lookaheadLabel("target") {
                throw error(currentToken, ".within(...) target argument is unlabeled")
            }
            let target = try parseTargetExpr()
            try expectSymbol(")")
            return .within(container: container, target: target)
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
        case "hint":
            try expectSymbol("(")
            let hint = try parseStringMatchCallArgument(field: "hint")
            try expectSymbol(")")
            return ElementPredicateTemplate(hint: hint)
        case "traits":
            try expectSymbol("(")
            let traits = try parseTraitArray(role: "traits")
            try rejectEmptyPredicateCollection(traits, role: "traits")
            try expectSymbol(")")
            return ElementPredicateTemplate(traits: traits)
        case "actions":
            try expectSymbol("(")
            let actions = try parseActionArray(role: "actions")
            try rejectEmptyPredicateCollection(actions, role: "actions")
            try expectSymbol(")")
            return ElementPredicateTemplate(actions: actions)
        case "customContent":
            try expectSymbol("(")
            let match = try parseCustomContentMatchArgument(role: "customContent")
            try expectSymbol(")")
            return ElementPredicateTemplate(customContent: match)
        case "rotors":
            try expectSymbol("(")
            let matches = try parseStringMatchArray(role: "rotors")
            try rejectEmptyPredicateCollection(matches, role: "rotors")
            try expectSymbol(")")
            return ElementPredicateTemplate(rotors: matches)
        case "exclude":
            try expectSymbol("(")
            let check = try parseElementPredicateCheck()
            try expectSymbol(")")
            return ElementPredicateTemplate([.exclude(check)])
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
        var checks: [ElementPredicateCheck<StringExpr>] = []
        if currentToken.isSymbol(")") {
            throw error(currentToken, ".element(...) requires at least one non-empty predicate check")
        }
        while true {
            if currentToken.isSymbol("."),
               lookaheadIdentifier(in: Set([
                   "label", "identifier", "value", "hint",
                   "traits",
                   "actions",
                   "customContent",
                   "rotors",
                   "exclude",
               ])) {
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
        return ElementPredicateTemplate(checks)
    }

    mutating func parseElementPredicateCheck() throws -> ElementPredicateCheck<StringExpr> {
        let token = currentToken
        switch try parseDotCallName(allowedPrefixes: []) {
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

    mutating func parseContainerPredicateExpr() throws -> ContainerPredicateExpr {
        let token = currentToken
        switch try parseDotCallName(allowedPrefixes: []) {
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
            return try parseDataTableContainerPredicateExpr()
        case "modalBoundary":
            if consumeSymbol("(") {
                let required = try parseBoolLiteral()
                try expectSymbol(")")
                return .matching(.modalBoundary(required))
            }
            return .modalBoundary
        case "matching":
            try expectSymbol("(")
            guard !consumeSymbol(")") else {
                throw error(previous, "container matching predicate requires at least one check")
            }
            let first = try parseContainerPredicateCheckExpr()
            var rest: [ContainerPredicateCheck<StringExpr>] = []
            while consumeSymbol(",") {
                rest.append(try parseContainerPredicateCheckExpr())
            }
            try expectSymbol(")")
            return ContainerPredicateExpr(checks: NonEmptyArray(first, rest: rest))
        default:
            throw error(
                token,
                "container predicates accept .none, .label, .value, .identifier, .type, " +
                ".dataTable, .scrollable(...), .actions, and .matching"
            )
        }
    }

    mutating func parseSemanticContainerPredicateExpr() throws -> SemanticContainerPredicate<StringExpr> {
        let token = currentToken
        switch try parseDotCallName(allowedPrefixes: []) {
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

    mutating func parseContainerPredicateCheckExpr() throws -> ContainerPredicateCheck<StringExpr> {
        let token = currentToken
        switch try parseDotCallName(allowedPrefixes: []) {
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
            let predicate = try parseSemanticContainerPredicateExpr()
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
            throw error(token, "container predicate checks accept .type, .identifier, .semantic, .rowCount, .columnCount, .modalBoundary, .scrollable(...), and .actions")
        }
    }

    mutating func parseDataTableContainerPredicateExpr() throws -> ContainerPredicateExpr {
        try expectSymbol("(")
        var rowCount: ContainerPredicateCount?
        var columnCount: ContainerPredicateCount?
        if !consumeSymbol(")") {
            repeat {
                if lookaheadLabel("rowCount") {
                    try expectIdentifier("rowCount")
                    try expectSymbol(":")
                    rowCount = try parseContainerPredicateCount(role: "container rowCount")
                } else if lookaheadLabel("columnCount") {
                    try expectIdentifier("columnCount")
                    try expectSymbol(":")
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

    mutating func concretePredicate(from template: ElementPredicateTemplate) throws -> ElementPredicate {
        return ElementPredicate(try template.checks.map { try concreteCheck($0) })
    }

    mutating func concreteCheck(_ check: ElementPredicateCheck<StringExpr>) throws -> ElementPredicateCheck<String> {
        switch check {
        case .label(let match):
            return try .label(concreteStringMatch(match, role: "label"))
        case .identifier(let match):
            return try .identifier(concreteStringMatch(match, role: "identifier"))
        case .value(let match):
            return try .value(concreteStringMatch(match, role: "value"))
        case .hint(let match):
            return try .hint(concreteStringMatch(match, role: "hint"))
        case .traits(let traits):
            return .traits(traits)
        case .actions(let actions):
            return .actions(actions)
        case .customContent(let match):
            return try .customContent(match.map { try concreteString($0, role: "custom content") })
        case .rotors(let matches):
            return try .rotors(matches.map { try concreteStringMatch($0, role: "rotors") })
        case .exclude(let check):
            return try .exclude(concreteCheck(check))
        }
    }

    mutating func concreteStringMatch(
        _ match: StringMatch<StringExpr>,
        role: String
    ) throws -> StringMatch<String> {
        let result = try match.map { try concreteString($0, role: role) }
        if result.valueIfPresent?.isEmpty == true {
            throw error(currentToken, "\(role) match value must not be empty")
        }
        return result
    }

    mutating func concreteStringMatch(
        _ match: StringMatch<StringExpr>?,
        role: String
    ) throws -> StringMatch<String>? {
        guard let match else { return nil }
        let result = try match.map { try concreteString($0, role: role) }
        if result.valueIfPresent?.isEmpty == true {
            throw error(currentToken, "\(role) match value must not be empty")
        }
        return result
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
        if lookaheadExactStringMatchCall {
            throw error(currentToken, "exact \(field) matches use the literal form: .\(field)(\"...\")")
        }
        if let label = stringMatchModeLabelTokenIfPresent() {
            throw error(label.token, "StringMatch modes use enum-case syntax; use `.\(field)(.\(label.name)(\"...\"))`")
        }
        if startsStringMatchDotCall {
            return try parseStringMatchDotCall(field: field)
        }
        return try validatedStringMatch(.exact, value: try parseStringExpr(), field: field, token: previous)
    }

    mutating func parseStringMatchFieldValue(field: String) throws -> StringMatch<StringExpr> {
        try parseStringMatchFieldValue(field: field, emptyLiteralPolicy: .reject)
    }

    mutating func parseStringPropertyUpdateFieldValue(field: String) throws -> StringMatch<StringExpr> {
        try parseStringMatchFieldValue(field: field, emptyLiteralPolicy: .allowExact)
    }

    private mutating func parseStringMatchFieldValue(
        field: String,
        emptyLiteralPolicy: StringMatchEmptyLiteralPolicy
    ) throws -> StringMatch<StringExpr> {
        if lookaheadExactStringMatchCall {
            throw error(currentToken, "exact \(field) matches use the literal form: \(field): \"...\"")
        }
        if let label = stringMatchModeLabelTokenIfPresent() {
            throw error(label.token, "StringMatch modes use enum-case syntax; use `\(field): .\(label.name)(\"...\")`")
        }
        if startsStringMatchDotCall {
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
    ) throws -> StringMatch<StringExpr> {
        let token = currentToken
        let name = try parseDotCallName(allowedPrefixes: [])
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

    func stringMatchModeLabelTokenIfPresent() -> StringMatchModeLabelToken? {
        for name in stringMatchModeNames where lookaheadLabel(name) {
            return StringMatchModeLabelToken(name: name, token: currentToken)
        }
        return nil
    }

    var startsStringMatchDotCall: Bool {
        if currentToken.isSymbol(".") {
            return lookaheadIdentifier(in: stringMatchModeNames)
        }
        return false
    }

    var lookaheadExactStringMatchCall: Bool {
        currentToken.isSymbol(".") && lookaheadIdentifier(in: ["exact"])
    }

    var stringMatchModeNames: Set<String> {
        Set(StringMatch<StringExpr>.Mode.sourceCallModes.map(\.rawValue))
    }

    func stringMatchMode(named name: String) -> StringMatch<StringExpr>.Mode? {
        StringMatch<StringExpr>.Mode(rawValue: name)
    }

    private func validatedStringMatch(
        _ mode: StringMatch<StringExpr>.Mode,
        value: StringExpr,
        field: String,
        token: HeistPlanSourceToken,
        emptyLiteralPolicy: StringMatchEmptyLiteralPolicy = .reject
    ) throws -> StringMatch<StringExpr> {
        let match = StringMatch(mode: mode, value: value)
        if match.valueIfPresent?.stringMatchLiteralIsEmpty == true,
           !(emptyLiteralPolicy == .allowExact && mode == .exact) {
            throw error(token, "\(field) match value must not be empty")
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
            return lookaheadIdentifier(in: ["target", "within"])
        }
        return false
    }

    mutating func parseCustomContentMatchArgument(role: String) throws -> CustomContentMatch<StringExpr> {
        if currentToken.isSymbol(".") {
            return try parseCustomContentMatch(role: role)
        }

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
                    throw error(currentToken, "\(role) accepts label, value, and isImportant")
                }
                guard consumeSymbol(",") else { break }
            }
        }
        return CustomContentMatch(label: label, value: value, isImportant: isImportant)
    }

}

private extension StringMatch.Mode {
    static var sourceCallModes: [Self] {
        [.contains, .prefix, .suffix, .isEmpty]
    }
}
