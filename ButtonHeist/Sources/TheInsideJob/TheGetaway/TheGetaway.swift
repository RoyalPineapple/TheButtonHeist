#if canImport(UIKit)
#if DEBUG
import UIKit

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
            handleScreen(requestId: requestId, respond: respond)
        case .wait(let target):
            let result = await brains.performWait(target: target)
            sendMessage(.actionResult(result), requestId: requestId, respond: respond)
            brains.recordSentState()

        // Interactions
        default:
            let actionResult = await brains.executeCommand(message)
            await recordAndRespond(
                command: message,
                actionResult: actionResult,
                requestId: requestId,
                respond: respond
            )
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
        brains.recordSentState()
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
            brains.recordSentState()
        case .failure(let error):
            sendMessage(.error(ServerError(kind: .general, message: error.message)), requestId: requestId, respond: respond)
        }
    }

    // MARK: - Screen Capture

    func handleScreen(requestId: String? = nil, respond: @escaping (Data) -> Void) {
        insideJobLogger.debug("Screen requested")

        guard brains.stash.commitVisibleObservation() != nil else {
            sendMessage(.error(ServerError(kind: .general, message: "Could not access accessibility tree")), requestId: requestId, respond: respond)
            return
        }

        guard let (image, bounds) = brains.stash.captureScreen() else {
            sendMessage(.error(ServerError(kind: .general, message: "Could not access app window")), requestId: requestId, respond: respond)
            return
        }

        guard let pngData = image.pngData() else {
            sendMessage(.error(ServerError(kind: .general, message: "Failed to encode screen as PNG")), requestId: requestId, respond: respond)
            return
        }

        let payload = ScreenPayload(
            pngData: pngData.base64EncodedString(),
            width: bounds.width,
            height: bounds.height,
            interface: brains.stash.interface()
        )

        sendMessage(.screen(payload), requestId: requestId, respond: respond)
        insideJobLogger.debug("Screen sent: \(pngData.count) bytes")
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
