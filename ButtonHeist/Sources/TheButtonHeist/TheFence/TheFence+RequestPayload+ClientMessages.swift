import Foundation

import TheScore

@ButtonHeistActor
extension TheFence {

    func clientMessageExecutionPlan(for request: ParsedRequest) throws -> ClientMessageExecutionPlan {
        let timeout = try request.executionTimeout
        let messages = try request.command.descriptor.clientMessages(for: request)
        return ClientMessageExecutionPlan(
            messages: messages,
            timeout: timeout,
            recordsCompletion: request.command != .getPasteboard
        )
    }
}

extension FenceCommandDescriptor {

    @ButtonHeistActor
    func clientMessages(for request: TheFence.ParsedRequest) throws -> [ClientMessage] {
        guard request.command == command else {
            throw FenceError.invalidRequest(
                "descriptor \"\(canonicalName)\" cannot lower command \"\(request.command.rawValue)\""
            )
        }
        return try request.payload.clientMessages(command: command)
    }
}

private extension TheFence.RequestPayload {

    func clientMessages(command: TheFence.Command) throws -> [ClientMessage] {
        switch self {
        case .gesture(let payload):
            return [payload.clientMessage]
        case .scroll(let payload):
            return [payload.clientMessage]
        case .accessibility(let payload):
            return try payload.clientMessages()
        case .rotor(let target):
            return [.rotor(target)]
        case .typeText(let target):
            return [.typeText(target)]
        case .editAction(let target):
            return [.editAction(target)]
        case .setPasteboard(let target):
            return [.setPasteboard(target)]
        case .none where command == .dismissKeyboard:
            return [.resignFirstResponder]
        case .none where command == .getPasteboard:
            return [.getPasteboard]
        case .waitFor(let target):
            return [.waitFor(target)]
        case .waitForChange(let payload):
            return [.waitForChange(WaitForChangeTarget(
                expect: payload.expectation,
                timeout: payload.timeout
            ))]
        case .none, .getInterface, .screen, .artifact, .startRecording, .connect,
             .runBatch, .archiveSession, .startHeist, .stopHeist, .playHeist:
            throw FenceError.invalidRequest("command \"\(command.rawValue)\" is not an executable action command")
        }
    }
}

private extension TheFence.ParsedRequest {

    var executionTimeout: TimeInterval {
        get throws {
            switch payload {
            case .scroll(.elementSearch), .typeText:
                return Timeouts.longActionSeconds
            case .waitFor(let target):
                return target.resolvedTimeout + 5
            case .waitForChange(let payload):
                let target = WaitForChangeTarget(expect: payload.expectation, timeout: payload.timeout)
                return target.resolvedTimeout + 5
            case .none where command == .getPasteboard:
                return Timeouts.healthSeconds
            default:
                return Timeouts.actionSeconds
            }
        }
    }
}
