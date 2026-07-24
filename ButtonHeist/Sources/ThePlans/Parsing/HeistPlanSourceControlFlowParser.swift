import Foundation

extension HeistPlanSourceParser {
    mutating func parseWaitFor() throws -> HeistStepAdmissionCandidate {
        try expectSymbol("(")
        let predicate = try parseAccessibilityPredicateExpr()
        let timeout = try parseTrailingTimeout(defaultValue: defaultWaitTimeout) ?? defaultWaitTimeout
        try expectSymbol(")")
        return .wait(HeistWaitAdmissionCandidate(
            predicate: predicate,
            timeout: timeout,
            elseBody: try parseLowercaseElseChainIfPresent(chainContext: "WaitFor")
        ))
    }

    mutating func parseIf() throws -> HeistStepAdmissionCandidate {
        if consumeSymbol("(") {
            let predicate = try parseScreenAssertion()
            try expectSymbol(")")
            return .conditional(try parseSinglePredicateBranches(predicate: predicate, chainContext: "If"))
        }
        return .conditional(try parsePredicateBranches())
    }

    mutating func parseForEach() throws -> HeistStepAdmissionCandidate {
        try expectSymbol("(")
        if consumeSymbol("[") {
            throw error(previous, #"ForEach string loops use `ForEach("a", "b")`, not array literals"#)
        }
        if case .string = currentToken.kind {
            var values: [String] = []
            repeat {
                values.append(try parseStringLiteral())
            } while consumeSymbol(",")
            try expectSymbol(")")
            return try parseScopedClosure(binding: .string) { parameter, body in
                .forEachString(try HeistForEachStringAdmissionCandidate(
                    values: values,
                    parameter: parameter,
                    body: body
                ))
            }
        }
        let matching = try parseElementLoopPredicate()
        var limit = 20
        while consumeSymbol(",") {
            if consumeIdentifier("limit") != nil {
                try expectSymbol(":")
                limit = try parseInteger()
            } else {
                throw error(currentToken, "ForEach element loop accepts only limit:")
            }
        }
        try expectSymbol(")")
        return try parseScopedClosure(binding: .target) { parameter, body in
            .forEachElement(try HeistForEachElementAdmissionCandidate(
                matching: matching,
                limit: limit,
                parameter: parameter,
                body: body
            ))
        }
    }

    mutating func parseRepeatUntil() throws -> HeistStepAdmissionCandidate {
        try expectSymbol("(")
        let predicate = try parseAccessibilityPredicateExpr()
        guard let timeout = try parseTrailingTimeout(defaultValue: nil) else {
            throw error(currentToken, "RepeatUntil requires timeout in seconds")
        }
        try expectSymbol(")")
        let body = try parseHeistBlock()
        return .repeatUntil(try HeistRepeatUntilAdmissionCandidate(
            predicate: predicate,
            timeout: timeout,
            body: body
        ))
    }

    mutating func parseElementLoopPredicate() throws -> ElementPredicate {
        try expectSymbol(".")
        let name = try parseIdentifier()
        if name == "matching" {
            throw error(previous, #"ForEach element loops use direct predicates like `ForEach(.label("x"))`, not `.matching(...)`"#)
        }
        return try parseElementPredicate(named: name)
    }

    mutating func parseRunHeist() throws -> HeistStep {
        try expectSymbol("(")
        let nameToken = currentToken
        let name = try parseStringLiteral()
        let invocationPath: HeistInvocationPath
        do {
            invocationPath = try HeistInvocationPath(validating: name)
        } catch let validationError {
            throw HeistSourceCompilationError(diagnostic: .invalidInvocationPath(
                name,
                error: validationError,
                phase: .sourceCompilation,
                sourceSpan: sourceSpan(for: nameToken)
            ))
        }
        var argument = HeistArgument.none
        if consumeSymbol(",") {
            argument = try parseHeistArgument()
        }
        try expectSymbol(")")
        var expectation: ComposedExpectation?
        while consumeSymbol(".") {
            let chainToken = currentToken
            let chain = try parseIdentifier()
            switch chain {
            case "expect":
                try expectSymbol("(")
                let predicate: AccessibilityPredicate
                let timeout: WaitTimeout?
                if currentToken.isSymbol(")") {
                    throw error(currentToken, ".expect(...) requires a canonical predicate")
                } else {
                    predicate = try parseAccessibilityPredicateExpr()
                    timeout = try parseTrailingTimeout(defaultValue: nil)
                }
                try expectSymbol(")")
                let composition = composeExpectation(
                    existing: expectation,
                    nextPredicate: predicate,
                    nextExplicit: timeout
                )
                if let diagnostic = composition.diagnostics.first {
                    throw error(chainToken, diagnostic.message)
                }
                expectation = composition.expectation
            default:
                throw error(chainToken, "unsupported RunHeist chain '.\(chain)'")
            }
        }
        return .invoke(HeistInvocationStep(
            path: invocationPath,
            argument: argument,
            expectation: expectation?.step
        ))
    }

    mutating func parseHeistArgument() throws -> HeistArgument {
        if let string = try parseStringExprIfPresent() {
            return HeistArgument(core: .string(string))
        }
        return .accessibilityTarget(try parseTargetExpr())
    }

    mutating func parseWarn() throws -> HeistStep {
        try expectSymbol("(")
        let messageToken = currentToken
        let message = try parseStringLiteral()
        try expectSymbol(")")
        do {
            return .warn(WarnStep(message: try HeistWarningMessage(validating: message)))
        } catch let validationError {
            throw error(messageToken, String(describing: validationError))
        }
    }

    mutating func parseFail() throws -> HeistStep {
        try expectSymbol("(")
        let messageToken = currentToken
        let message = try parseStringLiteral()
        try expectSymbol(")")
        do {
            return .fail(FailStep(message: try HeistFailureMessage(validating: message)))
        } catch let validationError {
            throw error(messageToken, String(describing: validationError))
        }
    }

    mutating func parsePredicateBranches() throws -> HeistConditionalAdmissionCandidate {
        try expectSymbol("{")
        var cases: [HeistPredicateCaseAdmissionCandidate] = []
        var elseBody: [HeistStepAdmissionCandidate]?
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
                let predicate = try parseScreenAssertion()
                try expectSymbol(")")
                cases.append(HeistPredicateCaseAdmissionCandidate(
                    predicate: predicate,
                    body: try parseHeistBlock()
                ))
            case "Else":
                guard elseBody == nil else {
                    throw error(token, "a branch block accepts at most one Else")
                }
                elseBody = try parseHeistBlock()
            default:
                throw error(token, "branch blocks accept only Case(...) and Else")
            }
        }
        return try HeistConditionalAdmissionCandidate(cases: cases, elseBody: elseBody)
    }

