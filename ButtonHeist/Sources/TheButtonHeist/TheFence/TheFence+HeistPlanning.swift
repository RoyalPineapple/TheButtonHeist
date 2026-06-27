import Foundation

import ThePlans
@_spi(ButtonHeistInternals) import TheScore

extension TheFence {

    struct RunHeistRequest {
        let plan: HeistPlan
        let argument: HeistArgument
    }

    struct PerformRequest {
        let plan: HeistPlan
        let step: PerformableHeistStep
    }

    struct ListHeistsRequest {
        let catalog: HeistDiscoveryCatalog
    }

    struct DescribeHeistRequest {
        let description: HeistDescription
    }

    enum PerformableHeistStep: Sendable, Equatable {
        case action(ActionStep)
        case wait(WaitStep)

        var heistStep: HeistStep {
            switch self {
            case .action(let action):
                return .action(action)
            case .wait(let wait):
                return .wait(wait)
            }
        }
    }

    enum PerformStepValidationError: Error, Sendable, Equatable, CustomStringConvertible {
        case wrongStepCount(Int)
        case unsupportedStep

        var diagnostic: HeistBuildDiagnostic {
            switch self {
            case .wrongStepCount:
                return Self.diagnostic(code: "heist.perform.wrong_step_count")
            case .unsupportedStep:
                return Self.diagnostic(code: "heist.perform.unsupported_step")
            }
        }

        var description: String {
            switch self {
            case .wrongStepCount:
                return Self.guidance
            case .unsupportedStep:
                return Self.guidance
            }
        }

        private static let guidance = """
        perform accepts one action statement or one simple WaitFor statement. \
        Use run_heist for branching, loops, reusable heists, warnings, failures, or multiple steps.
        """

        private static func diagnostic(code: String) -> HeistBuildDiagnostic {
            HeistBuildDiagnostic(
                code: code,
                phase: .planning,
                message: guidance,
                hint: "Use run_heist for full ButtonHeist programs."
            )
        }
    }

    func decodePerformRequest(_ arguments: CommandArgumentEnvelope) throws -> PerformRequest {
        try CommandArgumentEnvelopeLimits.validateHeistPlanSource(arguments, field: Command.perform.rawValue)
        let source = try arguments.requiredSchemaString("step")
        let plan = try loadInlinePerformStepSource(source)
        let step = try performableStep(in: plan)
        return PerformRequest(plan: plan, step: step)
    }

    func decodeRunHeistRequest(_ arguments: CommandArgumentEnvelope) throws -> RunHeistRequest {
        let plan = try admitRuntimeSafeHeistPlanSource(
            from: arguments,
            commandName: Command.runHeist.rawValue,
            droppingPlanKeys: ["argument"],
            acceptsInlinePlanSource: true
        )
        let argument = try decodeRootHeistArgument(from: arguments)
        try validateRootHeistArgument(argument, for: plan)
        return RunHeistRequest(plan: plan, argument: argument)
    }

    func loadInlinePerformStepSource(_ source: String) throws -> HeistPlan {
        switch HeistPlanning.loadValidatedPlanResult(from: HeistPlanSourceRequest(
            commandName: Command.perform.rawValue,
            inlineButtonHeistSource:
            """
            HeistPlan {
            \(source)
            }
            """
        )) {
        case .success(let plan, _):
            return plan
        case .failure(let diagnostics):
            guard diagnostics.contains(where: { $0.message.contains("WaitFor is a gate") }) else {
                throw buildDiagnosticFenceError(diagnostics)
            }
            throw buildDiagnosticFenceError([PerformStepValidationError.unsupportedStep.diagnostic])
        }
    }

    func performableStep(in plan: HeistPlan) throws -> PerformableHeistStep {
        guard plan.definitions.isEmpty else {
            throw buildDiagnosticFenceError([PerformStepValidationError.unsupportedStep.diagnostic])
        }
        guard plan.body.count == 1, let step = plan.body.first else {
            throw buildDiagnosticFenceError([PerformStepValidationError.wrongStepCount(plan.body.count).diagnostic])
        }
        switch step {
        case .action(let action):
            guard action.command.isPerformPrimitive else {
                throw buildDiagnosticFenceError([PerformStepValidationError.unsupportedStep.diagnostic])
            }
            return .action(action)
        case .wait(let wait):
            return .wait(wait)
        case .conditional, .forEachElement, .forEachString, .repeatUntil, .warn, .fail, .heist, .invoke:
            throw buildDiagnosticFenceError([PerformStepValidationError.unsupportedStep.diagnostic])
        }
    }

