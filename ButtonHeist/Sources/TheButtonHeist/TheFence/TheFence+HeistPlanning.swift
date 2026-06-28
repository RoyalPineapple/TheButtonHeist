import Foundation

import ThePlans
import TheScore

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
                return Self.diagnostic(code: .performWrongStepCount)
            case .unsupportedStep:
                return Self.diagnostic(code: .performUnsupportedStep)
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

        private static func diagnostic(code: HeistBuildDiagnosticCode) -> HeistBuildDiagnostic {
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
            droppingPlanKeys: ["argument"]
        )
        let argument = try decodeRootHeistArgument(from: arguments)
        try validateRootHeistArgument(argument, for: plan)
        return RunHeistRequest(plan: plan, argument: argument)
    }

    func loadInlinePerformStepSource(_ source: String) throws -> HeistPlan {
        switch HeistPlanning.loadValidatedPlanResult(from: HeistPlanLoadRequest(
            commandName: Command.perform.rawValue,
            source: .inlineDSL(
                """
                HeistPlan {
                \(source)
                }
                """
            )
        )) {
        case .success(let plan, _):
            return plan
        case .failure(let diagnostics):
            throw performStepSourceLoadError(for: diagnostics)
        }
    }

    func performStepSourceLoadError(for diagnostics: [HeistBuildDiagnostic]) -> FenceError {
        guard Self.containsPerformUnsupportedStepDiagnostic(diagnostics) else {
            return buildDiagnosticFenceError(diagnostics)
        }
        return buildDiagnosticFenceError([PerformStepValidationError.unsupportedStep.diagnostic])
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
                droppingPlanKeys: ["detail"]
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
                droppingPlanKeys: ["heist"]
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
        droppingPlanKeys: Set<String> = []
    ) throws -> HeistPlan {
        // Admission: accept exactly one public source shape for a plan. ThePlans
        // then returns a RuntimeSafety-validated executable `HeistPlan`.
        try CommandArgumentEnvelopeLimits.validateHeistPlanSource(arguments, field: commandName)
        switch HeistPlanning.loadValidatedPlanResult(from: HeistPlanSourceAdmissionRequest(
            commandName: commandName,
            path: try arguments.schemaString("path"),
            inlineDSL: try arguments.schemaString("plan"),
            rawStructuredJSONIRFields: rawStructuredJSONIRFields(in: arguments, dropping: droppingPlanKeys)
        )) {
        case .success(let plan, _):
            return plan
        case .failure(let diagnostics):
            throw buildDiagnosticFenceError(diagnostics)
        }
    }

    func loadInlineButtonHeistSource(_ source: String, commandName: String) throws -> HeistPlan {
        switch HeistPlanning.loadValidatedPlanResult(from: HeistPlanLoadRequest(
            commandName: commandName,
            source: .inlineDSL(source)
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
        try validateRootHeistArgumentPayload(value)
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

    func validateRootHeistArgumentPayload(_ value: HeistValue) throws {
        guard case .object(let object) = value,
              object["type"] == .string(HeistParameterKind.elementTarget.rawValue),
              let target = object["target"] else {
            return
        }
        try Self.validateElementPredicatePayloadStringMatches(target, field: "argument.target")
        guard case .object(let targetObject) = target else { return }
        let allowedTargetKeys = Set(ElementTarget.inlineFieldNames)
        guard let unknownKey = targetObject.keys.sorted().first(where: { !allowedTargetKeys.contains($0) }) else {
            return
        }
        throw SchemaValidationError(
            field: "argument.target.\(unknownKey)",
            observed: targetObject[unknownKey]?.schemaObservedDescription ?? "missing",
            expected: "valid argument.target property"
        )
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

    static func containsPerformUnsupportedStepDiagnostic(_ diagnostics: [HeistBuildDiagnostic]) -> Bool {
        diagnostics.contains { diagnostic in
            diagnostic.code == .sourceWaitForGate
        }
    }

}