    mutating func parseSinglePredicateBranches(
        predicate: ChangeDeclaration.ScreenAssertion,
        chainContext: String
    ) throws -> HeistConditionalAdmissionCandidate {
        let body = try parseHeistBlock()
        let elseBody = try parseLowercaseElseChainIfPresent(chainContext: chainContext)
        return try HeistConditionalAdmissionCandidate(
            cases: [HeistPredicateCaseAdmissionCandidate(predicate: predicate, body: body)],
            elseBody: elseBody
        )
    }

    mutating func parseHeistBlock() throws -> [HeistStepAdmissionCandidate] {
        try expectSymbol("{")
        let body = try parseHeistBody(untilRightBrace: true, allowDefinitions: false)
        return body.steps
    }

    mutating func parseLowercaseElseChainIfPresent(
        chainContext: String
    ) throws -> [HeistStepAdmissionCandidate]? {
        guard consumeSymbol(".") else { return nil }
        let token = currentToken
        let chain = try parseIdentifier()
        guard chain == "else" else {
            throw error(token, "unsupported \(chainContext) chain '.\(chain)'")
        }
        return try parseHeistBlock()
    }

    fileprivate mutating func parseScopedClosure<Value>(
        binding: HeistPlanSourceBinding,
        project: (HeistReferenceName, [HeistStepAdmissionCandidate]) throws -> Value
    ) throws -> Value {
        try expectSymbol("{")
        let localName = try parseIdentifier()
        try expectIdentifier("in")
        let referenceName = try HeistReferenceName(validating: localName)
        let previousScope = currentScope()
        defer { restoreScope(previousScope) }
        bindScopedReference(binding, localName: localName, referenceName: referenceName)
        let body = try parseHeistBody(untilRightBrace: true, allowDefinitions: false)
        return try project(referenceName, body.steps)
    }

}
