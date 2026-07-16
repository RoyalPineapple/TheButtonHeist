import Foundation

struct HeistCanonicalSwiftDSLRenderer {
    func render(_ plan: HeistPlan) throws -> String {
        var algebra = HeistCanonicalSwiftDSLRenderAlgebra(renderer: self)
        HeistPlanTraversal(expandsInvocations: false).walk(plan, visitor: &algebra)
        return try algebra.output()
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
}

private struct HeistCanonicalSwiftDSLRenderAlgebra: HeistPlanTraversalVisitor {
    private struct DefinitionFrame {
        let fullPath: HeistDefinitionPath
        let indent: Int
        let isNamespace: Bool
    }

    let renderer: HeistCanonicalSwiftDSLRenderer
    private var renderedSteps: [HeistPlanPath: String] = [:]
    private var renderedBodies: [HeistPlanPath: String] = [:]
    private var renderedDefinitions: [HeistPlanPath: String] = [:]
    private var renderedDefinitionGroups: [HeistPlanPath: String] = [:]
    private var bodyIndents: [HeistPlanPath: Int] = [:]
    private var bodyEnvironments: [HeistPlanPath: RenderEnvironment] = [:]
    private var stepIndents: [HeistPlanPath: Int] = [:]
    private var stepEnvironments: [HeistPlanPath: RenderEnvironment] = [:]
    private var activeBodyIndents: [Int] = []
    private var activeBodyEnvironments: [RenderEnvironment] = []
    private var definitionFrames: [DefinitionFrame] = []
    private var renderedPlan: String?
    private var failure: (any Error)?

    init(renderer: HeistCanonicalSwiftDSLRenderer) {
        self.renderer = renderer
    }

    mutating func visitPlan(_ plan: HeistPlan, context: HeistTraversalContext) {
        bodyIndents[context.path.child(.body)] = 1
    }

    mutating func visitDefinition(_ plan: HeistPlan, context: HeistTraversalContext) {
        guard let name = plan.name else {
            preconditionFailure("admitted heist definitions must have names")
        }
        let parent = definitionFrames.last
        let pathPrefix = parent?.isNamespace == true ? parent?.fullPath.components ?? [] : []
        let indent = parent.map { $0.isNamespace ? $0.indent : $0.indent + 1 } ?? 1
        let frame = DefinitionFrame(
            fullPath: HeistDefinitionPath(first: pathPrefix.first ?? name, remaining: pathPrefix.isEmpty
                ? []
                : Array(pathPrefix.dropFirst()) + [name]),
            indent: indent,
            isNamespace: plan.body.isEmpty && !plan.definitions.isEmpty && plan.parameter == .none
        )
        definitionFrames.append(frame)
        bodyIndents[context.path.child(.body)] = indent + 1
        bodyEnvironments[context.path.child(.body)] = RenderEnvironment(scope: context.scope)
    }

    mutating func visitSteps(_ steps: [HeistStep], context: HeistTraversalContext) {
        activeBodyIndents.append(bodyIndents[context.path] ?? context.depth)
        activeBodyEnvironments.append(bodyEnvironments[context.path] ?? RenderEnvironment(scope: context.scope))
    }

    mutating func leaveSteps(_ steps: [HeistStep], context: HeistTraversalContext) {
        _ = activeBodyIndents.popLast()
        _ = activeBodyEnvironments.popLast()
        guard failure == nil else { return }
        let results = steps.indices.compactMap { renderedSteps[context.path.index($0)] }
        precondition(results.count == steps.count, "canonical traversal did not reduce every heist step")
        renderedBodies[context.path] = results.joined(separator: "\n\n")
    }

    mutating func visitStep(_ step: HeistStep, context: HeistTraversalContext) {
        let indent = activeBodyIndents.last ?? context.depth
        let environment = activeBodyEnvironments.last ?? RenderEnvironment(scope: context.scope)
        stepIndents[context.path] = indent
        stepEnvironments[context.path] = environment
        let childIndent = indent + 1
        switch step {
        case .action, .warn, .fail, .invoke:
            break
        case .wait(let wait):
            if wait.elseBody != nil {
                bodyIndents[context.path.child(.wait).child(.elseBody)] = childIndent
            }
        case .conditional(let conditional):
            for index in conditional.cases.indices {
                bodyIndents[context.path.child(.conditional).child(.cases).index(index).child(.body)] = childIndent
            }
            if conditional.elseBody != nil {
                bodyIndents[context.path.child(.conditional).child(.elseBody)] = childIndent
            }
        case .forEachElement:
            bodyIndents[context.path.child(.forEachElement).child(.body)] = childIndent
        case .forEachString:
            bodyIndents[context.path.child(.forEachString).child(.body)] = childIndent
        case .repeatUntil(let repeatUntil):
            bodyIndents[context.path.child(.repeatUntil).child(.body)] = childIndent
            if repeatUntil.elseBody != nil {
                bodyIndents[context.path.child(.repeatUntil).child(.elseBody)] = childIndent
            }
        case .heist(let plan):
            let bodyPath = context.path.child(.heist).child(.body)
            bodyIndents[bodyPath] = childIndent
            bodyEnvironments[bodyPath] = try? environment.binding(parameter: plan.parameter)
        }
    }

