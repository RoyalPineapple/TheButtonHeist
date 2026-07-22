import Foundation

struct HeistCanonicalSwiftDSLRenderer {
    func render(_ plan: HeistPlan) throws -> String {
        try render(plan, callee: "HeistPlan", indent: 0, environment: RenderEnvironment(scope: .empty))
    }

    func renderHeistHeader(_ plan: HeistPlan, callee: String) throws -> String {
        let nameArgument = plan.name.map { quote($0.description) }
        switch plan.parameter {
        case .none:
            guard let nameArgument else { return "\(callee) {" }
            return "\(callee)(\(nameArgument)) {"
        case .string(let parameter):
            let prefix = nameArgument.map { "\($0), " } ?? ""
            return "\(callee)(\(prefix)parameter: \(quote(parameter))) { \(parameter) in"
        case .accessibilityTarget(let parameter):
            let prefix = nameArgument.map { "\($0), " } ?? ""
            return "\(callee)(\(prefix)targetParameter: \(quote(parameter))) { \(parameter) in"
        }
    }

    private func render(
        _ plan: HeistPlan,
        callee: String,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        let bodyEnvironment = try environment.binding(parameter: plan.parameter)
        let content = try [
            renderDefinitions(plan.definitions, parent: nil, indent: indent + 1),
            renderBody(plan.body, indent: indent + 1, environment: bodyEnvironment)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
        let header = try renderHeistHeader(plan, callee: callee)
        return """
        \(line(header, indent))
        \(content)
        \(line("}", indent))
        """
    }

    private func renderDefinitions(
        _ definitions: [HeistPlan],
        parent: DefinitionFrame?,
        indent: Int
    ) throws -> String {
        try definitions.map { definition in
            try renderDefinition(definition, parent: parent, indent: indent)
        }.joined(separator: "\n\n")
    }

    private func renderDefinition(
        _ definition: HeistPlan,
        parent: DefinitionFrame?,
        indent: Int
    ) throws -> String {
        guard let name = definition.name else {
            preconditionFailure("admitted heist definitions must have names")
        }

        let pathComponents = parent?.isNamespace == true ? parent?.path.components ?? [] : []
        let path = HeistDefinitionPath(
            first: pathComponents.first ?? name,
            remaining: pathComponents.isEmpty ? [] : Array(pathComponents.dropFirst()) + [name]
        )
        let frame = DefinitionFrame(
            path: path,
            indent: parent.map { $0.isNamespace ? $0.indent : $0.indent + 1 } ?? indent,
            isNamespace: definition.body.isEmpty && !definition.definitions.isEmpty && definition.parameter == .none
        )

        if frame.isNamespace {
            return try renderDefinitions(definition.definitions, parent: frame, indent: frame.indent)
        }

        let bodyEnvironment = RenderEnvironment(
            scope: HeistReferenceBindingContext.runtimeSafetyPlaceholder(for: definition.parameter).scope
        )
        let content = try [
            renderDefinitions(definition.definitions, parent: frame, indent: frame.indent + 1),
            renderBody(definition.body, indent: frame.indent + 1, environment: bodyEnvironment)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
        let type = try renderDefinitionType(definition.parameter)
        let header = try renderDefinitionHeader(definition, type: type, path: frame.path)
        return """
        \(line(header, frame.indent))
        \(content)
        \(line("}", frame.indent))
        """
    }

    private func renderBody(
        _ steps: [HeistStep],
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        try steps.map { step in
            try render(step, indent: indent, environment: environment)
        }.joined(separator: "\n\n")
    }

    private func render(
        _ step: HeistStep,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        switch step {
        case .action(let action):
            return try render(action: action, indent: indent, environment: environment)
        case .wait(let wait):
            return try render(
                wait: wait,
                renderedElseBody: try wait.elseBody.map {
                    try renderBody($0, indent: indent + 1, environment: environment)
                },
                indent: indent,
                environment: environment
            )
        case .conditional(let conditional):
            let bodies = try conditional.cases.map { predicateCase in
                try renderBody(predicateCase.body, indent: indent + 1, environment: environment)
            }
            return try renderConditional(
                conditional,
                renderedBodies: bodies,
                renderedElseBody: try conditional.elseBody.map {
                    try renderBody($0, indent: indent + 1, environment: environment)
                },
                indent: indent,
                environment: environment
            )
        case .forEachElement(let forEach):
            let bodyEnvironment = try environment.binding(parameter: .accessibilityTarget(name: forEach.parameter))
            return try renderForEachElement(
                forEach,
                renderedBody: try renderBody(forEach.body, indent: indent + 1, environment: bodyEnvironment),
                indent: indent,
                environment: environment
            )
        case .forEachString(let forEach):
            let bodyEnvironment = try environment.binding(parameter: .string(name: forEach.parameter))
            return try renderForEachString(
                forEach,
                renderedBody: try renderBody(forEach.body, indent: indent + 1, environment: bodyEnvironment),
                indent: indent
            )
        case .repeatUntil(let repeatUntil):
            return try renderRepeatUntil(
                repeatUntil,
                renderedBody: try renderBody(repeatUntil.body, indent: indent + 1, environment: environment),
                indent: indent,
                environment: environment
            )
        case .warn(let warn):
            return line("Warn(\(quote(warn.message.rawValue)))", indent)
        case .fail(let fail):
            return line("Fail(\(quote(fail.message.rawValue)))", indent)
        case .heist(let plan):
            return try render(plan, callee: "HeistPlan", indent: indent, environment: environment)
        case .invoke(let invoke):
            return try render(invoke: invoke, indent: indent, environment: environment)
        }
    }
}

private struct DefinitionFrame {
    let path: HeistDefinitionPath
    let indent: Int
    let isNamespace: Bool
}
