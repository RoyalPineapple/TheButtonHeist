import Foundation

extension HeistPlanSourceParser {
    mutating func parseWaitFor() throws -> HeistStep {
        try expectSymbol("(")
        let predicate = try parseAccessibilityPredicateExpr()
        let timeout = try parseTrailingTimeout(defaultValue: defaultWaitTimeout) ?? defaultWaitTimeout
        try expectSymbol(")")
        return .wait(WaitStep(
            predicate: predicate,
            timeout: timeout,
            elseBody: try parseLowercaseElseChainIfPresent(chainContext: "WaitFor")
        ))
    }

    mutating func parseIf() throws -> HeistStep {
        if consumeSymbol("(") {
            let predicate = try parseAccessibilityPredicateExpr()
            try expectSymbol(")")
            let branches = try parseSinglePredicateBranches(predicate: predicate, chainContext: "If")
            return .conditional(try ConditionalStep(cases: branches.cases, elseBody: branches.elseBody))
        }
        let branches = try parsePredicateBranches()
        return .conditional(try ConditionalStep(cases: branches.cases, elseBody: branches.elseBody))
    }

    mutating func parseForEach() throws -> HeistStep {
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
        if case .string = currentToken.kind {
            var values: [String] = []
            repeat {
                values.append(try parseStringLiteral())
            } while consumeSymbol(",")
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
                throw error(currentToken, "ForEach element loop accepts only limit:")
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

    mutating func parseRepeatUntil() throws -> HeistStep {
        try expectSymbol("(")
        let predicate = try parseAccessibilityPredicateExpr()
        guard let timeout = try parseTrailingTimeout(defaultValue: nil) else {
            throw error(currentToken, "RepeatUntil requires timeout: .seconds(...)")
        }
        try expectSymbol(")")
        let body = try parseHeistBlock()
        return .repeatUntil(try RepeatUntilStep(
            predicate: predicate,
            timeout: timeout,
            body: body,
            elseBody: try parseLowercaseElseChainIfPresent(chainContext: "RepeatUntil")
        ))
    }

    mutating func parseElementMatches() throws -> ElementPredicate {
        try expectSymbol(".")
        let name = try parseIdentifier()
        if name != "matching" {
            return try concretePredicate(from: parseElementPredicateTemplate(named: name))
        }
        try expectSymbol("(")
        let predicate = try parseElementPredicate()
        try expectSymbol(")")
        return predicate
    }

    mutating func parseRunHeist() throws -> HeistStep {
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

    mutating func parseHeistArgument() throws -> HeistArgument {
        if let string = try parseStringExprIfPresent() {
            return .string(string)
        }
        return .elementTarget(try parseTargetExpr())
    }

    mutating func parseWarn() throws -> HeistStep {
        try expectSymbol("(")
        let message = try parseStringLiteral()
        try expectSymbol(")")
        return .warn(WarnStep(message: message))
    }

    mutating func parseFail() throws -> HeistStep {
        try expectSymbol("(")
        let message = try parseStringLiteral()
        try expectSymbol(")")
        return .fail(FailStep(message: message))
    }

    mutating func parsePredicateBranches() throws -> (
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

    mutating func parseSinglePredicateBranches(
        predicate: AccessibilityPredicateExpr,
        chainContext: String
    ) throws -> (
        cases: [PredicateCase],
        elseBody: [HeistStep]?
    ) {
        let body = try parseHeistBlock()
        let elseBody = try parseLowercaseElseChainIfPresent(chainContext: chainContext)
        return ([PredicateCase(predicate: predicate, body: body)], elseBody)
    }

    mutating func parseHeistBlock() throws -> [HeistStep] {
        try expectSymbol("{")
        let body = try parseHeistBody(untilRightBrace: true, allowDefinitions: false)
        return body.steps
    }

    mutating func parseLowercaseElseChainIfPresent(chainContext: String) throws -> [HeistStep]? {
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
    ) throws -> (referenceName: HeistReferenceName, body: [HeistStep]) {
        try expectSymbol("{")
        let localName = try parseIdentifier()
        try expectIdentifier("in")
        let referenceName = HeistReferenceName(rawValue: localName)
        let previousScope = currentScope()
        defer { restoreScope(previousScope) }
        bindScopedReference(binding, localName: localName, referenceName: referenceName)
        let body = try parseHeistBody(untilRightBrace: true, allowDefinitions: false)
        return (referenceName, body.steps)
    }

    mutating func parseStringArrayTail() throws -> [String] {
        var values: [String] = []
        if consumeSymbol("]") { return values }
        repeat {
            values.append(try parseStringLiteral())
        } while consumeSymbol(",")
        try expectSymbol("]")
        return values
    }

}
