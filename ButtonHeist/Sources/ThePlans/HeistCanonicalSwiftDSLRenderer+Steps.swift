import Foundation

extension HeistCanonicalSwiftDSLRenderer {
    func render(
        steps: [HeistStep],
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        try steps.map { try render(step: $0, indent: indent, environment: environment) }
            .joined(separator: "\n\n")
    }

    func render(
        step: HeistStep,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        switch step {
        case .action(let action):
            return try render(action: action, indent: indent, environment: environment)
        case .wait(let wait):
            return try render(wait: wait, indent: indent, environment: environment)
        case .conditional(let conditional):
            return try renderConditional(conditional, indent: indent, environment: environment)
        case .forEachElement(let forEach):
            return try renderForEachElement(forEach, indent: indent, environment: environment)
        case .forEachString(let forEach):
            return try renderForEachString(forEach, indent: indent, environment: environment)
        case .warn(let warn):
            return line("Warn(\(quote(warn.message)))", indent)
        case .fail(let fail):
            return line("Fail(\(quote(fail.message)))", indent)
        case .heist(let plan):
            let environment = try environment.binding(parameter: plan.parameter)
            let body = try render(steps: plan.body, indent: indent + 1, environment: environment)
            let header = try renderHeistHeader(plan, callee: "HeistPlan")
            return """
            \(line(header, indent))
            \(body)
            \(line("}", indent))
            """
        case .invoke(let invoke):
            return try line(render(invoke: invoke, environment: environment), indent)
        }
    }

    func render(invoke: HeistInvocationStep, environment: RenderEnvironment) throws -> String {
        let callee = invoke.path.joined(separator: ".")
        let argument = try render(argument: invoke.argument, environment: environment)
        return argument.isEmpty ? "RunHeist(\(quote(callee)))" : "RunHeist(\(quote(callee)), \(argument))"
    }

    func render(argument: HeistArgument, environment: RenderEnvironment) throws -> String {
        switch argument {
        case .none:
            return ""
        case .string(let value):
            return try render(string: value, environment: environment)
        case .elementTarget(let target):
            return try render(target: target, environment: environment)
        }
    }

    func renderConditional(
        _ conditional: ConditionalStep,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        if conditional.cases.count == 1 {
            return try renderSingleCaseBranches(
                callee: "If",
                predicate: conditional.cases[0].predicate,
                timeout: nil,
                body: conditional.cases[0].body,
                elseBody: conditional.elseBody,
                indent: indent,
                environment: environment
            )
        }
        let cases = try renderCases(
            conditional.cases,
            elseBody: conditional.elseBody,
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
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        var source = line(
            "WaitFor(\(try render(predicate: wait.predicate, environment: environment))\(renderTimeout(wait.timeout)))",
            indent
        )
        if let elseBody = wait.elseBody {
            source += "\n"
            source += line(".else {", indent)
            source += "\n"
            source += try render(steps: elseBody, indent: indent + 1, environment: environment)
            source += "\n"
            source += line("}", indent)
        }
        return source
    }

    func renderSingleCaseBranches(
        callee: String,
        predicate: AccessibilityPredicateExpr,
        timeout: Double?,
        body: [HeistStep],
        elseBody: [HeistStep]?,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        let timeoutArgument = timeout.map { "\(renderTimeout($0))" } ?? ""
        let renderedBody = try render(steps: body, indent: indent + 1, environment: environment)
        var source = """
        \(line("\(callee)(\(try render(predicate: predicate, environment: environment))\(timeoutArgument)) {", indent))
        \(renderedBody)
        \(line("}", indent))
        """
        if let elseBody {
            source += "\n"
            source += line(".else {", indent)
            source += "\n"
            source += try render(steps: elseBody, indent: indent + 1, environment: environment)
            source += "\n"
            source += line("}", indent)
        }
        return source
    }

    func renderCases(
        _ cases: [PredicateCase],
        elseBody: [HeistStep]?,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        var blocks: [String] = []
        for predicateCase in cases {
            blocks.append(try renderCase(predicateCase, indent: indent, environment: environment))
        }
        if let elseBody {
            let body = try render(steps: elseBody, indent: indent + 1, environment: environment)
            blocks.append("""
            \(line("Else {", indent))
            \(body)
            \(line("}", indent))
            """)
        }
        return blocks.joined(separator: "\n\n")
    }

    func renderCase(
        _ predicateCase: PredicateCase,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        let body = try render(steps: predicateCase.body, indent: indent + 1, environment: environment)
        return """
        \(line("Case(\(try render(predicate: predicateCase.predicate, environment: environment))) {", indent))
        \(body)
        \(line("}", indent))
        """
    }

    func renderForEachElement(
        _ forEach: ForEachElementStep,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        try validateParameter(forEach.parameter)
        let childEnvironment = environment.bindingTargetReference(forEach.parameter)
        let body = try render(steps: forEach.body, indent: indent + 1, environment: childEnvironment)
        return """
        \(line("ForEach(.matching(\(render(predicate: forEach.matching))), limit: \(forEach.limit)) { \(forEach.parameter) in", indent))
        \(body)
        \(line("}", indent))
        """
    }

    func renderForEachString(
        _ forEach: ForEachStringStep,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        try validateParameter(forEach.parameter)
        let childEnvironment = environment.bindingStringReference(forEach.parameter)
        let values = forEach.values.map(quote).joined(separator: ", ")
        let body = try render(steps: forEach.body, indent: indent + 1, environment: childEnvironment)
        return """
        \(line("ForEach([\(values)]) { \(forEach.parameter) in", indent))
        \(body)
        \(line("}", indent))
        """
    }
}
