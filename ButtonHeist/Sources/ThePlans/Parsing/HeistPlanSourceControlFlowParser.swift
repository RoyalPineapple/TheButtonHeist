import Foundation

struct ParsedPredicateBranches {
    let cases: [HeistPredicateCaseAdmissionCandidate]
    let elseBody: [HeistStepAdmissionCandidate]?
}

struct ParsedClosureParameterBlock {
    let referenceName: HeistReferenceName
    let body: [HeistStepAdmissionCandidate]
}

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
            let branches = try parseSinglePredicateBranches(predicate: predicate, chainContext: "If")
            return .conditional(try HeistConditionalAdmissionCandidate(
                cases: branches.cases,
                elseBody: branches.elseBody
            ))
        }
        let branches = try parsePredicateBranches()
        return .conditional(try HeistConditionalAdmissionCandidate(
            cases: branches.cases,
            elseBody: branches.elseBody
        ))
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
            let closure = try parseClosureParameterBlock(binding: .string)
            return .forEachString(try HeistForEachStringAdmissionCandidate(
                values: values,
                parameter: closure.referenceName,
                body: closure.body
            ))
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
        let closure = try parseClosureParameterBlock(binding: .target)
        return .forEachElement(try HeistForEachElementAdmissionCandidate(
            matching: matching,
            limit: limit,
            parameter: closure.referenceName,
            body: closure.body
        ))
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
            body: body,
            elseBody: try parseLowercaseElseChainIfPresent(chainContext: "RepeatUntil")
        ))
    }

    mutating func parseElementLoopPredicate() throws -> ElementPredicateTemplate {
        try expectSymbol(".")
        let name = try parseIdentifier()
        if name == "matching" {
            throw error(previous, #"ForEach element loops use direct predicates like `ForEach(.label("x"))`, not `.matching(...)`"#)
        }
        return try parseElementPredicateTemplate(named: name)
    }

    mutating func parseRunHeist() throws -> HeistStep {
        try expectSymbol("(")
        let nameToken = currentToken
        let name = try parseStringLiteral()
        let invocationPath: HeistInvocationPath
        do {
            invocationPath = try HeistInvocationPath(validating: name)
        } catch let validationError {
            throw HeistPlanSourceCompilerError(diagnostic: .invalidInvocationPath(
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
        var invocation = HeistInvocationStep(
            path: invocationPath,
            argument: argument
        )
        var explicitExpectationTimeout: WaitTimeout?
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
                let timeoutResult = composeExpectationTimeout(
                    existing: invocation.expectation,
                    existingExplicit: explicitExpectationTimeout,
                    nextExplicit: timeout
                )
                let predicateResult = invocation.expectation.map {
                    composeExpectationPredicates(existing: $0.predicate, next: predicate)
                } ?? ExpectationPredicateComposition(predicate: predicate, diagnostics: [])
                if let diagnostic = (predicateResult.diagnostics + timeoutResult.diagnostics).first {
                    throw error(chainToken, diagnostic.message)
                }
                invocation = HeistInvocationStep(
                    path: invocation.path,
                    argument: invocation.argument,
                    expectation: WaitStep(predicate: predicateResult.predicate, timeout: timeoutResult.timeout)
                )
                explicitExpectationTimeout = timeoutResult.explicitTimeout
            default:
                throw error(chainToken, "unsupported RunHeist chain '.\(chain)'")
            }
        }
        return .invoke(invocation)
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

    mutating func parsePredicateBranches() throws -> ParsedPredicateBranches {
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
        return ParsedPredicateBranches(cases: cases, elseBody: elseBody)
    }

    mutating func parseSinglePredicateBranches(
        predicate: ChangeDeclaration.ScreenAssertion,
        chainContext: String
    ) throws -> ParsedPredicateBranches {
        let body = try parseHeistBlock()
        let elseBody = try parseLowercaseElseChainIfPresent(chainContext: chainContext)
        return ParsedPredicateBranches(
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

    mutating func parseClosureParameterBlock(
        binding: HeistPlanSourceBinding
    ) throws -> ParsedClosureParameterBlock {
        try expectSymbol("{")
        let localName = try parseIdentifier()
        try expectIdentifier("in")
        let referenceName = try HeistReferenceName(validating: localName)
        let previousScope = currentScope()
        defer { restoreScope(previousScope) }
        bindScopedReference(binding, localName: localName, referenceName: referenceName)
        let body = try parseHeistBody(untilRightBrace: true, allowDefinitions: false)
        return ParsedClosureParameterBlock(
            referenceName: referenceName,
            body: body.steps
        )
    }

}