    mutating func leaveStep(_ step: HeistStep, context: HeistTraversalContext) {
        guard failure == nil else { return }
        do {
            let indent = stepIndents[context.path] ?? context.depth
            let environment = stepEnvironments[context.path] ?? RenderEnvironment(scope: context.scope)
            renderedSteps[context.path] = try render(
                step,
                path: context.path,
                indent: indent,
                environment: environment
            )
        } catch {
            failure = error
        }
    }

    mutating func leaveDefinition(_ plan: HeistPlan, context: HeistTraversalContext) {
        let frame = definitionFrames.removeLast()
        guard failure == nil else { return }
        do {
            if frame.isNamespace {
                renderedDefinitions[context.path] = renderedDefinitionGroups[
                    context.path.child(.definitions)
                ] ?? ""
                return
            }
            let nestedDefinitions = renderedDefinitionGroups[context.path.child(.definitions)] ?? ""
            let body = renderedBodies[context.path.child(.body)] ?? ""
            let content = [nestedDefinitions, body].filter { !$0.isEmpty }.joined(separator: "\n\n")
            let type = try renderer.renderDefinitionType(plan.parameter)
            let header = try renderer.renderDefinitionHeader(plan, type: type, path: frame.fullPath)
            renderedDefinitions[context.path] = """
            \(renderer.line(header, frame.indent))
            \(content)
            \(renderer.line("}", frame.indent))
            """
        } catch {
            failure = error
        }
    }

    mutating func leaveDefinitions(_ definitions: [HeistPlan], context: HeistTraversalContext) {
        guard failure == nil else { return }
        let results = definitions.indices.compactMap { renderedDefinitions[context.path.index($0)] }
        precondition(results.count == definitions.count, "canonical traversal did not reduce every heist definition")
        renderedDefinitionGroups[context.path] = results.joined(separator: "\n\n")
    }

    mutating func leavePlan(_ plan: HeistPlan, context: HeistTraversalContext) {
        guard failure == nil else { return }
        do {
            let definitions = renderedDefinitionGroups[context.path.child(.definitions)] ?? ""
            let body = renderedBodies[context.path.child(.body)] ?? ""
            let content = [definitions, body].filter { !$0.isEmpty }.joined(separator: "\n\n")
            let header = try renderer.renderHeistHeader(plan, callee: "HeistPlan")
            renderedPlan = """
            \(header)
            \(content)
            }
            """
        } catch {
            failure = error
        }
    }

    func output() throws -> String {
        if let failure { throw failure }
        guard let renderedPlan else {
            preconditionFailure("canonical traversal did not reduce the heist plan")
        }
        return renderedPlan
    }

    private func render(
        _ step: HeistStep,
        path: HeistPlanPath,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        switch step {
        case .action(let action):
            return try renderer.render(action: action, indent: indent, environment: environment)
        case .wait(let wait):
            return try renderer.render(
                wait: wait,
                renderedElseBody: renderedBodies[path.child(.wait).child(.elseBody)],
                indent: indent,
                environment: environment
            )
        case .conditional(let conditional):
            let conditionalPath = path.child(.conditional)
            let bodies = conditional.cases.indices.map {
                renderedBodies[conditionalPath.child(.cases).index($0).child(.body)] ?? ""
            }
            return try renderer.renderConditional(
                conditional,
                renderedBodies: bodies,
                renderedElseBody: renderedBodies[conditionalPath.child(.elseBody)],
                indent: indent,
                environment: environment
            )
        case .forEachElement(let forEach):
            return try renderer.renderForEachElement(
                forEach,
                renderedBody: renderedBodies[path.child(.forEachElement).child(.body)] ?? "",
                indent: indent,
                environment: environment
            )
        case .forEachString(let forEach):
            return try renderer.renderForEachString(
                forEach,
                renderedBody: renderedBodies[path.child(.forEachString).child(.body)] ?? "",
                indent: indent
            )
        case .repeatUntil(let repeatUntil):
            let repeatPath = path.child(.repeatUntil)
            return try renderer.renderRepeatUntil(
                repeatUntil,
                renderedBody: renderedBodies[repeatPath.child(.body)] ?? "",
                renderedElseBody: renderedBodies[repeatPath.child(.elseBody)],
                indent: indent,
                environment: environment
            )
        case .warn(let warn):
            return renderer.line("Warn(\(renderer.quote(warn.message.rawValue)))", indent)
        case .fail(let fail):
            return renderer.line("Fail(\(renderer.quote(fail.message.rawValue)))", indent)
        case .heist(let plan):
            let body = renderedBodies[path.child(.heist).child(.body)] ?? ""
            let header = try renderer.renderHeistHeader(plan, callee: "HeistPlan")
            return """
            \(renderer.line(header, indent))
            \(body)
            \(renderer.line("}", indent))
            """
        case .invoke(let invoke):
            return try renderer.render(invoke: invoke, indent: indent, environment: environment)
        }
    }
}
