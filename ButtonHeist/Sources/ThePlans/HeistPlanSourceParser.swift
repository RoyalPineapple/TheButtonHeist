import Foundation

struct HeistPlanSourceParser {
    let tokens: [HeistPlanSourceToken]
    let sourceName: String

    private var index: Int = 0
    private var scope = HeistPlanSourceScope()

    init(tokens: [HeistPlanSourceToken], sourceName: String) {
        self.tokens = tokens
        self.sourceName = sourceName
    }

    mutating func parseProgram() throws -> [HeistStep] {
        let body = try parseStatements(untilRightBrace: false)
        try expect(.eof)
        return body
    }

    private mutating func parseStatements(untilRightBrace: Bool) throws -> [HeistStep] {
        var steps: [HeistStep] = []
        while true {
            skipSemicolons()
            if atEnd { break }
            if consumeSymbol("}") {
                if untilRightBrace { return steps }
                throw error(previous, "unexpected '}'")
            }
            try rejectForbiddenStatementSyntax()
            steps.append(contentsOf: try parseStatement())
        }
        if untilRightBrace {
            throw error(currentToken, "expected '}' to close compact plan block")
        }
        return steps
    }

    private mutating func parseStatement() throws -> [HeistStep] {
        let name = try parseCalleeName()

        switch name {
        case ["Activate"]:
            return [try parseActionStep(command: parseActivateAction())]
        case ["WaitFor"]:
            return [try parseWaitFor()]
        case ["If"]:
            return [try parseIf()]
        case ["ForEach"]:
            return [try parseForEach()]
        case ["RunHeist"]:
            return [try parseRunHeist()]
        case ["Warn"]:
            return [try parseWarn()]
        case ["Fail"]:
            return [try parseFail()]
        default:
            throw error(previous, "unsupported compact plan source statement '\(name.joined(separator: "."))'")
        }
    }

    private mutating func parseActivateAction() throws -> HeistActionCommand {
        try expectSymbol("(")
        let target = try parseTargetExpr()
        try expectSymbol(")")
        return .activate(target)
    }

    private mutating func parseActionStep(
        command: HeistActionCommand
    ) throws -> HeistStep {
        var content: any HeistActionContent = ActionContent(command: command)
        while consumeSymbol(".") {
            let chainToken = currentToken
            let chain = try parseIdentifier()
            switch chain {
            case "expect":
                try expectSymbol("(")
                let predicate = try parseAccessibilityPredicateExpr()
                let timeout = try parseTrailingTimeout(defaultValue: nil)
                try expectSymbol(")")
                content = content.expect(predicate, timeout: timeout)
            default:
                throw error(chainToken, "unsupported action chain '.\(chain)'")
            }
        }
        guard let step = content.heistSteps.first, content.heistSteps.count == 1 else {
            throw error(previous, "action statement did not produce exactly one step")
        }
        return step
    }

    private mutating func parseWaitFor() throws -> HeistStep {
        try expectSymbol("(")
        if lookaheadLabel("timeout") {
            try expectIdentifier("timeout")
            try expectSymbol(":")
            let timeout = try parseDuration()
            try expectSymbol(")")
            let branches = try parsePredicateBranches()
            return .waitForCases(try WaitForCasesStep(
                timeout: timeout,
                cases: branches.cases,
                elseBody: branches.elseBody
            ))
        }

        let predicate = try parseAccessibilityPredicateExpr()
        let timeout = try parseTrailingTimeout(defaultValue: 0) ?? 0
        try expectSymbol(")")
        return .wait(WaitStep(predicate: predicate, timeout: timeout))
    }

    private mutating func parseIf() throws -> HeistStep {
        if consumeSymbol("(") {
            let predicate = try parseAccessibilityPredicateExpr()
            try expectSymbol(")")
            let body = try parseHeistBlock()
            var elseBody: [HeistStep]?
            if consumeIdentifier("otherwise") != nil {
                try expectSymbol(":")
                elseBody = try parseHeistBlock()
            }
            return .conditional(try ConditionalStep(
                cases: [PredicateCase(predicate: predicate, body: body)],
                elseBody: elseBody
            ))
        }
        let branches = try parsePredicateBranches()
        return .conditional(try ConditionalStep(cases: branches.cases, elseBody: branches.elseBody))
    }

