#if canImport(UIKit)
#if DEBUG
import UIKit

import ThePlans
@_spi(ButtonHeistInternals) import TheScore

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
        let launchId: ServerLaunchID
        let effectiveInstanceId: InsideJobInstanceID
        var tlsActive: Bool
    }

    var identity: ServerIdentity
    let pongPayload: PongPayload

    struct TransportWiringAttempt {
        let transport: ServerTransport
        let deliveryGeneration: ClientDelivery.Generation
    }

    struct WiredTransportAdmission {
        let attempt: TransportWiringAttempt

        var transport: ServerTransport {
            attempt.transport
        }
    }

    enum TransportWiringOutcome {
        case admitted(WiredTransportAdmission)
        case rejected
    }

    struct WiredTransport {
        let attempt: TransportWiringAttempt
        let eventConsumer: Task<Void, Never>
    }

    enum TransportWiringState {
        case unwired
        case wiring(TransportWiringAttempt)
        case wired(WiredTransport)

        var transport: ServerTransport? {
            switch self {
            case .unwired:
                nil
            case .wiring(let attempt):
                attempt.transport
            case .wired(let session):
                session.attempt.transport
            }
        }

        var eventConsumer: Task<Void, Never>? {
            guard case .wired(let session) = self else { return nil }
            return session.eventConsumer
        }

        var deliveryGeneration: ClientDelivery.Generation? {
            switch self {
            case .unwired:
                nil
            case .wiring(let attempt):
                attempt.deliveryGeneration
            case .wired(let session):
                session.attempt.deliveryGeneration
            }
        }

        func admits(_ attempt: TransportWiringAttempt) -> Bool {
            guard case .wiring(let current) = self else { return false }
            return current.deliveryGeneration == attempt.deliveryGeneration
        }

        func admitsEvent(generation: ClientDelivery.Generation) -> Bool {
            guard case .wired(let current) = self else { return false }
            return current.attempt.deliveryGeneration == generation
        }
    }

    /// Transport wiring is one explicit state machine so teardown cannot leave a
    /// stale transport or consumer behind while callback installation is suspended.
    var transportWiring: TransportWiringState = .unwired
    private var latestIssuedDeliveryGenerationRawValue: UInt64 = 0

    var pauseBeforeTransportCallbackBeginForTesting: (@MainActor @Sendable () async -> Void)?
    var pauseBeforeTransportCallbackInstallationForTesting: (@MainActor @Sendable () async -> Void)?
    var pauseAfterClientRequestAdmissionForTesting: (
        @MainActor @Sendable (ClientDelivery.Generation) async -> Void
    )?
    var observeClientRequestCompletionForTesting: (
        @MainActor @Sendable (ClientDelivery.Generation) -> Void
    )?

    var transport: ServerTransport? {
        transportWiring.transport
    }

    func issueDeliveryGeneration() -> ClientDelivery.Generation {
        precondition(
            latestIssuedDeliveryGenerationRawValue < .max,
            "ClientDelivery.Generation exhausted"
        )
        latestIssuedDeliveryGenerationRawValue += 1
        return ClientDelivery.Generation(rawValue: latestIssuedDeliveryGenerationRawValue)
    }

    /// Frames are admitted and executed in per-client order. Transport
    /// lifecycle events never wait for these consumers.
    var clientRequestPipelines: [Int: ClientRequestPipeline] = [:]

    // MARK: - Init

    init(muscle: TheMuscle, brains: TheBrains, identity: ServerIdentity) {
        self.muscle = muscle
        self.brains = brains
        self.identity = identity
        self.pongPayload = Self.capturePongPayload(identity: identity)
    }

    // MARK: - Message Execution

    func executeClientMessage(
        _ admitted: AdmittedClientMessage,
        respond: @escaping SocketResponseHandler,
        generation: ClientDelivery.Generation
    ) async {
        let clientId = admitted.clientId
        let envelope = admitted.envelope
        let requestId = envelope.requestId
        let message = envelope.message

        switch message {
        case .clientHello, .authenticate:
            insideJobLogger.fault("Protocol message reached app dispatch after admission")
            await sendMessage(
                .error(ServerError(
                    kind: .validationError,
                    message: "Protocol messages are handled by admission before app dispatch."
                )),
                requestId: requestId,
                respond: respond,
                generation: generation
            )
        case .requestInterface(let query):
            await sendInterface(
                query: query,
                requestId: requestId,
                respond: respond,
                generation: generation
            )
        case .ping:
            await muscle.noteClientActivity(clientId)
            await sendMessage(
                .pong(pongPayload.withServerTimestamp()),
                requestId: requestId,
                respond: respond,
                generation: generation
            )
        case .status:
            await sendMessage(
                .status(await captureStatus()),
                requestId: requestId,
                respond: respond,
                generation: generation
            )

        // Observation
        case .getPasteboard:
            let result = brains.executePasteboardRead()
            await sendMessage(
                .actionResult(result),
                requestId: requestId,
                respond: respond,
                generation: generation
            )
        case .getAnnouncements:
            await sendMessage(
                .announcements(brains.capturedAnnouncements()),
                requestId: requestId,
                respond: respond,
                generation: generation
            )
        case .requestScreen(let payload):
            await sendScreen(
                mode: payload.mode,
                requestId: requestId,
                respond: respond,
                generation: generation
            )
        case .runtimeAction(let command):
            let actionResult = await executeDirectRuntimeAction(command)
            await sendActionResult(
                actionResult: actionResult,
                requestId: requestId,
                respond: respond,
                generation: generation
            )
        case .heistPlan(let run):
            let actionResult = await brains.executeHeistPlan(run.plan, argument: run.argument)
            await sendActionResult(
                actionResult: actionResult,
                requestId: requestId,
                respond: respond,
                generation: generation
            )
        }
    }

    func executeDirectRuntimeAction(_ command: HeistActionCommand) async -> ActionResult {
        let payload = actionPayload(for: command)
        guard command.durableHeistActionFailure != nil else {
            return .failure(
                payload: payload,
                failureKind: .validationError,
                message: "Direct runtimeAction accepts only transient non-durable commands; durable commands must run as heistPlan"
            )
        }
        guard brains.semanticObservationIsActive else {
            return brains.runtimeInactiveResult(payload: payload)
        }
        do {
            return await brains.executeRuntimeAction(try command.resolve(in: .empty))
        } catch {
            return .failure(
                payload: payload,
                failureKind: .validationError,
                message: "Could not resolve direct runtime action: \(error)"
            )
        }
    }

    private func actionPayload(for command: HeistActionCommand) -> ActionResult.Payload {
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
            return .rotor(nil)
        case .typeText:
            return .typeText(nil)
        case .oneFingerTap:
            return .oneFingerTap
        case .longPress:
            return .longPress
        case .swipe:
            return .swipe
        case .drag:
            return .drag
        case .scroll:
            return .scroll
        case .scrollToVisible:
            return .scrollToVisible
        case .scrollToEdge:
            return .scrollToEdge
        case .dismiss:
            return .dismiss
        case .magicTap:
            return .magicTap
        case .editAction:
            return .editAction
        case .setPasteboard:
            return .setPasteboard(nil)
        case .takeScreenshot:
            return .screenshot(nil)
        case .dismissKeyboard:
            return .dismissKeyboard
        }
    }

    private func sendActionResult(
        actionResult: ActionResult,
        requestId: RequestID?,
        respond: @escaping SocketResponseHandler,
        generation: ClientDelivery.Generation
    ) async {
        await sendMessage(
            .actionResult(actionResult),
            requestId: requestId,
            respond: respond,
            generation: generation
        )
    }

    func sendInterface(
        query: InterfaceQuery = InterfaceQuery(),
        requestId: RequestID? = nil,
        respond: @escaping SocketResponseHandler,
        generation: ClientDelivery.Generation
    ) async {
        switch await brains.observeInterface(query) {
        case .success(let interface):
            await sendMessage(
                .interface(interface),
                requestId: requestId,
                respond: respond,
                generation: generation
            )
        case .failure(let error):
            let message: ServerErrorMessage
            do {
                message = try ServerErrorMessage(validating: error.message)
            } catch {
                insideJobLogger.error("Failed to admit interface error response: \(error)")
                return
            }
            await sendMessage(
                .error(ServerError(kind: .general, message: message)),
                requestId: requestId,
                respond: respond,
                generation: generation
            )
        }
    }

    // MARK: - InterfaceObservation Capture

    func sendScreen(
        mode: ScreenCaptureMode = .raw,
        requestId: RequestID? = nil,
        respond: @escaping SocketResponseHandler,
        generation: ClientDelivery.Generation
    ) async {
        switch await brains.captureScreenPayload(mode: mode) {
        case .success(let payload, context: _):
            await sendMessage(
                .screen(payload),
                requestId: requestId,
                respond: respond,
                generation: generation
            )
        case .failure(let failure):
            let message: ServerErrorMessage
            do {
                message = try ServerErrorMessage(validating: failure.message)
            } catch {
                insideJobLogger.error("Failed to admit screen-capture error response: \(error)")
                return
            }
            await sendMessage(
                .error(ServerError(kind: .general, message: message)),
                requestId: requestId,
                respond: respond,
                generation: generation
            )
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
