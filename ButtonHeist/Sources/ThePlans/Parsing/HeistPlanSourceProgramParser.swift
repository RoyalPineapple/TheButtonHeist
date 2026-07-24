import Foundation

extension HeistPlanSourceParser {
    mutating func parseRootHeistPlan() throws -> HeistPlan {
        let name = try parseCalleeName()
        guard name == ["HeistPlan"] else {
            throw error(previous, "expected `HeistPlan { ... }`")
        }
        return try parseHeistPlanAfterCallee(allowDefinitions: true)
    }

    mutating func parseHeistBody(
        untilRightBrace: Bool,
        allowDefinitions: Bool
    ) throws -> ParsedHeistBody {
        var definitions: [HeistPlan] = []
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

    mutating func parseDefinition() throws -> HeistPlan {
        let callee = try parseCalleeName()
        switch callee {
        case ["HeistDef"]:
            return try parseHeistDef(parameterKind: try parseHeistDefGeneric())
        case ["Namespace"]:
            return try parseNamespaceDefinition()
        default:
            throw error(previous, "heist definitions must use `HeistDef<...>(\"Name\") { ... }` or `Namespace(\"Name\") { ... }`")
        }
    }

    mutating func parseNamespaceDefinition() throws -> HeistPlan {
        try expectSymbol("(")
        let nameToken = currentToken
        let name = try parseStringLiteral()
        try expectSymbol(")")
        let body = try parseHeistClosureBody(parameter: .none, allowDefinitions: true)
        guard body.steps.isEmpty else {
            throw error(previous, "Namespace blocks may contain HeistDef or Namespace declarations only")
        }
        return try HeistPlan(
            structuralVersion: HeistPlan.currentVersion,
            name: try parsePlanName(name, token: nameToken),
            parameter: .none,
            definitions: mergeDefinitions(body.definitions),
            body: []
        )
    }

    mutating func parseHeistDefGeneric() throws -> HeistParameterKind {
        try expectSymbol("<")
        let type = try parseIdentifier()
        try expectSymbol(">")
        switch type {
        case "Void":
            return .none
        case "String":
            return .string
        case "AccessibilityTarget":
            return .accessibilityTarget
        default:
            throw error(previous, "unsupported HeistDef parameter type '\(type)'")
        }
    }

    fileprivate mutating func parseHeistDef(
        parameterKind: HeistParameterKind
    ) throws -> HeistPlan {
        try expectSymbol("(")
        let pathToken = currentToken
        let path = try parseStringLiteral()
        var parameter = HeistParameter.none
        if consumeSymbol(",") {
            try expectIdentifier("parameter")
            try expectSymbol(":")
            let parameterName = try parseReferenceNameLiteral(role: "parameter")
            switch parameterKind {
            case .none:
                throw error(previous, "HeistDef<Void> must not declare parameter:")
            case .string:
                parameter = .string(name: parameterName)
            case .accessibilityTarget:
                parameter = .accessibilityTarget(name: parameterName)
            }
        }
        try expectSymbol(")")

        switch (parameterKind, parameter) {
        case (.none, .none), (.string, .string), (.accessibilityTarget, .accessibilityTarget):
            break
        case (.string, .none):
            throw error(previous, "HeistDef<String> must declare `parameter: \"name\"`")
        case (.accessibilityTarget, .none):
            throw error(previous, "HeistDef<AccessibilityTarget> must declare `parameter: \"name\"`")
        default:
            throw error(previous, "HeistDef parameter type does not match its parameter declaration")
        }
        let definitionPath: HeistDefinitionPath
        do {
            definitionPath = try HeistDefinitionPath(validating: path)
        } catch {
            throw HeistSourceCompilationError(diagnostic: .invalidDefinitionPath(
                path,
                error: error,
                phase: .sourceCompilation,
                sourceSpan: sourceSpan(for: pathToken)
            ))
        }
        let body = try parseHeistClosureBody(parameter: parameter, allowDefinitions: true)
        return try HeistPlan.nestedDefinition(
            path: definitionPath,
            parameter: parameter,
            definitions: mergeDefinitions(body.definitions),
            body: body.steps
        )
    }

    func mergeDefinitions(_ definitions: [HeistPlan]) -> [HeistPlan] {
        HeistPlan.mergeDefinitions(definitions, duplicatePolicy: .preserve)
    }

    mutating func parseStatement() throws -> [HeistStep] {
        let tryPrefix = try parseTryPrefixIfPresent()
        if let tryPrefix {
            if let correction = runHeistCorrectionAfterTryPrefix(startingAt: index) {
                throw error(
                    tryPrefix,
                    "`try` is only allowed in Swift wrapper code, not inside ButtonHeist DSL bodies. Use \(correction)."
                )
            }
            throw error(tryPrefix, "`try` is only allowed in Swift wrapper code, not inside ButtonHeist DSL bodies")
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
        case ["ClearText"]:
            return [try parseActionStep(command: parseClearTextAction())]
        case ["CustomAction"]:
            return [try parseActionStep(command: parseCustomAction())]
        case ["Rotor"]:
            return [try parseActionStep(command: parseRotorAction())]
        case ["SetPasteboard"]:
            return [try parseActionStep(command: parseSetPasteboardAction())]
        case ["TakeScreenshot"]:
            return [try parseActionStep(command: parseTakeScreenshotAction())]
        case ["ScreenActions", "Dismiss"]:
            return [try parseActionStep(command: parseDismissAction())]
        case ["ScreenActions", "MagicTap"]:
            return [try parseActionStep(command: parseMagicTapAction())]
        case ["Edit"]:
            return [try parseActionStep(command: parseEditAction())]
        case ["dismissKeyboard"]:
            return [try parseActionStep(command: parseDismissKeyboardAction())]
        case ["oneFingerTap"]:
            return [try parseActionStep(command: parseOneFingerTap())]
        case ["longPress"]:
            return [try parseActionStep(command: parseLongPress())]
        case ["swipe"]:
            return [try parseActionStep(command: parseSwipe())]
        case ["drag"]:
            return [try parseActionStep(command: parseDrag())]
        case ["WaitFor"]:
            return [try parseWaitFor()]
        case ["If"]:
            return [try parseIf()]
        case ["ForEach"]:
            return [try parseForEach()]
        case ["RepeatUntil"]:
            return [try parseRepeatUntil()]
        case ["HeistPlan"]:
            let plan = try parseHeistPlanAfterCallee(allowDefinitions: false)
            return [.heist(plan)]
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

    mutating func parseHeistPlanAfterCallee(allowDefinitions: Bool) throws -> HeistPlan {
        var name: HeistPlanName?
        var parameter = HeistParameter.none
        if consumeSymbol("(") {
            if currentToken.isSymbol(")") {
                throw error(currentToken, "empty HeistPlan parentheses are not canonical; use `HeistPlan { ... }`")
            }

            if lookaheadLabel("parameter") || lookaheadLabel("targetParameter") {
                parameter = try parseRootHeistParameter()
            } else {
                let nameToken = currentToken
                name = try parsePlanName(parseStringLiteral(), token: nameToken)
                if consumeSymbol(",") {
                    parameter = try parseRootHeistParameter()
                }
            }
            try expectSymbol(")")
        }

        let body = try parseHeistClosureBody(parameter: parameter, allowDefinitions: allowDefinitions)
        return try HeistPlan(
            structuralVersion: HeistPlan.currentVersion,
            name: name,
            parameter: parameter,
            definitions: mergeDefinitions(body.definitions),
            body: body.steps
        )
    }

    func parsePlanName(_ value: String, token: HeistPlanSourceToken) throws -> HeistPlanName {
        do {
            return try HeistPlanName(validating: value)
        } catch {
            throw self.error(token, String(describing: error))
        }
    }

    mutating func parseRootHeistParameter() throws -> HeistParameter {
        if consumeIdentifier("parameter") != nil {
            try expectSymbol(":")
            return .string(name: try parseReferenceNameLiteral(role: "parameter"))
        }
        if consumeIdentifier("targetParameter") != nil {
            try expectSymbol(":")
            return .accessibilityTarget(name: try parseReferenceNameLiteral(role: "targetParameter"))
        }
        throw error(currentToken, "expected parameter: or targetParameter:")
    }

    mutating func parseHeistClosureBody(
        parameter: HeistParameter,
        allowDefinitions: Bool
    ) throws -> ParsedHeistBody {
        try expectSymbol("{")
        let previousScope = currentScope()
        defer { restoreScope(previousScope) }
        if parameter.name != nil {
            let localName = try parseIdentifier()
            try expectIdentifier("in")
            bindScopedParameter(parameter, localName: localName)
        }
        return try parseHeistBody(untilRightBrace: true, allowDefinitions: allowDefinitions)
    }

}
