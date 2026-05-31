#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

struct AdmittedClientMessage: Sendable {
    let clientId: Int
    let envelope: RequestEnvelope
}

enum ClientAdmission: Sendable {
    case admitted(AdmittedClientMessage)
    case handled
}

struct MuscleAdmissionEffect {
    var outputs: [MuscleAdmissionOutput] = []
    var delayedDisconnectClientId: Int?
    var approvalPromptClientId: Int?
    var dismissApprovalPrompt = false

    static let none = MuscleAdmissionEffect()

    static func response(
        _ message: ServerMessage,
        requestId: String? = nil,
        respond: @escaping TheMuscleAdmission.ResponseHandler,
        disconnect clientId: Int? = nil
    ) -> MuscleAdmissionEffect {
        MuscleAdmissionEffect(
            outputs: [.response(message, requestId: requestId, respond: respond)],
            delayedDisconnectClientId: clientId
        )
    }

    static func client(
        _ message: ServerMessage,
        requestId: String? = nil,
        clientId: Int,
        disconnect: Bool = false
    ) -> MuscleAdmissionEffect {
        MuscleAdmissionEffect(
            outputs: [.client(message, requestId: requestId, clientId: clientId)],
            delayedDisconnectClientId: disconnect ? clientId : nil
        )
    }
}

enum MuscleAdmissionOutput {
    case response(ServerMessage, requestId: String?, respond: TheMuscleAdmission.ResponseHandler)
    case client(ServerMessage, requestId: String?, clientId: Int)
}

struct MuscleAuthentication {
    let clientId: Int
    let address: String
    let driverIdentity: String
    let respond: TheMuscleAdmission.ResponseHandler
    let source: MuscleAuthenticationSource
}

enum MuscleAuthenticationSource {
    case token
    case uiApproval(approvedToken: String)
}

enum MuscleAdmissionDecision {
    case admitted(AdmittedClientMessage)
    case handled(MuscleAdmissionEffect)
    case authenticate(MuscleAuthentication)
}

/// Owns the unauthenticated ButtonHeist handshake and client auth phases.
struct TheMuscleAdmission {
    typealias ResponseHandler = @Sendable (Data) -> Void

    private var authentication: MuscleAuthenticationFlow

    init(tokenSource: SessionTokenSource, maxFailedAttempts: Int, lockoutDuration: TimeInterval) {
        self.authentication = MuscleAuthenticationFlow(
            tokenSource: tokenSource,
            maxFailedAttempts: maxFailedAttempts,
            lockoutDuration: lockoutDuration
        )
    }

    var authenticatedClientIDs: Set<Int> {
        authentication.authenticatedClientIDs
    }

    mutating func registerClientAddress(_ clientId: Int, address: String) {
        authentication.registerClientAddress(clientId, address: address)
    }

    mutating func installAuthenticatedForTest(_ clientId: Int, address: String, driverIdentity: String) {
        authentication.installAuthenticatedForTest(clientId, address: address, driverIdentity: driverIdentity)
    }

    mutating func removeAllClients() {
        authentication.removeAllClients()
    }

    func contains(_ clientId: Int) -> Bool {
        authentication.contains(clientId)
    }

    mutating func admitClientMessage(
        _ clientId: Int,
        data: Data,
        respond: @escaping ResponseHandler,
        uiApprovalUnavailableDiagnostic: SessionLease.SessionLockDiagnostic?
    ) -> MuscleAdmissionDecision {
        authentication.admitClientMessage(
            clientId,
            data: data,
            respond: respond,
            uiApprovalUnavailableDiagnostic: uiApprovalUnavailableDiagnostic
        )
    }

    mutating func completeAuthentication(_ authentication: MuscleAuthentication) -> MuscleAdmissionEffect {
        self.authentication.completeAuthentication(authentication)
    }

    func rejectForSessionLock(
        _ clientId: Int,
        diagnostic: SessionLease.SessionLockDiagnostic,
        respond: @escaping ResponseHandler
    ) -> MuscleAdmissionEffect {
        authentication.rejectForSessionLock(clientId, diagnostic: diagnostic, respond: respond)
    }

    mutating func denyClient(_ clientId: Int) -> MuscleAdmissionEffect {
        authentication.denyClient(clientId)
    }

    mutating func approvalAuthentication(_ clientId: Int) -> MuscleAuthentication? {
        authentication.approvalAuthentication(clientId)
    }

    mutating func removeClient(_ clientId: Int) -> MuscleAdmissionEffect {
        authentication.removeClient(clientId)
    }

    func authenticationDeadline(_ clientId: Int, deadlineSeconds: UInt64) -> MuscleAdmissionEffect {
        authentication.authenticationDeadline(clientId, deadlineSeconds: deadlineSeconds)
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
