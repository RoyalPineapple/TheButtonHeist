import Foundation

import ThePlans
import TheScore

extension TheFence {

    struct RunHeistRequest {
        let plan: HeistPlan
    }

    struct HeistStepPlanBuildError: Error {
        let message: String
    }

    func decodeRunHeistRequest(_ arguments: CommandArgumentEnvelope) throws -> RunHeistRequest {
        try CommandArgumentEnvelopeLimits.validateRunHeist(arguments)
        if let inputPath = try arguments.schemaString("input") {
            guard arguments.argumentValues["body"] == nil else {
                throw FenceError.invalidRequest("run_heist accepts either an input path or an inline plan, not both")
            }
            return RunHeistRequest(plan: try loadHeistPlan(fromInputPath: inputPath))
        }
        return RunHeistRequest(plan: try heistPlan(from: arguments))
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

    /// Read a heist plan from a `.heist` package artifact the operator handed us.
    ///
    /// `.heist` is the enforced run artifact: the fence — not the caller — opens
    /// the package and turns it into a `HeistPlan` value, so the plan reaches the
    /// runtime as Swift objects rather than surviving a JSON→parameter→JSON
    /// round-trip. The package's `plan.json` is internal to the artifact and is
    /// not itself a run input. Swift DSL source is compiled by the CLI authoring
    /// path, not here. The run is named after the package when the plan is
    /// anonymous.
    func loadHeistPlan(fromInputPath path: String) throws -> HeistPlan {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FenceError.invalidRequest("run_heist input path must not be empty")
        }
        let url = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        guard url.pathExtension.lowercased() == "heist" else {
            throw FenceError.invalidRequest(
                "run_heist input must be a .heist package artifact for \(path); " +
                "raw .json plan IR is internal to the package, not a run input."
            )
        }
        let plan: HeistPlan
        do {
            plan = try HeistArtifactCodec.read(from: url).plan
        } catch let error as HeistArtifactCodecError {
            throw FenceError.invalidRequest(error.description)
        }
        try plan.assertRuntimeAdmissible()
        return plan.named(url.deletingPathExtension().lastPathComponent)
    }

    func heistPlan(from arguments: CommandArgumentEnvelope) throws -> HeistPlan {
        var values = arguments.argumentValues
        values.removeValue(forKey: "requestId")
        let data = try JSONEncoder().encode(HeistValue.object(values))
        do {
            return try JSONDecoder().decode(HeistPlan.self, from: data)
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
