#if canImport(UIKit)
#if DEBUG
import UIKit

import ThePlans
import TheScore

/// The getaway driver — runs comms between the wire and the crew.
///
/// TheGetaway owns message routing between the transport and crew members.
/// Transport wiring, encoding, broadcast, and status construction live in
/// focused extension files so this root stays a coordinator.
@MainActor
final class TheGetaway {

    // MARK: - Crew References (not owned)

    let muscle: TheMuscle
    let brains: TheBrains

    /// Identity info provided by TheInsideJob for ServerInfo responses.
    struct ServerIdentity {
        let sessionId: UUID
        let effectiveInstanceId: String
        var tlsActive: Bool
    }

    var identity: ServerIdentity
    let pongPayload: PongPayload

    /// Current transport — set by `wireTransport`, cleared on teardown.
    weak var transport: ServerTransport?

    /// Single long-lived consumer Task for `transport.events`. Cancelled on
    /// `tearDown()`; the for-await loop also exits when the transport finishes
    /// its event continuation in `stop()`.
    var eventConsumerTask: Task<Void, Never>?

    // MARK: - Init

    init(muscle: TheMuscle, brains: TheBrains, identity: ServerIdentity) {
        self.muscle = muscle
        self.brains = brains
        self.identity = identity
        self.pongPayload = Self.makePongPayload(identity: identity)
    }

    // MARK: - Message Dispatch

    func handleClientMessage(_ admitted: AdmittedClientMessage, respond: @escaping (Data) -> Void) async {
        let clientId = admitted.clientId
        let envelope = admitted.envelope
        let requestId = envelope.requestId
        let message = envelope.message

        insideJobLogger.debug("Received from client \(clientId): \(String(describing: message).prefix(40))")

        switch message {
        case .clientHello, .authenticate:
            insideJobLogger.fault("Protocol message reached app dispatch after admission")
            sendMessage(
                .error(ServerError(
                    kind: .validationError,
                    message: "Protocol messages are handled by admission before app dispatch."
                )),
                requestId: requestId,
                respond: respond
            )
        case .requestInterface(let query):
            insideJobLogger.debug("Interface requested by client \(clientId)")
            await sendInterface(query: query, requestId: requestId, respond: respond)
        case .ping:
            await muscle.noteClientActivity(clientId)
            sendMessage(.pong(pongPayload.withServerTimestamp()), requestId: requestId, respond: respond)
        case .status:
            sendMessage(.status(await makeStatusPayload()), requestId: requestId, respond: respond)

        // Observation
        case .getPasteboard:
            let result = brains.executePasteboardRead()
            sendMessage(.actionResult(result), requestId: requestId, respond: respond)
        case .requestScreen:
            await handleScreen(requestId: requestId, respond: respond)
        case .runtimeAction(let command):
            let actionResult = await executeDirectRuntimeAction(command)
            await recordAndRespond(
                command: message,
                actionResult: actionResult,
                requestId: requestId,
                respond: respond
            )
        case .heistPlan(let run):
            let actionResult = await brains.executeHeistPlan(run.plan, argument: run.argument)
            await recordAndRespond(
                command: message,
                actionResult: actionResult,
                requestId: requestId,
                respond: respond
            )
        }
    }

    private func executeDirectRuntimeAction(_ command: HeistActionCommand) async -> ActionResult {
        let method = actionMethod(for: command)
        guard command.durableHeistActionFailure != nil else {
            var builder = ActionResultBuilder()
            builder.message = "Direct runtimeAction accepts only transient non-durable commands; durable commands must run as heistPlan"
            return builder.failure(method: method, errorKind: .validationError)
        }
        guard brains.semanticObservationIsActive else {
            return brains.runtimeInactiveResult(method: method)
        }
        do {
            return await brains.executeRuntimeAction(try command.resolveForRuntimeDispatch(in: .empty))
        } catch {
            var builder = ActionResultBuilder()
            builder.message = "Could not resolve direct runtime action: \(error)"
            return builder.failure(method: method, errorKind: .validationError)
        }
    }

    private func actionMethod(for command: HeistActionCommand) -> ActionMethod {
        switch command {
        case .activate:
            return .activate
        case .increment:
            return .increment
        case .decrement:
            return .decrement
        case .customAction:
            return .customAction
        case .rotor:
            return .rotor
        case .typeText:
            return .typeText
        case .mechanicalTap:
            return .syntheticTap
        case .mechanicalLongPress:
            return .syntheticLongPress
        case .mechanicalSwipe:
            return .syntheticSwipe
        case .mechanicalDrag:
            return .syntheticDrag
        case .viewportScroll:
            return .scroll
        case .viewportScrollToVisible:
            return .scrollToVisible
        case .viewportScrollToEdge:
            return .scrollToEdge
        case .editAction:
            return .editAction
        case .setPasteboard:
            return .setPasteboard
        case .takeScreenshot:
            return .takeScreenshot
        case .dismissKeyboard:
            return .resignFirstResponder
        }
    }

    private func recordAndRespond(
        command: ClientMessage,
        actionResult: ActionResult,
        requestId: String?,
        respond: @escaping (Data) -> Void
    ) async {
        sendMessage(
            .actionResult(actionResult),
            requestId: requestId,
            respond: respond
        )
        await brains.recordSentState()
    }

    func sendInterface(
        query: InterfaceQuery = InterfaceQuery(),
        requestId: String? = nil,
        respond: @escaping (Data) -> Void
    ) async {
        switch await brains.observeInterface(query) {
        case .success(let interface):
            insideJobLogger.info("Interface: \(interface.projectedElements.count) elements")
            sendMessage(
                .interface(interface),
                requestId: requestId,
                respond: respond
            )
            await brains.recordSentState()
        case .failure(let error):
            sendMessage(.error(ServerError(kind: .general, message: error.message)), requestId: requestId, respond: respond)
        }
    }

    // MARK: - Screen Capture

    func handleScreen(requestId: String? = nil, respond: @escaping (Data) -> Void) async {
        insideJobLogger.debug("Screen requested")

        switch await brains.captureScreenPayload() {
        case .success(let payload):
            sendMessage(.screen(payload), requestId: requestId, respond: respond)
            insideJobLogger.debug("Screen sent: \(payload.pngData.count) base64 characters")
        case .failure(let failure):
            sendMessage(.error(ServerError(kind: .general, message: failure.message)), requestId: requestId, respond: respond)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
