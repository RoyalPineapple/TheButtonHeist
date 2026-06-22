import Foundation

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

    mutating func parseDefinition() throws -> HeistPlanAdmissionCandidate {
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

    mutating func parseHeistDefGeneric() throws -> HeistDefinitionParameterKind {
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

    mutating func parseHeistDefHeader(
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

    func makeDefinition(
        path: [String],
        parameter: HeistParameter,
        definitions: [HeistPlanAdmissionCandidate],
        body: [HeistStep]
    ) -> HeistPlanAdmissionCandidate {
        guard let first = path.first else {
            return HeistPlanAdmissionCandidate(parameter: parameter, definitions: definitions, body: body)
        }
        guard path.count > 1 else {
            return HeistPlanAdmissionCandidate(name: first, parameter: parameter, definitions: definitions, body: body)
        }
        return HeistPlanAdmissionCandidate(
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

    func mergeDefinitions(_ definitions: [HeistPlanAdmissionCandidate]) -> [HeistPlanAdmissionCandidate] {
        var merged: [HeistPlanAdmissionCandidate] = []
        for definition in definitions {
            guard let name = definition.name,
                  let existingIndex = merged.firstIndex(where: { $0.name == name }) else {
                merged.append(definition)
                continue
            }
            let existing = merged[existingIndex]
            if isNamespace(existing), isNamespace(definition) {
                merged[existingIndex] = HeistPlanAdmissionCandidate(
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

    func isNamespace(_ definition: HeistPlanAdmissionCandidate) -> Bool {
        definition.parameter == .none && definition.body.isEmpty && !definition.definitions.isEmpty
    }

    mutating func parseStatement() throws -> [HeistStep] {
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
            return [.heist(plan.uncheckedPlanForRuntimeSafetyValidation())]
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

    mutating func parseHeistPlanHeader() throws -> (name: String?, parameter: HeistParameter) {
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

    mutating func parseRootHeistParameter() throws -> HeistParameter {
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