    func decodeListHeistsRequest(_ arguments: CommandArgumentEnvelope) throws -> ListHeistsRequest {
        let detail = try arguments.schemaEnum("detail", as: HeistCatalogDetail.self) ?? .summary
        do {
            let plan = try admitRuntimeSafeHeistPlanSource(
                from: arguments,
                commandName: Command.listHeists.rawValue,
                droppingPlanKeys: ["detail"],
                acceptsInlinePlanSource: true
            )
            return ListHeistsRequest(catalog: try plan.heistCatalog(detail: detail))
        } catch let error as HeistCatalogError {
            throw FenceError.invalidRequest(error.description)
        }
    }

    func decodeDescribeHeistRequest(_ arguments: CommandArgumentEnvelope) throws -> DescribeHeistRequest {
        let requestedName = try arguments.requiredSchemaString("heist")
        do {
            let plan = try admitRuntimeSafeHeistPlanSource(
                from: arguments,
                commandName: Command.describeHeist.rawValue,
                droppingPlanKeys: ["heist"],
                acceptsInlinePlanSource: true
            )
            return DescribeHeistRequest(description: try plan.describeHeist(named: requestedName))
        } catch let error as HeistCatalogError {
            throw FenceError.invalidRequest(error.description)
        } catch let error as HeistDescriptionLookupError {
            throw FenceError.invalidRequest(error.description)
        }
    }

}

private extension HeistActionCommand {
    var isPerformPrimitive: Bool {
        switch self {
        case .activate, .increment, .decrement, .customAction, .rotor,
             .typeText, .mechanicalTap, .mechanicalLongPress, .mechanicalSwipe,
             .mechanicalDrag, .editAction, .setPasteboard, .takeScreenshot, .dismissKeyboard:
            return true
        case .viewportScroll, .viewportScrollToVisible, .viewportScrollToEdge:
            return false
        }
    }
}

private extension TheFence {

    func admitRuntimeSafeHeistPlanSource(
        from arguments: CommandArgumentEnvelope,
        commandName: String,
        droppingPlanKeys: Set<String> = [],
        acceptsInlinePlanSource: Bool
    ) throws -> HeistPlan {
        // Admission: accept exactly one public source shape for a plan. ThePlans
        // then returns a RuntimeSafety-validated executable `HeistPlan`.
        try CommandArgumentEnvelopeLimits.validateHeistPlanSource(arguments, field: commandName)
        switch HeistPlanning.loadValidatedPlanResult(from: HeistPlanSourceRequest(
            commandName: commandName,
            path: try arguments.schemaString("path"),
            inlineButtonHeistSource: try arguments.schemaString("plan"),
            rawStructuredJSONIRFields: rawStructuredJSONIRFields(in: arguments, dropping: droppingPlanKeys),
            acceptsInlineButtonHeistSource: acceptsInlinePlanSource
        )) {
        case .success(let plan, _):
            return plan
        case .failure(let diagnostics):
            throw buildDiagnosticFenceError(diagnostics)
        }
    }

    func loadInlineButtonHeistSource(_ source: String, commandName: String) throws -> HeistPlan {
        switch HeistPlanning.loadValidatedPlanResult(from: HeistPlanSourceRequest(
            commandName: commandName,
            inlineButtonHeistSource: source
        )) {
        case .success(let plan, _):
            return plan
        case .failure(let diagnostics):
            throw buildDiagnosticFenceError(diagnostics)
        }
    }

    func rawStructuredJSONIRFields(
        in arguments: CommandArgumentEnvelope,
        dropping keys: Set<String>
    ) -> Set<String> {
        var fieldNames = Set(arguments.argumentValues.keys)
        fieldNames.remove("requestId")
        fieldNames.subtract(keys)
        return fieldNames.intersection(HeistPlanning.rawStructuredJSONIRFieldNames)
    }

    func decodeRootHeistArgument(from arguments: CommandArgumentEnvelope) throws -> HeistArgument {
        guard let value = arguments.argumentValues["argument"] else { return .none }
        let data = try JSONEncoder().encode(value)
        switch HeistPlanning.decodeArgumentJSONResult(
            data,
            sourceURL: URL(fileURLWithPath: "run_heist-argument.json")
        ) {
        case .success(let argument, _):
            return argument
        case .failure(let diagnostics):
            throw buildDiagnosticFenceError(diagnostics)
        }
    }

    func validateRootHeistArgument(_ argument: HeistArgument, for plan: HeistPlan) throws {
        switch HeistPlanning.validateRootArgumentResult(argument, for: plan) {
        case .success:
            return
        case .failure(let diagnostics):
            throw buildDiagnosticFenceError(diagnostics)
        }
    }

    func buildDiagnosticFenceError(_ diagnostics: [HeistBuildDiagnostic]) -> FenceError {
        FenceError.invalidRequest(Self.renderBuildDiagnostics(diagnostics))
    }

    static func renderBuildDiagnostics(_ diagnostics: [HeistBuildDiagnostic]) -> String {
        guard !diagnostics.isEmpty else { return "Heist planning failed." }
        return diagnostics.map(\.renderedMessage).joined(separator: "\n")
    }

}