    private mutating func parseForEach() throws -> HeistStep {
        try expectSymbol("(")
        if consumeSymbol("[") {
            let values = try parseStringArrayTail()
            let parameter = try parseOptionalParameterLabel(defaultValue: "item")
            try expectSymbol(")")
            let closure = try parseClosureParameterBlock(defaultParameterName: parameter, binding: .string)
            return .forEachString(try ForEachStringStep(
                values: values,
                parameter: closure.referenceName,
                body: closure.body
            ))
        }

        let matching = try parseElementMatches()
        var limit = 20
        var parameter = "target"
        while consumeSymbol(",") {
            if consumeIdentifier("limit") != nil {
                try expectSymbol(":")
                limit = try parseInteger()
            } else if consumeIdentifier("parameter") != nil {
                try expectSymbol(":")
                parameter = try parseStringLiteral()
            } else {
                throw error(currentToken, "ForEach(.matching(...)) accepts only limit: and parameter:")
            }
        }
        try expectSymbol(")")
        let closure = try parseClosureParameterBlock(defaultParameterName: parameter, binding: .target)
        return .forEachElement(try ForEachElementStep(
            matching: matching,
            limit: limit,
            parameter: closure.referenceName,
            body: closure.body
        ))
    }

    private mutating func parseElementMatches() throws -> ElementPredicate {
        try parseQualifiedOrShorthandCall(allowedPrefixes: ["ElementMatches"], expectedName: "matching")
        try expectSymbol("(")
        let predicate = try parseElementPredicate()
        try expectSymbol(")")
        return predicate
    }

    private mutating func parseRunHeist() throws -> HeistStep {
        try expectSymbol("(")
        let name = try parseStringLiteral()
        var argument = HeistArgument.none
        if consumeSymbol(",") {
            argument = try parseHeistArgument()
        }
        try expectSymbol(")")
        return .invoke(HeistInvocationStep(
            path: name.split(separator: ".").map(String.init),
            argument: argument
        ))
    }

    private mutating func parseHeistArgument() throws -> HeistArgument {
        if let string = try parseStringExprIfPresent() {
            return .string(string)
        }
        return .elementTarget(try parseTargetExpr())
    }

    private mutating func parseWarn() throws -> HeistStep {
        try expectSymbol("(")
        let message = try parseStringLiteral()
        try expectSymbol(")")
        return .warn(WarnStep(message: message))
    }

    private mutating func parseFail() throws -> HeistStep {
        try expectSymbol("(")
        let message = try parseStringLiteral()
        try expectSymbol(")")
        return .fail(FailStep(message: message))
    }

    private mutating func parsePredicateBranches() throws -> (
        cases: [PredicateCase],
        elseBody: [HeistStep]?
    ) {
        try expectSymbol("{")
        var cases: [PredicateCase] = []
        var elseBody: [HeistStep]?
        while !consumeSymbol("}") {
            try rejectForbiddenStatementSyntax()
            let token = currentToken
            let name = try parseIdentifier()
            switch name {
            case "Case":
                guard elseBody == nil else {
                    throw error(token, "Case must appear before Else")
                }
                try expectSymbol("(")
                let predicate = try parseAccessibilityPredicateExpr()
                try expectSymbol(")")
                cases.append(PredicateCase(predicate: predicate, body: try parseHeistBlock()))
            case "Else":
                guard elseBody == nil else {
                    throw error(token, "a branch block accepts at most one Else")
                }
                elseBody = try parseHeistBlock()
            default:
                throw error(token, "branch blocks accept only Case(...) and Else")
            }
        }
        return (cases, elseBody)
    }

    private mutating func parseHeistBlock() throws -> [HeistStep] {
        try expectSymbol("{")
        return try parseStatements(untilRightBrace: true)
    }

    private mutating func parseClosureParameterBlock(
        defaultParameterName: String,
        binding: HeistPlanSourceBinding
    ) throws -> (referenceName: String, body: [HeistStep]) {
        try expectSymbol("{")
        let localName = try parseIdentifier()
        try expectIdentifier("in")
        let previousScope = scope
        switch binding {
        case .string:
            scope.stringRefs[localName] = defaultParameterName
        case .target:
            scope.targetRefs[localName] = defaultParameterName
        }
        let body = try parseStatements(untilRightBrace: true)
        scope = previousScope
        return (defaultParameterName, body)
    }

    private mutating func parseOptionalParameterLabel(defaultValue: String) throws -> String {
        var parameter = defaultValue
        if consumeSymbol(",") {
            try expectIdentifier("parameter")
            try expectSymbol(":")
            parameter = try parseStringLiteral()
        }
        return parameter
    }

    private mutating func parseStringArrayTail() throws -> [String] {
        var values: [String] = []
        if consumeSymbol("]") { return values }
        repeat {
            values.append(try parseStringLiteral())
        } while consumeSymbol(",")
        try expectSymbol("]")
        return values
    }

