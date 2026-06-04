import Foundation

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
        return RunHeistRequest(plan: try heistPlan(from: arguments))
    }

    func heistStep(for request: ParsedRequest) throws -> HeistStep {
        guard request.command.descriptor.isDurableHeistPrimitive else {
            throw HeistStepPlanBuildError(
                message: "command \"\(request.command.rawValue)\" is not a durable heist primitive"
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

        return .action(try ActionStep(
            command: message,
            expectation: actionExpectationStep(for: request)
        ))
    }
}

private extension TheFence {

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
}
