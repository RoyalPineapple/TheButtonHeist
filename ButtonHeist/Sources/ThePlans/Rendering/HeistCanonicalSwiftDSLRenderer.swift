import Foundation

struct HeistCanonicalSwiftDSLRenderer {
    func render(_ plan: HeistPlan) throws -> String {
        let environment = try RenderEnvironment.empty.binding(parameter: plan.parameter)
        let definitions = try renderDefinitions(plan.definitions, path: [], indent: 1)
        let body = try render(steps: plan.body, indent: 1, environment: environment)
        let content = [definitions, body].filter { !$0.isEmpty }.joined(separator: "\n\n")
        let heistHeader = try renderHeistHeader(plan, callee: "HeistPlan")
        let heist = """
        \(heistHeader)
        \(content)
        }
        """
        return heist
    }

    func renderHeistHeader(_ plan: HeistPlan, callee: String) throws -> String {
        let nameArgument = plan.name.map(quote)
        switch plan.parameter {
        case .none:
            guard let nameArgument else { return "\(callee) {" }
            return "\(callee)(\(nameArgument)) {"
        case .string(let parameter):
            try validateParameter(parameter)
            let prefix = nameArgument.map { "\($0), " } ?? ""
            return "\(callee)(\(prefix)parameter: \(quote(parameter))) { \(parameter) in"
        case .elementTarget(let parameter):
            try validateParameter(parameter)
            let prefix = nameArgument.map { "\($0), " } ?? ""
            return "\(callee)(\(prefix)targetParameter: \(quote(parameter))) { \(parameter) in"
        }
    }
}
