import Foundation

enum HeistRuntimePayloadContractValidator {
    static func validate<T: Codable>(_ payload: T) throws {
        let data = try JSONEncoder().encode(payload)
        _ = try JSONDecoder().decode(T.self, from: data)
    }
}

struct StringLoopResolvedPayloadValidator: HeistPlanTraversalVisitor {
    let valuePath: String

    var failures: [HeistPlanRuntimeSafetyFailure] = []

    mutating func visitAction(_ action: ActionStep, context: HeistTraversalContext) {
        do {
            try action.command.assertResolvedPayloadAdmissible(in: context.environment)
        } catch {
            fail(
                path: context.path.description,
                contract: "string loop value must lower through the heist action payload contract",
                observed: "\(valuePath) resolved to \(summarize(error))",
                correction: "Use loop string values that keep every referenced command payload valid."
            )
        }
    }

    mutating func visitWait(_ wait: WaitStep, context: HeistTraversalContext) {
        do {
            _ = try wait.resolve(in: context.environment)
        } catch {
            fail(
                path: context.path.description,
                contract: "string loop value must resolve wait predicates",
                observed: "\(valuePath) resolved to \(summarize(error))",
                correction: "Use loop string values that keep every referenced wait predicate valid."
            )
        }
    }

    mutating func fail(
        path: String,
        contract: String,
        observed: String,
        correction: String
    ) {
        failures.append(HeistPlanRuntimeSafetyFailure(
            path: path,
            contract: contract,
            observed: observed,
            correction: correction
        ))
    }

    func summarize(_ error: Error) -> String {
        let text = String(describing: error)
        guard text.count > 220 else { return text }
        return "\(text.prefix(217))..."
    }
}
