import Foundation

import ThePlans
import TheScore

extension TheFence {

    struct RunHeistRequest {
        let plan: HeistPlan
        let argument: HeistArgument
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

    /// Canonical `HeistPlan` root fields that constitute a structured inline plan.
    /// `path`, `plan`, and these fields are mutually exclusive plan sources. These
    /// keys are intentionally not present in public descriptors; they remain here
    /// only so generated/internal callers can be rejected or decoded by explicit
    /// lower-level tests without making raw JSON IR an advertised authoring surface.
    static let inlinePlanFieldKeys: Set<String> = ["version", "name", "parameter", "definitions", "body"]

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

private extension TheFence {

    func decodeRuntimeValidatedHeistPlanSource(
        from arguments: CommandArgumentEnvelope,
        commandName: String,
        droppingPlanKeys: Set<String> = [],
        acceptsInlinePlanSource: Bool
    ) throws -> HeistPlan {
        try CommandArgumentEnvelopeLimits.validateHeistPlanSource(arguments, field: commandName)

        let path = try arguments.schemaString("path")
        let plan = try arguments.schemaString("plan")
        guard acceptsInlinePlanSource || plan == nil else {
            throw FenceError.invalidRequest(
                "\(commandName) does not accept inline ButtonHeist source; use path"
            )
        }
        let hasInlinePlan = arguments.argumentValues.keys.contains { Self.inlinePlanFieldKeys.contains($0) }
        let sourceCount = [path != nil, plan != nil, hasInlinePlan].filter { $0 }.count
        guard sourceCount == 1 else {
            throw FenceError.invalidRequest(
                "\(commandName) accepts exactly one plan source: path or plan. " +
                "Raw JSON IR fields are internal and cannot be combined with public sources."
            )
        }

        if let path {
            return try loadHeistPlan(fromArtifactPath: path, commandName: commandName)
        }
        if let plan {
            return try loadInlinePlanSource(plan, commandName: commandName)
        }
        return try loadInlineHeistPlan(from: arguments, commandName: commandName, dropping: droppingPlanKeys)
    }

    /// Read a heist plan from a `.heist` package artifact the operator handed us.
    ///
    /// `.heist` is the enforced run artifact: TheFence selects the source, then
    /// asks ThePlans' heist planning boundary for a validated `HeistPlan`. The plan
    /// reaches the runtime as Swift objects rather than surviving a
    /// JSON→parameter→JSON round-trip. The package's `plan.json` is internal to
    /// the artifact and is not itself a run input. Local Swift source is compiled
    /// by the CLI authoring path, not here.
    ///
    /// The plan is run exactly as authored — the fence does not stamp the file
    /// name into the plan's `name`. `name` is a Swift-identifier-constrained
    /// semantic field (it resolves heist definitions and invocations); a file
    /// name such as `bh-demo-smoke` is not a valid identifier and would fail
    /// runtime validation, silently reducing the run to zero steps. Run naming
    /// for reports is derived from the path at the report layer, not here.
    func loadHeistPlan(fromArtifactPath path: String, commandName: String) throws -> HeistPlan {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FenceError.invalidRequest("\(commandName) path must not be empty")
        }
        let url = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        guard url.pathExtension.lowercased() == "heist" else {
            throw FenceError.invalidRequest(
                "\(commandName) path must be a .heist package artifact for \(path); " +
                "raw .json plan IR is internal to the package, not a run input."
            )
        }
        do {
            return try HeistPlanning.readPlan(from: url)
        } catch let error as HeistArtifactCodecError {
            throw FenceError.invalidRequest(error.description)
        }
    }

    func loadInlineHeistPlan(
        from arguments: CommandArgumentEnvelope,
        commandName: String,
        dropping keys: Set<String> = []
    ) throws -> HeistPlan {
        var values = arguments.argumentValues
        values.removeValue(forKey: "requestId")
        for key in keys {
            values.removeValue(forKey: key)
        }
        let data = try JSONEncoder().encode(HeistValue.object(values))
        do {
            return try HeistPlanning.decodePlanJSON(
                data,
                sourceURL: URL(fileURLWithPath: "\(commandName)-inline-plan.json")
            )
        } catch {
            throw FenceError.invalidRequest(String(describing: error))
        }
    }

    func loadInlinePlanSource(_ source: String, commandName: String) throws -> HeistPlan {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FenceError.invalidRequest("\(commandName) plan must not be empty")
        }
        do {
            return try HeistPlanning.compileHeistPlanSource(
                source,
                sourceName: "\(commandName)-inline.plan"
            )
        } catch let error as HeistPlanSourceCompilerError {
            throw FenceError.invalidRequest(error.description)
        } catch {
            throw FenceError.invalidRequest(String(describing: error))
        }
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
        let command = try HeistActionCommand(clientMessage: message)
        if let failure = command.durableHeistActionFailure {
            throw HeistStepPlanBuildError(
                message: """
                command "\(commandName)" is not accepted by the heist primitive payload gate: \(failure)
                """
            )
        }
    }
}
