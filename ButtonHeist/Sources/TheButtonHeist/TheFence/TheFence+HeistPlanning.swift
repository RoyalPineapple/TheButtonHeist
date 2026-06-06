import Foundation

@_spi(ButtonHeistInternals) import ThePlans
import TheScore

extension TheFence {

    struct RunHeistRequest {
        let plan: HeistPlan
        let argument: HeistArgument
    }

    struct ListHeistsRequest {
        let catalog: HeistCatalog
    }

    struct DescribeHeistRequest {
        let description: HeistDescription
    }

    struct HeistStepPlanBuildError: Error {
        let message: String
    }

    /// Canonical `HeistPlan` root fields that constitute an inline plan. A
    /// `path` may not be combined with any of them — exactly one input source.
    static let inlinePlanFieldKeys: Set<String> = ["version", "name", "parameter", "definitions", "body"]

    func decodeRunHeistRequest(_ arguments: CommandArgumentEnvelope) throws -> RunHeistRequest {
        let plan = try decodeRuntimeValidatedHeistPlanSource(
            from: arguments,
            commandName: Command.runHeist.rawValue,
            droppingPlanKeys: ["argument"]
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
            let plan = try decodeRuntimeValidatedHeistPlanSource(
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
        droppingPlanKeys: Set<String> = []
    ) throws -> HeistPlan {
        try CommandArgumentEnvelopeLimits.validateHeistPlanSource(arguments, field: commandName)

        let plan: HeistPlan
        if let path = try arguments.schemaString("path") {
            // Reject `path` combined with ANY inline plan field before touching
            // the artifact — heist plan source commands accept exactly one plan
            // source, plus command-specific selector fields.
            guard arguments.argumentValues.keys.allSatisfy({ !Self.inlinePlanFieldKeys.contains($0) }) else {
                throw FenceError.invalidRequest("\(commandName) accepts either a path or an inline plan, not both")
            }
            plan = try loadHeistPlan(fromArtifactPath: path, commandName: commandName)
        } else {
            plan = try translateRuntimeValidationErrors {
                try decodeRawHeistPlanSource(from: arguments, dropping: droppingPlanKeys)
                    .validatedForRuntime()
            }
        }
        return plan
    }

    func translateRuntimeValidationErrors<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as HeistPlanValidationError {
            throw FenceError.invalidRequest(error.description)
        }
    }

    /// Read a heist plan from a `.heist` package artifact the operator handed us.
    ///
    /// `.heist` is the enforced run artifact: the fence — not the caller — opens
    /// the package and turns it into a `HeistPlan` value through the single
    /// canonical reader (`HeistArtifactCodec.readPlan`), so the plan reaches the
    /// runtime as Swift objects rather than surviving a JSON→parameter→JSON
    /// round-trip. The package's `plan.json` is internal to the artifact and is
    /// not itself a run input. Swift DSL source is compiled by the CLI authoring
    /// path, not here.
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
            // The artifact codec decodes and validates the plan before
            // returning a HeistPlan that is ready for runtime behavior.
            return try HeistArtifactCodec.readPlan(from: url)
        } catch let error as HeistArtifactCodecError {
            throw FenceError.invalidRequest(error.description)
        }
    }

    func decodeRawHeistPlanSource(
        from arguments: CommandArgumentEnvelope,
        dropping keys: Set<String> = []
    ) throws -> UnvalidatedHeistPlan {
        var values = arguments.argumentValues
        values.removeValue(forKey: "requestId")
        for key in keys {
            values.removeValue(forKey: key)
        }
        let data = try JSONEncoder().encode(HeistValue.object(values))
        do {
            return try JSONDecoder().decode(UnvalidatedHeistPlan.self, from: data)
        } catch DecodingError.dataCorrupted(let context) {
            throw SchemaValidationError(
                field: context.codingPath.map(\.stringValue).joined(separator: "."),
                observed: "invalid heist plan",
                expected: context.debugDescription
            )
        } catch DecodingError.keyNotFound(let key, let context) {
            throw SchemaValidationError(
                field: (context.codingPath + [key]).map(\.stringValue).joined(separator: "."),
                observed: "missing",
                expected: "heist plan field"
            )
        } catch DecodingError.typeMismatch(_, let context),
                DecodingError.valueNotFound(_, let context) {
            throw SchemaValidationError(
                field: context.codingPath.map(\.stringValue).joined(separator: "."),
                observed: "invalid heist plan",
                expected: context.debugDescription
            )
        } catch {
            throw FenceError.invalidRequest("Invalid heist plan: \(error.localizedDescription)")
        }
    }

    func decodeRootHeistArgument(from arguments: CommandArgumentEnvelope) throws -> HeistArgument {
        guard let value = arguments.argumentValues["argument"] else { return .none }
        let data = try JSONEncoder().encode(value)
        do {
            return try JSONDecoder().decode(HeistArgument.self, from: data)
        } catch DecodingError.dataCorrupted(let context) {
            throw SchemaValidationError(
                field: (["argument"] + context.codingPath.map(\.stringValue)).joined(separator: "."),
                observed: "invalid heist argument",
                expected: context.debugDescription
            )
        } catch DecodingError.keyNotFound(let key, let context) {
            throw SchemaValidationError(
                field: (["argument"] + (context.codingPath + [key]).map(\.stringValue)).joined(separator: "."),
                observed: "missing",
                expected: "heist argument field"
            )
        } catch DecodingError.typeMismatch(_, let context),
                DecodingError.valueNotFound(_, let context) {
            throw SchemaValidationError(
                field: (["argument"] + context.codingPath.map(\.stringValue)).joined(separator: "."),
                observed: "invalid heist argument",
                expected: context.debugDescription
            )
        } catch {
            throw FenceError.invalidRequest("Invalid heist argument: \(error.localizedDescription)")
        }
    }

    func validateRootHeistArgument(_ argument: HeistArgument, for plan: HeistPlan) throws {
        do {
            _ = try HeistExecutionEnvironment.empty.binding(argument: argument, to: plan.parameter)
        } catch {
            throw FenceError.invalidRequest("run_heist argument does not match root heist parameter: \(error)")
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
