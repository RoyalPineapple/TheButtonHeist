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

    struct HeistStepPlanBuildError: Error {
        let message: String
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
    }

    func decodePerformRequest(_ arguments: CommandArgumentEnvelope) throws -> PerformRequest {
        try CommandArgumentEnvelopeLimits.validateHeistPlanSource(arguments, field: Command.perform.rawValue)
        let source = try arguments.requiredSchemaString("step")
        let plan = try loadInlinePerformStepSource(source)
        let step = try performableStep(in: plan)
        return PerformRequest(plan: plan, step: step)
    }

    func decodeRunHeistRequest(_ arguments: CommandArgumentEnvelope) throws -> RunHeistRequest {
        let plan = try decodeRuntimeValidatedHeistPlanSource(
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
        try loadInlineButtonHeistSource(
            """
            HeistPlan {
            \(source)
            }
            """,
            commandName: Command.perform.rawValue
        )
    }

    func performableStep(in plan: HeistPlan) throws -> PerformableHeistStep {
        guard plan.definitions.isEmpty else {
            throw FenceError.invalidRequest(PerformStepValidationError.unsupportedStep.description)
        }
        guard plan.body.count == 1, let step = plan.body.first else {
            throw FenceError.invalidRequest(PerformStepValidationError.wrongStepCount(plan.body.count).description)
        }
        switch step {
        case .action(let action):
            guard action.command.isPerformPrimitive else {
                throw FenceError.invalidRequest(PerformStepValidationError.unsupportedStep.description)
            }
            return .action(action)
        case .wait(let wait):
            return .wait(wait)
        case .conditional, .waitForCases, .forEachElement, .forEachString, .warn, .fail, .heist, .invoke:
            throw FenceError.invalidRequest(PerformStepValidationError.unsupportedStep.description)
        }
    }

    func decodeListHeistsRequest(_ arguments: CommandArgumentEnvelope) throws -> ListHeistsRequest {
        let detail = try arguments.schemaEnum("detail", as: HeistCatalogDetail.self) ?? .summary
        do {
            let plan = try decodeRuntimeValidatedHeistPlanSource(
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
            let plan = try decodeRuntimeValidatedHeistPlanSource(
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

    func heistStep(for request: ParsedRequest) throws -> HeistStep {
        guard request.command.heistPrimitiveCommand != nil else {
            throw HeistStepPlanBuildError(
                message: "command \"\(request.command.rawValue)\" is not a heist primitive"
            )
        }

        let messages = try executableActionMessages(for: request)
        guard let message = messages.first, messages.count == 1 else {
            let commandName = request.command.rawValue
            throw HeistStepPlanBuildError(
                message: """
                heist action command "\(commandName)" expands to \(messages.count) actions; \
                express repeats as separate ordered steps
                """
            )
        }

        if case .wait(let target) = message {
            return .wait(WaitStep(
                predicate: target.predicate,
                timeout: target.resolvedTimeout
            ))
        }

        if request.command.payloadCheckedHeistPrimitiveCommand != nil {
            try validatePayloadCheckedHeistPrimitive(message, commandName: request.command.rawValue)
        }

        return .action(try ActionStep(
            command: message,
            expectation: actionExpectationStep(for: request)
        ))
    }
}

private extension HeistActionCommand {
    var isPerformPrimitive: Bool {
        switch self {
        case .activate, .increment, .decrement, .customAction, .rotor,
             .typeText, .mechanicalTap, .mechanicalLongPress, .mechanicalSwipe,
             .mechanicalDrag, .editAction, .setPasteboard, .dismissKeyboard:
            return true
        case .viewportScroll, .viewportScrollToVisible, .viewportScrollToEdge:
            return false
        }
    }
}

private extension TheFence {

    func decodeRuntimeValidatedHeistPlanSource(
        from arguments: CommandArgumentEnvelope,
        commandName: String,
        droppingPlanKeys: Set<String> = [],
        acceptsInlinePlanSource: Bool
    ) throws -> HeistPlan {
        try CommandArgumentEnvelopeLimits.validateHeistPlanSource(arguments, field: commandName)
        do {
            return try HeistPlanning.loadValidatedPlan(from: HeistPlanSourceRequest(
                commandName: commandName,
                path: try arguments.schemaString("path"),
                inlineButtonHeistSource: try arguments.schemaString("plan"),
                rawStructuredJSONIRFields: rawStructuredJSONIRFields(in: arguments, dropping: droppingPlanKeys),
                acceptsInlineButtonHeistSource: acceptsInlinePlanSource
            ))
        } catch let error as HeistPlanningError {
            throw FenceError.invalidRequest(error.description)
        }
    }

    func loadInlineButtonHeistSource(_ source: String, commandName: String) throws -> HeistPlan {
        do {
            return try HeistPlanning.loadValidatedPlan(from: HeistPlanSourceRequest(
                commandName: commandName,
                inlineButtonHeistSource: source
            ))
        } catch let error as HeistPlanningError {
            throw FenceError.invalidRequest(error.description)
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
        do {
            return try HeistPlanning.decodeArgumentJSON(
                data,
                sourceURL: URL(fileURLWithPath: "run_heist-argument.json")
            )
        } catch let error as HeistPlanningError {
            throw FenceError.invalidRequest(error.description)
        }
    }

    func validateRootHeistArgument(_ argument: HeistArgument, for plan: HeistPlan) throws {
        do {
            try HeistPlanning.validateRootArgument(argument, for: plan)
        } catch let error as HeistPlanningError {
            throw FenceError.invalidRequest(error.description)
        }
    }

    func actionExpectationStep(for request: ParsedRequest) -> WaitStep? {
        guard let expectation = request.expectationPayload.expectation else { return nil }
        return WaitStep(
            predicate: expectation,
            timeout: request.expectationPayload.postActionValidationTimeout ?? 10
        )
    }

    func validatePayloadCheckedHeistPrimitive(_ message: ClientMessage, commandName: String) throws {
        let command = try HeistActionCommand(internalDispatchMessage: message)
        if let failure = command.durableHeistActionFailure {
            throw HeistStepPlanBuildError(
                message: """
                command "\(commandName)" is not accepted by the heist primitive payload gate: \(failure)
                """
            )
        }
    }
}