    private mutating func parseAccessibilityPredicateExpr() throws -> AccessibilityPredicateExpr {
        let name = try parseDotCallName(
            allowedPrefixes: ["AccessibilityPredicate", "AccessibilityPredicateExpr"]
        )
        switch name {
        case "screenChanged":
            return .changed(.screen())
        case "elementsChanged":
            return .changed(.elements)
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
        default:
            throw error(previous, "unsupported accessibility predicate '.\(name)'")
        }
    }

    private mutating func parseChangePredicateExpr() throws -> ChangePredicateExpr {
        let name = try parseDotCallName(allowedPrefixes: ["AccessibilityPredicate.Change", "ChangePredicateExpr"])
        switch name {
        case "screenChanged":
            return .screen()
        case "elementsChanged":
            return .elements
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
        case "appeared":
            try expectSymbol("(")
            let predicate = try parseElementPredicateTemplate()
            try expectSymbol(")")
            return .appeared(predicate)
        case "disappeared":
            try expectSymbol("(")
            let predicate = try parseElementPredicateTemplate()
            try expectSymbol(")")
            return .disappeared(predicate)
        case "updated":
            try expectSymbol("(")
            let update = try parseElementUpdatePredicate()
            try expectSymbol(")")
            return .updated(update)
        default:
            throw error(previous, "unsupported change predicate '.\(name)'")
        }
    }

