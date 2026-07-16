import Foundation

struct HeistDefinitionHeader {
    let path: HeistDefinitionPath
    let parameter: HeistParameter
}

struct HeistPlanHeader {
    let name: HeistPlanName?
    let parameter: HeistParameter
}

extension HeistPlanSourceParser {
    mutating func parseRootHeistPlan() throws -> HeistPlanAdmissionCandidate {
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
        var definitions: [HeistPlanAdmissionCandidate] = []
        var steps: [HeistStepAdmissionCandidate] = []
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

    mutating func parseDefinition() throws -> HeistPlanAdmissionCandidate {
        let callee = try parseCalleeName()
        switch callee {
        case ["HeistDef"]:
            let parameterKind = try parseHeistDefGeneric()
            let header = try parseHeistDefHeader(parameterKind: parameterKind)
            let body = try parseHeistClosureBody(parameter: header.parameter, allowDefinitions: true)
            return makeDefinition(
                components: header.path.components[...],
                parameter: header.parameter,
                definitions: mergeDefinitions(body.definitions),
                body: body.steps
            )
        case ["Namespace"]:
            return try parseNamespaceDefinition()
        default:
            throw error(previous, "heist definitions must use `HeistDef<...>(\"Name\") { ... }` or `Namespace(\"Name\") { ... }`")
        }
    }

    mutating func parseNamespaceDefinition() throws -> HeistPlanAdmissionCandidate {
        try expectSymbol("(")
        let nameToken = currentToken
        let name = try parseStringLiteral()
        try expectSymbol(")")
        let body = try parseHeistClosureBody(parameter: .none, allowDefinitions: true)
        guard body.steps.isEmpty else {
            throw error(previous, "Namespace blocks may contain HeistDef or Namespace declarations only")
        }
        return HeistPlanAdmissionCandidate(
            name: try parsePlanName(name, token: nameToken),
            parameter: .none,
            definitions: mergeDefinitions(body.definitions),
            body: []
        )
    }

    mutating func parseHeistDefGeneric() throws -> HeistDefinitionParameterKind {
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

    mutating func parseHeistDefHeader(
        parameterKind: HeistDefinitionParameterKind
    ) throws -> HeistDefinitionHeader {
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
            throw HeistPlanSourceCompilerError(diagnostic: .invalidDefinitionPath(
                path,
                error: error,
                phase: .sourceCompilation,
                sourceSpan: sourceSpan(for: pathToken)
            ))
        }
        return HeistDefinitionHeader(path: definitionPath, parameter: parameter)
    }

    func makeDefinition(
        components: ArraySlice<HeistPlanName>,
        parameter: HeistParameter,
        definitions: [HeistPlanAdmissionCandidate],
        body: [HeistStepAdmissionCandidate]
    ) -> HeistPlanAdmissionCandidate {
        guard let first = components.first else {
            preconditionFailure("validated heist definition path must not be empty")
        }
        guard components.count > 1 else {
            return HeistPlanAdmissionCandidate(name: first, parameter: parameter, definitions: definitions, body: body)
        }
        return HeistPlanAdmissionCandidate(
            name: first,
            definitions: [
                makeDefinition(
                    components: components.dropFirst(),
                    parameter: parameter,
                    definitions: definitions,
                    body: body
                ),
            ],
            body: []
        )
    }

    func mergeDefinitions(_ definitions: [HeistPlanAdmissionCandidate]) -> [HeistPlanAdmissionCandidate] {
        HeistDefinitionMerger.merge(definitions, duplicatePolicy: .preserve)
    }

    mutating func parseStatement() throws -> [HeistStepAdmissionCandidate] {
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
            return [HeistStepAdmissionCandidate(try parseActionStep(command: parseElementTargetAction("Activate", makeCommand: HeistActionCommand.activate)))]
        case ["Increment"]:
            return [HeistStepAdmissionCandidate(try parseActionStep(command: parseElementTargetAction("Increment", makeCommand: HeistActionCommand.increment)))]
        case ["Decrement"]:
            return [HeistStepAdmissionCandidate(try parseActionStep(command: parseElementTargetAction("Decrement", makeCommand: HeistActionCommand.decrement)))]
        case ["TypeText"]:
            return [HeistStepAdmissionCandidate(try parseActionStep(command: parseTypeTextAction()))]
        case ["ClearText"]:
            return [HeistStepAdmissionCandidate(try parseActionStep(command: parseClearTextAction()))]
        case ["CustomAction"]:
            return [HeistStepAdmissionCandidate(try parseActionStep(command: parseCustomAction()))]
        case ["Rotor"]:
            return [HeistStepAdmissionCandidate(try parseActionStep(command: parseRotorAction()))]
        case ["SetPasteboard"]:
            return [HeistStepAdmissionCandidate(try parseActionStep(command: parseSetPasteboardAction()))]
        case ["TakeScreenshot"]:
            return [HeistStepAdmissionCandidate(try parseActionStep(command: parseTakeScreenshotAction()))]
        case ["ScreenActions", "Dismiss"]:
            return [HeistStepAdmissionCandidate(try parseActionStep(command: parseDismissAction()))]
        case ["ScreenActions", "MagicTap"]:
            return [HeistStepAdmissionCandidate(try parseActionStep(command: parseMagicTapAction()))]
        case ["Edit"]:
            return [HeistStepAdmissionCandidate(try parseActionStep(command: parseEditAction()))]
        case ["DismissKeyboard"]:
            return [HeistStepAdmissionCandidate(try parseActionStep(command: parseDismissKeyboardAction()))]
        case ["Mechanical", "Tap"]:
            return [HeistStepAdmissionCandidate(try parseActionStep(command: parseMechanicalTap()))]
        case ["Mechanical", "LongPress"]:
            return [HeistStepAdmissionCandidate(try parseActionStep(command: parseMechanicalLongPress()))]
        case ["Mechanical", "Swipe"]:
            return [HeistStepAdmissionCandidate(try parseActionStep(command: parseMechanicalSwipe()))]
        case ["Mechanical", "Drag"]:
            return [HeistStepAdmissionCandidate(try parseActionStep(command: parseMechanicalDrag()))]
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
            return [HeistStepAdmissionCandidate(try parseRunHeist())]
        case ["Warn"]:
            return [HeistStepAdmissionCandidate(try parseWarn())]
        case ["Fail"]:
            return [HeistStepAdmissionCandidate(try parseFail())]
        default:
            throw error(previous, "unsupported ButtonHeist source statement '\(name.joined(separator: "."))'")
        }
    }

    mutating func parseHeistPlanAfterCallee(allowDefinitions: Bool) throws -> HeistPlanAdmissionCandidate {
        let header = try parseHeistPlanHeader()
        let body = try parseHeistClosureBody(parameter: header.parameter, allowDefinitions: allowDefinitions)
        return HeistPlanAdmissionCandidate(
            version: HeistPlan.currentVersion,
            name: header.name,
            parameter: header.parameter,
            definitions: mergeDefinitions(body.definitions),
            body: body.steps
        )
    }

    mutating func parseHeistPlanHeader() throws -> HeistPlanHeader {
        var name: HeistPlanName?
        var parameter = HeistParameter.none
        guard consumeSymbol("(") else {
            return HeistPlanHeader(name: nil, parameter: .none)
        }
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
        return HeistPlanHeader(name: name, parameter: parameter)
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
