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

    mutating func parseProgram() throws -> UnvalidatedHeistPlan {
        if startsRootHeistPlan {
            let root = try parseRootHeistPlan()
            let uncheckedRoot = root.uncheckedPlanForRuntimeValidation()
            try expect(.eof)
            return UnvalidatedHeistPlan(
                version: HeistPlan.currentVersion,
                name: root.name,
                parameter: root.parameter,
                definitions: root.definitions,
                body: uncheckedRoot.body
            )
        }

        try rejectForbiddenStatementSyntax()
        throw error(currentToken, "ButtonHeist source must be a canonical root plan: `HeistPlan { ... }`")
    }

    private mutating func parseRootHeistPlan() throws -> UnvalidatedHeistPlan {
        let name = try parseCalleeName()
        guard name == ["HeistPlan"] else {
            throw error(previous, "expected `HeistPlan { ... }`")
        }
        return try parseHeistPlanAfterCallee(allowDefinitions: true)
    }

    private mutating func parseHeistBody(
        untilRightBrace: Bool,
        allowDefinitions: Bool
    ) throws -> ParsedHeistBody {
        var definitions: [UnvalidatedHeistPlan] = []
        var steps: [HeistStep] = []
        var seenStep = false
        while true {
            skipSemicolons()
            if atEnd { break }
            if consumeSymbol("}") {
                if untilRightBrace {
                    return ParsedHeistBody(definitions: definitions, steps: steps)
                }
                throw error(previous, "unexpected '}'")
            }
            if allowDefinitions, startsDefinition {
                guard !seenStep else {
                    throw error(currentToken, "canonical HeistDef definitions must appear before actions in their block")
                }
                definitions.append(try parseDefinition())
                continue
            }
            try rejectForbiddenStatementSyntax()
            steps.append(contentsOf: try parseStatement())
            seenStep = true
        }
        if untilRightBrace {
            throw error(currentToken, "expected '}' to close ButtonHeist source block")
        }
        return ParsedHeistBody(definitions: definitions, steps: steps)
    }

    private mutating func parseDefinition() throws -> UnvalidatedHeistPlan {
        let callee = try parseCalleeName()
        guard callee == ["HeistDef"] else {
            throw error(previous, "heist definitions must use `HeistDef<...>(\"Name\") { ... }`")
        }
        let parameterKind = try parseHeistDefGeneric()
        let header = try parseHeistDefHeader(parameterKind: parameterKind)
        let body = try parseHeistClosureBody(parameter: header.parameter, allowDefinitions: true)
        return makeDefinition(
            path: header.path.split(separator: ".").map(String.init),
            parameter: header.parameter,
            definitions: mergeDefinitions(body.definitions),
            body: body.steps
        )
    }

    private mutating func parseHeistDefGeneric() throws -> HeistDefinitionParameterKind {
        try expectSymbol("<")
        let type = try parseIdentifier()
        try expectSymbol(">")
        switch type {
        case "Void":
            return .none
        case "String":
            return .string
        case "ElementTarget":
            return .elementTarget
        default:
            throw error(previous, "unsupported HeistDef parameter type '\(type)'")
        }
    }

    private mutating func parseHeistDefHeader(
        parameterKind: HeistDefinitionParameterKind
    ) throws -> (path: String, parameter: HeistParameter) {
        try expectSymbol("(")
        let path = try parseStringLiteral()
        var parameter = HeistParameter.none
        if consumeSymbol(",") {
            try expectIdentifier("parameter")
            try expectSymbol(":")
            let parameterName = try parseStringLiteral()
            switch parameterKind {
            case .none:
                throw error(previous, "HeistDef<Void> must not declare parameter:")
            case .string:
                parameter = .string(name: parameterName)
            case .elementTarget:
                parameter = .elementTarget(name: parameterName)
            }
        }
        try expectSymbol(")")

        switch (parameterKind, parameter) {
        case (.none, .none), (.string, .string), (.elementTarget, .elementTarget):
            break
        case (.string, .none):
            throw error(previous, "HeistDef<String> must declare `parameter: \"name\"`")
        case (.elementTarget, .none):
            throw error(previous, "HeistDef<ElementTarget> must declare `parameter: \"name\"`")
        default:
            throw error(previous, "HeistDef parameter type does not match its parameter declaration")
        }
        return (path, parameter)
    }

    private func makeDefinition(
        path: [String],
        parameter: HeistParameter,
        definitions: [UnvalidatedHeistPlan],
        body: [HeistStep]
    ) -> UnvalidatedHeistPlan {
        guard let first = path.first else {
            return UnvalidatedHeistPlan(parameter: parameter, definitions: definitions, body: body)
        }
        guard path.count > 1 else {
            return UnvalidatedHeistPlan(name: first, parameter: parameter, definitions: definitions, body: body)
        }
        return UnvalidatedHeistPlan(
            name: first,
            definitions: [
                makeDefinition(
                    path: Array(path.dropFirst()),
                    parameter: parameter,
                    definitions: definitions,
                    body: body
                ),
            ],
            body: []
        )
    }

    private func mergeDefinitions(_ definitions: [UnvalidatedHeistPlan]) -> [UnvalidatedHeistPlan] {
        var merged: [UnvalidatedHeistPlan] = []
        for definition in definitions {
            guard let name = definition.name,
                  let existingIndex = merged.firstIndex(where: { $0.name == name }) else {
                merged.append(definition)
                continue
            }
            let existing = merged[existingIndex]
            if isNamespace(existing), isNamespace(definition) {
                merged[existingIndex] = UnvalidatedHeistPlan(
                    name: name,
                    definitions: mergeDefinitions(existing.definitions + definition.definitions),
                    body: []
                )
            } else {
                merged.append(definition)
            }
        }
        return merged
    }

    private func isNamespace(_ definition: UnvalidatedHeistPlan) -> Bool {
        definition.parameter == .none && definition.body.isEmpty && !definition.definitions.isEmpty
    }

    private mutating func parseStatement() throws -> [HeistStep] {
        let tryPrefix = try parseTryPrefixIfPresent()
        if let tryPrefix {
            if let correction = runHeistCorrectionAfterTryPrefix(startingAt: index) {
                throw error(
                    tryPrefix.token,
                    "`try` is only allowed in Swift wrapper code, not inside ButtonHeist DSL bodies. Use \(correction)."
                )
            }
            throw error(tryPrefix.token, "`try` is only allowed in Swift wrapper code, not inside ButtonHeist DSL bodies")
        }

        let name = try parseCalleeName()

        switch name {
        case ["Activate"]:
            return [try parseActionStep(command: parseElementTargetAction("Activate", makeCommand: HeistActionCommand.activate))]
        case ["Increment"]:
            return [try parseActionStep(command: parseElementTargetAction("Increment", makeCommand: HeistActionCommand.increment))]
        case ["Decrement"]:
            return [try parseActionStep(command: parseElementTargetAction("Decrement", makeCommand: HeistActionCommand.decrement))]
        case ["TypeText"]:
            return [try parseActionStep(command: parseTypeTextAction())]
        case ["CustomAction"]:
            return [try parseActionStep(command: parseCustomAction())]
        case ["Rotor"]:
            return [try parseActionStep(command: parseRotorAction())]
        case ["SetPasteboard"]:
            return [try parseActionStep(command: parseSetPasteboardAction())]
        case ["Edit"]:
            return [try parseActionStep(command: parseEditAction())]
        case ["DismissKeyboard"]:
            return [try parseActionStep(command: parseDismissKeyboardAction())]
        case ["Mechanical", "Tap"]:
            return [try parseActionStep(command: parseMechanicalTap())]
        case ["Mechanical", "LongPress"]:
            return [try parseActionStep(command: parseMechanicalLongPress())]
        case ["Mechanical", "Swipe"]:
            return [try parseActionStep(command: parseMechanicalSwipe())]
        case ["Mechanical", "Drag"]:
            return [try parseActionStep(command: parseMechanicalDrag())]
        case ["WaitFor"]:
            return [try parseWaitFor()]
        case ["If"]:
            return [try parseIf()]
        case ["ForEach"]:
            return [try parseForEach()]
        case ["HeistPlan"]:
            let plan = try parseHeistPlanAfterCallee(allowDefinitions: false)
            return [.heist(plan.uncheckedPlanForRuntimeValidation())]
        case ["RunHeist"]:
            return [try parseRunHeist()]
        case ["Warn"]:
            return [try parseWarn()]
        case ["Fail"]:
            return [try parseFail()]
        default:
            throw error(previous, "unsupported ButtonHeist source statement '\(name.joined(separator: "."))'")
        }
    }

    private mutating func parseHeistPlanAfterCallee(allowDefinitions: Bool) throws -> UnvalidatedHeistPlan {
        let header = try parseHeistPlanHeader()
        let body = try parseHeistClosureBody(parameter: header.parameter, allowDefinitions: allowDefinitions)
        return UnvalidatedHeistPlan(
            version: HeistPlan.currentVersion,
            name: header.name,
            parameter: header.parameter,
            definitions: mergeDefinitions(body.definitions),
            body: body.steps
        )
    }

    private mutating func parseHeistPlanHeader() throws -> (name: String?, parameter: HeistParameter) {
        var name: String?
        var parameter = HeistParameter.none
        guard consumeSymbol("(") else {
            return (nil, .none)
        }
        if currentToken.isSymbol(")") {
            throw error(currentToken, "empty HeistPlan parentheses are not canonical; use `HeistPlan { ... }`")
        }

        if lookaheadLabel("parameter") || lookaheadLabel("targetParameter") {
            parameter = try parseRootHeistParameter()
        } else {
            name = try parseStringLiteral()
            if consumeSymbol(",") {
                parameter = try parseRootHeistParameter()
            }
        }
        try expectSymbol(")")
        return (name, parameter)
    }

    private mutating func parseRootHeistParameter() throws -> HeistParameter {
        if consumeIdentifier("parameter") != nil {
            try expectSymbol(":")
            return .string(name: try parseStringLiteral())
        }
        if consumeIdentifier("targetParameter") != nil {
            try expectSymbol(":")
            return .elementTarget(name: try parseStringLiteral())
        }
        throw error(currentToken, "expected parameter: or targetParameter:")
    }

    private mutating func parseHeistClosureBody(
        parameter: HeistParameter,
        allowDefinitions: Bool
    ) throws -> ParsedHeistBody {
        try expectSymbol("{")
        let previousScope = scope
        if let parameterName = parameter.name {
            let localName = try parseIdentifier()
            try expectIdentifier("in")
            switch parameter {
            case .string:
                scope.stringRefs[localName] = parameterName
            case .elementTarget:
                scope.targetRefs[localName] = parameterName
            case .none:
                break
            }
        }
        let body = try parseHeistBody(untilRightBrace: true, allowDefinitions: allowDefinitions)
        scope = previousScope
        return body
    }

    private mutating func parseElementTargetAction(
        _ actionName: String,
        makeCommand: (ElementTargetExpr) -> HeistActionCommand
    ) throws -> HeistActionCommand {
        try expectSymbol("(")
        let target = try parseTargetExpr()
        try rejectActionLevelOrdinalIfPresent(actionName: actionName, target: target)
        try expectSymbol(")")
        return makeCommand(target)
    }

    private mutating func rejectActionLevelOrdinalIfPresent(
        actionName: String,
        target: ElementTargetExpr
    ) throws {
        guard consumeSymbol(",") else { return }
        let token = currentToken
        if consumeIdentifier("ordinal") != nil {
            try expectSymbol(":")
            _ = try parseInteger()
            throw error(
                token,
                "Ordinal belongs to the target. Use \(actionName)(.target(\(renderTargetCorrection(target)), ordinal: 0))."
            )
        }
        throw error(token, "\(actionName)(...) accepts a single ElementTargetExpr")
    }

    private func renderTargetCorrection(_ target: ElementTargetExpr) -> String {
        switch target {
        case .predicate(let predicate, _):
            return renderPredicateCorrection(predicate)
        case .target(let target):
            return renderConcreteTargetCorrection(target)
        case .ref(let reference):
            return reference
        }
    }

    private func renderConcreteTargetCorrection(_ target: ElementTarget) -> String {
        switch target {
        case .predicate(let predicate, _):
            return renderPredicateCorrection(ElementPredicateTemplate(
                label: predicate.label.map(StringExpr.literal),
                identifier: predicate.identifier.map(StringExpr.literal),
                value: predicate.value.map(StringExpr.literal),
                traits: predicate.traits,
                excludeTraits: predicate.excludeTraits
            ))
        }
    }

    private func renderPredicateCorrection(_ predicate: ElementPredicateTemplate) -> String {
        if predicate.traits.isEmpty, predicate.excludeTraits.isEmpty {
            switch (predicate.label, predicate.identifier, predicate.value) {
            case (.some(let label), nil, nil):
                return ".label(\(renderStringCorrection(label)))"
            case (nil, .some(let identifier), nil):
                return ".identifier(\(renderStringCorrection(identifier)))"
            case (nil, nil, .some(let value)):
                return ".value(\(renderStringCorrection(value)))"
            default:
                break
            }
        }
        var fields: [String] = []
        if let label = predicate.label { fields.append("label: \(renderStringCorrection(label))") }
        if let identifier = predicate.identifier { fields.append("identifier: \(renderStringCorrection(identifier))") }
        if let value = predicate.value { fields.append("value: \(renderStringCorrection(value))") }
        if !predicate.traits.isEmpty {
            fields.append("traits: [\(predicate.traits.map { ".\($0.rawValue)" }.joined(separator: ", "))]")
        }
        if !predicate.excludeTraits.isEmpty {
            fields.append("excludeTraits: [\(predicate.excludeTraits.map { ".\($0.rawValue)" }.joined(separator: ", "))]")
        }
        return ".element(\(fields.joined(separator: ", ")))"
    }

    private func renderStringCorrection(_ string: StringExpr) -> String {
        switch string {
        case .literal(let value):
            return quote(value)
        case .ref(let reference):
            return reference
        }
    }

    private mutating func parseTypeTextAction() throws -> HeistActionCommand {
        try expectSymbol("(")
        let text = try parseStringExpr()
        var target: ElementTargetExpr?
        if consumeSymbol(",") {
            try expectIdentifier("into")
            try expectSymbol(":")
            target = try parseTargetExpr()
        }
        try expectSymbol(")")
        return .typeText(text: text, target: target)
    }

    private mutating func parseCustomAction() throws -> HeistActionCommand {
        try expectSymbol("(")
        let actionName = try parseStringLiteral()
        try expectSymbol(",")
        try expectIdentifier("on")
        try expectSymbol(":")
        let target = try parseTargetExpr()
        try expectSymbol(")")
        return .customAction(name: actionName, target: target)
    }

    private mutating func parseRotorAction() throws -> HeistActionCommand {
        try expectSymbol("(")
        let rotorName = try parseStringLiteral()
        try expectSymbol(",")
        try expectIdentifier("on")
        try expectSymbol(":")
        let target = try parseTargetExpr()
        var direction = RotorDirection.next
        if consumeSymbol(",") {
            try expectIdentifier("direction")
            try expectSymbol(":")
            direction = try parseEnumCase(RotorDirection.self, role: "rotor direction")
        }
        try expectSymbol(")")
        return .rotor(selection: .named(rotorName), target: target, direction: direction)
    }

    private mutating func parseSetPasteboardAction() throws -> HeistActionCommand {
        try expectSymbol("(")
        let text = try parseStringLiteral()
        try expectSymbol(")")
        return .setPasteboard(SetPasteboardTarget(text: text))
    }

    private mutating func parseEditAction() throws -> HeistActionCommand {
        try expectSymbol("(")
        let action = try parseEnumCase(EditAction.self, role: "edit action")
        try expectSymbol(")")
        return .editAction(EditActionTarget(action: action))
    }

    private mutating func parseDismissKeyboardAction() throws -> HeistActionCommand {
        try expectSymbol("(")
        try expectSymbol(")")
        return .dismissKeyboard
    }

    private mutating func parseMechanicalTap() throws -> HeistActionCommand {
        try expectSymbol("(")
        let selection: GesturePointSelection
        if lookaheadLabel("x") {
            let point = try parseXYArguments()
            selection = .coordinate(point)
        } else {
            selection = .element(try parseConcreteElementTarget())
        }
        try expectSymbol(")")
        return .mechanicalTap(TapTarget(selection: selection))
    }

    private mutating func parseMechanicalLongPress() throws -> HeistActionCommand {
        try expectSymbol("(")
        let selection: GesturePointSelection
        var duration = GestureDuration.longPressDefault
        if lookaheadLabel("x") {
            let point = try parseXYArguments()
            selection = .coordinate(point)
            if consumeSymbol(",") {
                try expectIdentifier("duration")
                try expectSymbol(":")
                duration = try parseGestureDuration()
            }
        } else {
            selection = .element(try parseConcreteElementTarget())
        }
        try expectSymbol(")")
        return .mechanicalLongPress(LongPressTarget(selection: selection, duration: duration))
    }

    private mutating func parseMechanicalSwipe() throws -> HeistActionCommand {
        try expectSymbol("(")
        let selection: SwipeGestureSelection
        if lookaheadLabel("from") {
            try expectIdentifier("from")
            try expectSymbol(":")
            let start = try parseScreenPoint()
            try expectSymbol(",")
            if lookaheadLabel("to") {
                try expectIdentifier("to")
                try expectSymbol(":")
                selection = .point(start: .coordinate(start), destination: .coordinate(try parseScreenPoint()))
            } else {
                let direction = try parseEnumCase(SwipeDirection.self, role: "swipe direction")
                selection = .point(start: .coordinate(start), destination: .direction(direction))
            }
        } else {
            let target = try parseConcreteElementTarget()
            try expectSymbol(",")
            if lookaheadLabel("from") {
                try expectIdentifier("from")
                try expectSymbol(":")
                let start = try parseUnitPoint()
                try expectSymbol(",")
                try expectIdentifier("to")
                try expectSymbol(":")
                selection = .unitElement(target, start: start, end: try parseUnitPoint())
            } else {
                selection = .elementDirection(target, try parseEnumCase(SwipeDirection.self, role: "swipe direction"))
            }
        }
        try expectSymbol(")")
        return .mechanicalSwipe(SwipeTarget(selection: selection))
    }

    private mutating func parseMechanicalDrag() throws -> HeistActionCommand {
        try expectSymbol("(")
        let selection: DragGestureSelection
        if lookaheadLabel("from") {
            try expectIdentifier("from")
            try expectSymbol(":")
            let start = try parseScreenPoint()
            try expectSymbol(",")
            try expectIdentifier("to")
            try expectSymbol(":")
            selection = .pointToPoint(start: start, end: try parseScreenPoint())
        } else {
            let target = try parseConcreteElementTarget()
            try expectSymbol(",")
            try expectIdentifier("to")
            try expectSymbol(":")
            selection = .elementToPoint(target, end: try parseScreenPoint())
        }
        try expectSymbol(")")
        return .mechanicalDrag(DragTarget(selection: selection))
    }

    private mutating func parseConcreteElementTarget() throws -> ElementTarget {
        let expr = try parseTargetExpr()
        switch expr {
        case .target(let target):
            return target
        case .predicate(let predicate, let ordinal):
            return .predicate(try concretePredicate(from: predicate), ordinal: ordinal)
        case .ref(let reference):
            throw error(previous, "mechanical actions require a concrete ElementTarget, not target ref '\(reference)'")
        }
    }

    private mutating func parseXYArguments() throws -> ScreenPoint {
        try expectIdentifier("x")
        try expectSymbol(":")
        let x = try parseNumber()
        try expectSymbol(",")
        try expectIdentifier("y")
        try expectSymbol(":")
        let y = try parseNumber()
        return ScreenPoint(x: x, y: y)
    }

    private mutating func parseScreenPoint() throws -> ScreenPoint {
        try expectIdentifier("ScreenPoint")
        try expectSymbol("(")
        let point = try parseXYArguments()
        try expectSymbol(")")
        return point
    }

    private mutating func parseUnitPoint() throws -> UnitPoint {
        try expectIdentifier("UnitPoint")
        try expectSymbol("(")
        let point = try parseXYArguments()
        try expectSymbol(")")
        return UnitPoint(x: point.x, y: point.y)
    }

    private mutating func parseGestureDuration() throws -> GestureDuration {
        try expectIdentifier("GestureDuration")
        try expectSymbol("(")
        try expectIdentifier("seconds")
        try expectSymbol(":")
        let seconds = try parseNumber()
        try expectSymbol(")")
        return GestureDuration(seconds: seconds)
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
            case "withoutExpectation":
                try expectSymbol("(")
                let reason = try parseStringLiteral()
                try expectSymbol(")")
                content = content.withoutExpectation(reason)
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
        if currentToken.isSymbol("{") {
            let body = try parseHeistBlock()
            let elseBody = try parseLowercaseElseChainIfPresent()
            return .waitForCases(try WaitForCasesStep(
                timeout: timeout,
                cases: [
                    PredicateCase(predicate: predicate, body: body),
                ],
                elseBody: elseBody
            ))
        }
        return .wait(WaitStep(predicate: predicate, timeout: timeout))
    }

    private mutating func parseIf() throws -> HeistStep {
        if consumeSymbol("(") {
            throw error(previous, "If(predicate) is not canonical ButtonHeist source. Use If { Case(...) { ... } Else { ... } }")
        }
        let branches = try parsePredicateBranches()
        return .conditional(try ConditionalStep(cases: branches.cases, elseBody: branches.elseBody))
    }

    private mutating func parseForEach() throws -> HeistStep {
        try expectSymbol("(")
        if consumeSymbol("[") {
            let values = try parseStringArrayTail()
            try expectSymbol(")")
            let closure = try parseClosureParameterBlock(binding: .string)
            return .forEachString(try ForEachStringStep(
                values: values,
                parameter: closure.referenceName,
                body: closure.body
            ))
        }

        let matching = try parseElementMatches()
        var limit = 20
        while consumeSymbol(",") {
            if consumeIdentifier("limit") != nil {
                try expectSymbol(":")
                limit = try parseInteger()
            } else {
                throw error(currentToken, "ForEach(.matching(...)) accepts only limit:")
            }
        }
        try expectSymbol(")")
        let closure = try parseClosureParameterBlock(binding: .target)
        return .forEachElement(try ForEachElementStep(
            matching: matching,
            limit: limit,
            parameter: closure.referenceName,
            body: closure.body
        ))
    }

    private mutating func parseElementMatches() throws -> ElementPredicate {
        try expectSymbol(".")
        let name = try parseIdentifier()
        guard name == "matching" else {
            throw error(previous, "expected .matching(...)")
        }
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
        let body = try parseHeistBody(untilRightBrace: true, allowDefinitions: false)
        return body.steps
    }

    private mutating func parseLowercaseElseChainIfPresent() throws -> [HeistStep]? {
        guard consumeSymbol(".") else { return nil }
        let token = currentToken
        let chain = try parseIdentifier()
        guard chain == "else" else {
            throw error(token, "unsupported WaitFor chain '.\(chain)'")
        }
        return try parseHeistBlock()
    }

    private mutating func parseClosureParameterBlock(
        binding: HeistPlanSourceBinding
    ) throws -> (referenceName: String, body: [HeistStep]) {
        try expectSymbol("{")
        let localName = try parseIdentifier()
        try expectIdentifier("in")
        let referenceName = localName
        let previousScope = scope
        switch binding {
        case .string:
            scope.stringRefs[localName] = referenceName
        case .target:
            scope.targetRefs[localName] = referenceName
        }
        let body = try parseHeistBody(untilRightBrace: true, allowDefinitions: false)
        scope = previousScope
        return (referenceName, body.steps)
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
                traits = try parseTraitArray(role: "traits")
            } else if consumeIdentifier("excludeTraits") != nil {
                try expectSymbol(":")
                excludeTraits = try parseTraitArray(role: "excludeTraits")
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

    private mutating func parseTraitArray(role: String) throws -> [HeistTrait] {
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
        if currentTokenIsIdentifier, nextTokenIsSymbol("(") {
            throw error(
                currentToken,
                "arbitrary calls are not supported inside ButtonHeist DSL bodies; wrap the heist in Swift and pass values through parameters or RunHeist"
            )
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
        var sign = 1.0
        let signToken = currentToken
        if consumeSymbol("-") {
            sign = -1.0
        }
        guard case .number(let text) = currentToken.kind else {
            if sign < 0 {
                throw error(signToken, "expected a number after '-'")
            }
            return nil
        }
        guard let value = Double(text) else {
            throw error(currentToken, "invalid number '\(text)'")
        }
        advance()
        return sign * value
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
                    throw error(token, "unsupported ButtonHeist source type prefix '\(prefix)'")
                }
                return try parseIdentifier()
            }
            guard allowedPrefixes.contains(prefix) else {
                throw error(token, "unsupported ButtonHeist source type prefix '\(prefix)'")
            }
            return second
        }
        throw error(token, "expected a ButtonHeist expression beginning with '.'")
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

    private mutating func parseTryPrefixIfPresent() throws -> HeistTryPrefix? {
        guard let token = consumeIdentifier("try") else { return nil }
        let forced = consumeSymbol("!")
        return HeistTryPrefix(token: token, forced: forced)
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

    private func nextTokenIsIdentifier(_ name: String) -> Bool {
        guard tokens.indices.contains(index + 1),
              case .identifier(name) = tokens[index + 1].kind else {
            return false
        }
        return true
    }

    private func nextTokenIsSymbol(_ symbol: Character) -> Bool {
        guard tokens.indices.contains(index + 1) else { return false }
        return tokens[index + 1].isSymbol(symbol)
    }

    private func tokenIsIdentifier(_ token: HeistPlanSourceToken, _ name: String) -> Bool {
        guard case .identifier(name) = token.kind else { return false }
        return true
    }

    private func lookaheadIdentifier(_ offset: Int, _ name: String) -> Bool {
        guard tokens.indices.contains(index + offset),
              case .identifier(name) = tokens[index + offset].kind else {
            return false
        }
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

    private var startsRootHeistPlan: Bool {
        tokenIsIdentifier(currentToken, "HeistPlan")
    }

    private var startsDefinition: Bool {
        tokenIsIdentifier(currentToken, "HeistDef")
    }

    private var atEnd: Bool {
        currentToken.kind == .eof
    }

    private var currentTokenIsIdentifier: Bool {
        if case .identifier = currentToken.kind { return true }
        return false
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
            throw error(currentToken, "import declarations are not supported in ButtonHeist source")
        case "let", "var":
            throw error(
                currentToken,
                "\(name) declarations are not supported inside ButtonHeist DSL bodies; wrap the heist in Swift and pass values through parameters or RunHeist"
            )
        case "func":
            throw error(currentToken, "function declarations are not supported in ButtonHeist source")
        case "class", "struct", "protocol", "extension", "actor":
            throw error(currentToken, "type declarations are not supported in ButtonHeist source")
        case "enum":
            throw error(currentToken, "enum declarations are Swift wrapper code, not ButtonHeist DSL body syntax")
        case "if":
            throw error(currentToken, "native Swift if/else is not supported inside ButtonHeist DSL bodies. Use If { Case(...) { ... } Else { ... } }")
        case "for", "while", "switch":
            throw error(currentToken, "native Swift \(name) statements are not supported; use ButtonHeist constructs such as If, WaitFor, and ForEach")
        case "try":
            if let correction = runHeistCorrectionAfterTryPrefix(startingAt: index + 1) {
                throw error(
                    currentToken,
                    "`try` is only allowed in Swift wrapper code, not inside ButtonHeist DSL bodies. Use \(correction)."
                )
            }
            throw error(currentToken, "`try` is only allowed in Swift wrapper code, not inside ButtonHeist DSL bodies")
        case "await":
            throw error(currentToken, "`await` is not supported in ButtonHeist source")
        default:
            return
        }
    }

    private func runHeistCorrectionAfterTryPrefix(startingAt startIndex: Int) -> String? {
        guard tokens.indices.contains(startIndex),
              case .identifier(let first) = tokens[startIndex].kind else {
            return nil
        }
        var names = [first]
        var cursor = startIndex + 1
        while tokens.indices.contains(cursor), tokens[cursor].isSymbol(".") {
            let nameIndex = cursor + 1
            guard tokens.indices.contains(nameIndex),
                  case .identifier(let name) = tokens[nameIndex].kind else {
                return nil
            }
            names.append(name)
            cursor = nameIndex + 1
        }
        guard names.count > 1,
              tokens.indices.contains(cursor),
              tokens[cursor].isSymbol("(") else {
            return nil
        }
        return "RunHeist(\(quote(names.joined(separator: "."))))"
    }

    private func quote(_ value: String) -> String {
        if let data = try? JSONEncoder().encode(value),
           let encoded = String(data: data, encoding: .utf8) {
            return encoded
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
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

private struct ParsedHeistBody {
    let definitions: [UnvalidatedHeistPlan]
    let steps: [HeistStep]
}

private struct HeistTryPrefix {
    let token: HeistPlanSourceToken
    let forced: Bool
}

private struct HeistPlanSourceScope: Equatable {
    var stringRefs: [String: String] = [:]
    var targetRefs: [String: String] = [:]
}

private enum HeistPlanSourceBinding {
    case string
    case target
}

private enum HeistDefinitionParameterKind {
    case none
    case string
    case elementTarget
}