    private mutating func parseStatePredicateExpr() throws -> StatePredicateExpr {
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

    private mutating func parsePresentAbsentState(name: String) throws -> StatePredicateExpr {
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

    private mutating func parseAllState() throws -> StatePredicateExpr {
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

    private mutating func parseElementUpdatePredicate() throws -> ElementUpdatePredicateExpr {
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

    private mutating func parseTargetExpr() throws -> ElementTargetExpr {
        if let target = try parseTargetRefIfPresent() {
            return target
        }
        let name = try parseDotCallName(allowedPrefixes: ["ElementTarget", "ElementTargetExpr"])
        switch name {
        case "label":
            try expectSymbol("(")
            let label = try parseStringExpr()
            try expectSymbol(")")
            return .predicate(.label(label))
        case "identifier":
            try expectSymbol("(")
            let identifier = try parseStringExpr()
            try expectSymbol(")")
            return .predicate(.identifier(identifier))
        case "value":
            try expectSymbol("(")
            let value = try parseStringExpr()
            try expectSymbol(")")
            return .predicate(.value(value))
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

    private mutating func parseElementPredicateTemplate() throws -> ElementPredicateTemplate {
        let name = try parseDotCallName(allowedPrefixes: [
            "ElementPredicate",
            "ElementPredicateTemplate",
            "ElementTarget",
            "ElementTargetExpr",
        ])
        switch name {
        case "label":
            try expectSymbol("(")
            let label = try parseStringExpr()
            try expectSymbol(")")
            return .label(label)
        case "identifier":
            try expectSymbol("(")
            let identifier = try parseStringExpr()
            try expectSymbol(")")
            return .identifier(identifier)
        case "value":
            try expectSymbol("(")
            let value = try parseStringExpr()
            try expectSymbol(")")
            return .value(value)
        case "element":
            try expectSymbol("(")
            let predicate = try parseElementPredicateTemplateFields()
            try expectSymbol(")")
            return predicate
        default:
            throw error(previous, "unsupported element predicate '.\(name)'")
        }
    }

    private mutating func parseElementPredicate() throws -> ElementPredicate {
        let template = try parseElementPredicateTemplate()
        return try concretePredicate(from: template)
    }

    private mutating func parseElementPredicateTemplateFields() throws -> ElementPredicateTemplate {
        var label: StringExpr?
        var identifier: StringExpr?
        var value: StringExpr?
        var traits: [HeistTrait] = []
        var excludeTraits: [HeistTrait] = []
        if currentToken.isSymbol(")") {
            return .element()
        }
        while true {
            if consumeIdentifier("label") != nil {
                try expectSymbol(":")
                label = try parseStringExpr()
            } else if consumeIdentifier("identifier") != nil {
                try expectSymbol(":")
                identifier = try parseStringExpr()
            } else if consumeIdentifier("value") != nil {
                try expectSymbol(":")
                value = try parseStringExpr()
            } else if consumeIdentifier("traits") != nil {
                try expectSymbol(":")
                traits = try parseTraitArray()
            } else if consumeIdentifier("excludeTraits") != nil {
                try expectSymbol(":")
                excludeTraits = try parseTraitArray()
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

    private mutating func parseTraitArray() throws -> [HeistTrait] {
        try expectSymbol("[")
        var traits: [HeistTrait] = []
        if !consumeSymbol("]") {
            repeat {
                traits.append(try parseEnumCase(HeistTrait.self, role: "accessibility trait"))
            } while consumeSymbol(",")
            try expectSymbol("]")
        }
        return traits
    }

    private mutating func concretePredicate(from template: ElementPredicateTemplate) throws -> ElementPredicate {
        let label = try concreteString(template.label, role: "label")
        let identifier = try concreteString(template.identifier, role: "identifier")
        let value = try concreteString(template.value, role: "value")
        return ElementPredicate(
            label: label,
            identifier: identifier,
            value: value,
            traits: template.traits,
            excludeTraits: template.excludeTraits
        )
    }

    private func concreteString(_ string: StringExpr?, role: String) throws -> String? {
        guard let string else { return nil }
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

    private mutating func parseStringExpr() throws -> StringExpr {
        if let string = try parseStringExprIfPresent() {
            return string
        }
        throw error(currentToken, "expected a string literal or scoped string reference")
    }

    private mutating func parseStringExprIfPresent() throws -> StringExpr? {
        if case .string(let value) = currentToken.kind {
            advance()
            return .literal(value)
        }
        if case .identifier(let name) = currentToken.kind, let reference = scope.stringRefs[name] {
            advance()
            return .ref(reference)
        }
        return nil
    }

    private mutating func parseTargetRefIfPresent() throws -> ElementTargetExpr? {
        if case .identifier(let name) = currentToken.kind, let reference = scope.targetRefs[name] {
            advance()
            return .ref(reference)
        }
        return nil
    }

    private var startsTargetExpression: Bool {
        if case .identifier(let name) = currentToken.kind, scope.targetRefs[name] != nil {
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

    private mutating func parseTrailingTimeout(defaultValue: Double?) throws -> Double? {
        guard consumeSymbol(",") else { return defaultValue }
        try expectIdentifier("timeout")
        try expectSymbol(":")
        return try parseDuration()
    }

    private mutating func parseDuration() throws -> Double {
        if let number = try parseNumberIfPresent() {
            return number
        }
        if consumeSymbol(".") {
            return try parseDurationCall()
        }
        if consumeIdentifier("Double") != nil {
            try expectSymbol(".")
            return try parseDurationCall()
        }
        throw error(currentToken, "expected a timeout duration such as .seconds(1)")
    }

    private mutating func parseDurationCall() throws -> Double {
        let method = try parseIdentifier()
        try expectSymbol("(")
        let value = try parseNumber()
        try expectSymbol(")")
        switch method {
        case "seconds":
            return value
        case "milliseconds":
            return value / 1_000
        default:
            throw error(previous, "unsupported duration '.\(method)'")
        }
    }

    private mutating func parseInteger() throws -> Int {
        let token = currentToken
        guard case .number(let text) = token.kind, let value = Int(text) else {
            throw error(token, "expected an integer")
        }
        advance()
        return value
    }

    private mutating func parseNumber() throws -> Double {
        guard let value = try parseNumberIfPresent() else {
            throw error(currentToken, "expected a number")
        }
        return value
    }

    private mutating func parseNumberIfPresent() throws -> Double? {
        guard case .number(let text) = currentToken.kind else { return nil }
        guard let value = Double(text) else {
            throw error(currentToken, "invalid number '\(text)'")
        }
        advance()
        return value
    }

    private mutating func parseStringLiteral() throws -> String {
        let token = currentToken
        guard case .string(let value) = token.kind else {
            throw error(token, "expected a string literal")
        }
        advance()
        return value
    }

    private mutating func parseEnumCase<T: RawRepresentable>(
        _ type: T.Type,
        role: String
    ) throws -> T where T.RawValue == String {
        if consumeSymbol(".") {}
        let token = currentToken
        let name = try parseIdentifier()
        guard let value = T(rawValue: name) else {
            throw error(token, "unknown \(role) '.\(name)'")
        }
        return value
    }

    private mutating func parseQualifiedOrShorthandCall(
        allowedPrefixes: Set<String>,
        expectedName: String
    ) throws {
        let name = try parseDotCallName(allowedPrefixes: allowedPrefixes)
        guard name == expectedName else {
            throw error(previous, "expected .\(expectedName)(...)")
        }
    }

    private mutating func parseDotCallName(allowedPrefixes: Set<String>) throws -> String {
        if consumeSymbol(".") {
            return try parseIdentifier()
        }
        let token = currentToken
        let first = try parseIdentifier()
        if consumeSymbol(".") {
            var prefix = first
            let second = try parseIdentifier()
            if consumeSymbol(".") {
                prefix += ".\(second)"
                guard allowedPrefixes.contains(prefix) else {
                    throw error(token, "unsupported plan source type prefix '\(prefix)'")
                }
                return try parseIdentifier()
            }
            guard allowedPrefixes.contains(prefix) else {
                throw error(token, "unsupported plan source type prefix '\(prefix)'")
            }
            return second
        }
        throw error(token, "expected a plan expression beginning with '.'")
    }

    private mutating func parseCalleeName() throws -> [String] {
        let token = currentToken
        let first = try parseIdentifier()
        if first == "in" {
            throw error(token, "unexpected closure parameter separator")
        }
        var names = [first]
        while consumeSymbol(".") {
            names.append(try parseIdentifier())
        }
        return names
    }

    private mutating func parseIdentifier() throws -> String {
        let token = currentToken
        guard case .identifier(let name) = token.kind else {
            throw error(token, "expected an identifier")
        }
        advance()
        return name
    }

    private mutating func expectIdentifier(_ expected: String) throws {
        let token = currentToken
        let actual = try parseIdentifier()
        guard actual == expected else {
            throw error(token, "expected '\(expected)'")
        }
    }

    private mutating func expectSymbol(_ symbol: Character) throws {
        let token = currentToken
        guard consumeSymbol(symbol) else {
            throw error(token, "expected '\(symbol)'")
        }
    }

    private mutating func expect(_ kind: HeistPlanSourceTokenKind) throws {
        let token = currentToken
        guard token.kind == kind else {
            throw error(token, "expected \(kind.description)")
        }
        advance()
    }

    @discardableResult
    private mutating func consumeIdentifier(_ name: String) -> HeistPlanSourceToken? {
        guard case .identifier(name) = currentToken.kind else { return nil }
        let token = currentToken
        advance()
        return token
    }

    private mutating func consumeSymbol(_ symbol: Character) -> Bool {
        guard currentToken.isSymbol(symbol) else { return false }
        advance()
        return true
    }

    private mutating func skipSemicolons() {
        while consumeSymbol(";") {}
    }

    private func lookaheadLabel(_ label: String) -> Bool {
        guard case .identifier(label) = currentToken.kind else { return false }
        guard tokens.indices.contains(index + 1) else { return false }
        return tokens[index + 1].isSymbol(":")
    }

    private func lookaheadIdentifier(in values: Set<String>) -> Bool {
        guard tokens.indices.contains(index + 1),
              case .identifier(let name) = tokens[index + 1].kind else {
            return false
        }
        return values.contains(name)
    }

    private var atEnd: Bool {
        currentToken.kind == .eof
    }

    private var currentToken: HeistPlanSourceToken {
        tokens[index]
    }

    private var previous: HeistPlanSourceToken {
        tokens[max(tokens.startIndex, index - 1)]
    }

    private mutating func advance() {
        if index < tokens.count - 1 {
            index += 1
        }
    }

    private mutating func rejectForbiddenStatementSyntax() throws {
        guard case .identifier(let name) = currentToken.kind else { return }
        switch name {
        case "import":
            throw error(currentToken, "import declarations are not supported in compact plan source")
        case "let", "var":
            throw error(currentToken, "\(name) declarations are not supported in compact plan source")
        case "func":
            throw error(currentToken, "function declarations are not supported in compact plan source")
        case "class", "struct", "enum", "protocol", "extension", "actor":
            throw error(currentToken, "type declarations are not supported in compact plan source")
        case "if", "for", "while", "switch":
            throw error(currentToken, "native Swift \(name) statements are not supported; use plan source constructs")
        case "try":
            throw error(currentToken, "`try` is not supported in compact plan source; call plan constructs directly")
        default:
            return
        }
    }

    private func error(
        _ token: HeistPlanSourceToken,
        _ message: String
    ) -> HeistPlanSourceCompilerError {
        HeistPlanSourceCompilerError(
            message: message,
            sourceName: sourceName,
            offset: token.marker.offset,
            line: token.marker.line,
            column: token.marker.column
        )
    }
}

private struct HeistPlanSourceScope: Equatable {
    var stringRefs: [String: String] = [:]
    var targetRefs: [String: String] = [:]
}

private enum HeistPlanSourceBinding {
    case string
    case target
}
