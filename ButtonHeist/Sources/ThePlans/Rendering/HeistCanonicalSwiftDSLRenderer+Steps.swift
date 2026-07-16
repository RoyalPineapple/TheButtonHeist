import Foundation

extension HeistCanonicalSwiftDSLRenderer {
    func render(
        invoke: HeistInvocationStep,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        let callee = invoke.path.description
        let argument = try render(argument: invoke.argument, environment: environment)
        let base = argument.isEmpty ? "RunHeist(\(quote(callee)))" : "RunHeist(\(quote(callee)), \(argument))"
        var text = line(base, indent)
        if let expectation = invoke.expectation {
            let predicate = try render(predicate: expectation.predicate, environment: environment)
            text += "\n" + line(".expect(\(predicate)\(renderInvocationExpectationTimeout(expectation.timeout)))", indent + 1)
        }
        return text
    }

    private func renderInvocationExpectationTimeout(_ timeout: WaitTimeout) -> String {
        timeout == defaultActionExpectationTimeout
            ? ""
            : ", timeout: .seconds(\(decimal(timeout.seconds)))"
    }

    func render(argument: HeistArgument, environment: RenderEnvironment) throws -> String {
        switch argument.core {
        case .none:
            return ""
        case .string(let value):
            return try render(string: value, environment: environment)
        case .accessibilityTarget(let target):
            return try render(target: target, environment: environment)
        }
    }

    func renderConditional(
        _ conditional: ConditionalStep,
        renderedBodies: [String],
        renderedElseBody: String?,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        if conditional.cases.count == 1 {
            return try renderSingleCaseBranches(
                callee: "If",
                predicate: conditional.cases[0].predicate,
                timeout: nil,
                renderedBody: renderedBodies[0],
                renderedElseBody: renderedElseBody,
                indent: indent,
                environment: environment
            )
        }
        let cases = try renderCases(
            conditional.cases,
            renderedBodies: renderedBodies,
            renderedElseBody: renderedElseBody,
            indent: indent + 1,
            environment: environment
        )
        return """
        \(line("If {", indent))
        \(cases)
        \(line("}", indent))
        """
    }

    func render(
        wait: WaitStep,
        renderedElseBody: String?,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        var source = line(
            "WaitFor(\(try render(predicate: wait.predicate, environment: environment))\(renderTimeout(wait.timeout)))",
            indent
        )
        if let renderedElseBody {
            source += "\n"
            source += line(".else {", indent)
            source += "\n"
            source += renderedElseBody
            source += "\n"
            source += line("}", indent)
        }
        return source
    }

    func renderSingleCaseBranches(
        callee: String,
        predicate: ChangeDeclaration.ScreenAssertion,
        timeout: WaitTimeout?,
        renderedBody: String,
        renderedElseBody: String?,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        let timeoutArgument = timeout.map { "\(renderTimeout($0))" } ?? ""
        var source = """
        \(line("\(callee)(\(try render(predicate: predicate, environment: environment))\(timeoutArgument)) {", indent))
        \(renderedBody)
        \(line("}", indent))
        """
        if let renderedElseBody {
            source += "\n"
            source += line(".else {", indent)
            source += "\n"
            source += renderedElseBody
            source += "\n"
            source += line("}", indent)
        }
        return source
    }

    func renderCases(
        _ cases: [PredicateCase],
        renderedBodies: [String],
        renderedElseBody: String?,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        var blocks = try zip(cases, renderedBodies).map { predicateCase, renderedBody in
            try renderCase(
                predicateCase,
                renderedBody: renderedBody,
                indent: indent,
                environment: environment
            )
        }
        if let renderedElseBody {
            blocks.append("""
            \(line("Else {", indent))
            \(renderedElseBody)
            \(line("}", indent))
            """)
        }
        return blocks.joined(separator: "\n\n")
    }

    func renderCase(
        _ predicateCase: PredicateCase,
        renderedBody: String,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        return """
        \(line("Case(\(try render(predicate: predicateCase.predicate, environment: environment))) {", indent))
        \(renderedBody)
        \(line("}", indent))
        """
    }

    func renderForEachElement(
        _ forEach: ForEachElementStep,
        renderedBody: String,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        let predicate = try render(predicate: forEach.matching, environment: environment)
        let header = "ForEach(\(predicate), limit: \(forEach.limit)) { \(forEach.parameter) in"
        return """
        \(line(header, indent))
        \(renderedBody)
        \(line("}", indent))
        """
    }

    func renderForEachString(
        _ forEach: ForEachStringStep,
        renderedBody: String,
        indent: Int
    ) throws -> String {
        let values = forEach.values.map(quote).joined(separator: ", ")
        return """
        \(line("ForEach(\(values)) { \(forEach.parameter) in", indent))
        \(renderedBody)
        \(line("}", indent))
        """
    }

    func renderRepeatUntil(
        _ repeatUntil: RepeatUntilStep,
        renderedBody: String,
        renderedElseBody: String?,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        let predicate = try render(predicate: repeatUntil.predicate, environment: environment)
        let timeout = ".seconds(\(decimal(repeatUntil.timeout.seconds)))"
        var source = """
        \(line("RepeatUntil(\(predicate), timeout: \(timeout)) {", indent))
        \(renderedBody)
        \(line("}", indent))
        """
        if let renderedElseBody {
            source += "\n"
            source += line(".else {", indent)
            source += "\n"
            source += renderedElseBody
            source += "\n"
            source += line("}", indent)
        }
        return source
    }
}
