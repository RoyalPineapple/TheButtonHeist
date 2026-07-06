#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit

import TheScore

@MainActor
extension TheInsideJob {
    func startRuntimeResourcesForStartup(attemptID: UUID) async throws -> InsideJobRuntimeResources {
        let resources = try await startRuntimeResources(
            phase: .startup,
            startupAttemptID: attemptID,
            idleTimerBaseline: UIApplication.shared.isIdleTimerDisabled,
            leavesStoppedOnFailure: true
        )
        logStartupSummary(
            actualPort: resources.actualPort,
            bonjourServiceName: resources.bonjourServiceName
        )
        return resources
    }

    func startRuntimeResourcesForResume(
        idleTimerBaseline: Bool
    ) async throws -> InsideJobRuntimeResources {
        try await startRuntimeResources(
            phase: .resume,
            startupAttemptID: nil,
            idleTimerBaseline: idleTimerBaseline,
            leavesStoppedOnFailure: false
        )
    }

    func stopRuntime() async {
        if case .resuming(let attempt) = serverPhase {
            attempt.task.cancel()
            await attempt.task.value
        }

        let resourcesToStop: InsideJobRuntimeResources?
        let startupTransportToStop: ServerTransport?
        let idleTimerBaseline: Bool?
        switch serverPhase {
        case .starting(let attempt):
            resourcesToStop = nil
            startupTransportToStop = attempt.transport
            idleTimerBaseline = nil
        case .running(let resources):
            resourcesToStop = resources
            startupTransportToStop = nil
            idleTimerBaseline = resources.idleTimerBaseline
        case .suspending(let suspension):
            resourcesToStop = suspension.resources
            startupTransportToStop = nil
            idleTimerBaseline = suspension.resources.idleTimerBaseline
        case .suspended(let suspended):
            resourcesToStop = nil
            startupTransportToStop = nil
            idleTimerBaseline = suspended.idleTimerBaseline
        case .resuming:
            resourcesToStop = nil
            startupTransportToStop = nil
            idleTimerBaseline = retainedIdleTimerBaseline
        case .stopping, .stopped:
            return
        }

        serverPhase = .stopping(InsideJobStopAttempt(id: UUID()))
        if let idleTimerBaseline {
            releaseRuntimeOwnedResources(policy: .stop, idleTimerBaseline: idleTimerBaseline)
        }
        await cleanupFailedTransportStartup(startupTransportToStop)
        await resourcesToStop?.transport.stop()

        serverPhase = .stopped
    }

    private func startRuntimeResources(
        phase: InsideJobRuntimeStartPhase,
        startupAttemptID: UUID?,
        idleTimerBaseline: Bool,
        leavesStoppedOnFailure: Bool
    ) async throws -> InsideJobRuntimeResources {
        let token = try requireRuntimeToken(phase: phase)
        insideJobLogger.info("TLS PSK material ready")

        let transport = transportFactory(token, runtimeConfiguration.allowedScopes)
        if let startupAttemptID {
            serverPhase = .starting(InsideJobStartAttempt(id: startupAttemptID, transport: transport))
        }
        installTransportOverflowHandler(transport)
        await getaway.wireTransport(transport)

        let exposure = ServerExposure(
            allowedScopes: runtimeConfiguration.allowedScopes,
            addressFamily: runtimeConfiguration.addressFamily
        )
        do {
            let actualPort = try await transport.start(
                port: runtimeConfiguration.preferredPort,
                bindToLoopback: exposure.bindsToLoopbackOnly,
                addressFamily: exposure.addressFamily
            )
            let serviceName = advertiseService(on: transport, port: actualPort)
            return InsideJobRuntimeResources(
                transport: transport,
                actualPort: actualPort,
                bonjourServiceName: serviceName,
                idleTimerBaseline: idleTimerBaseline
            )
        } catch {
            await cleanupFailedTransportStartup(transport)
            if let startupAttemptID {
                finishFailedStartAttempt(startupAttemptID, leavesStoppedOnFailure: leavesStoppedOnFailure)
            }
            throw error
        }
    }

    func requireRuntimeToken(phase: InsideJobRuntimeStartPhase) throws -> String {
        guard let token = runtimeConfiguration.token,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            getaway.identity.tlsActive = false
            throw InsideJobStartupError.tokenRequired(phase: phase)
        }
        return token
    }

    func installTransportOverflowHandler(_ transport: ServerTransport) {
        transport.setEventBacklogOverflowHandler { [weak self] maxEvents in
            await self?.handleTransportEventBacklogOverflow(maxEvents: maxEvents)
        }
    }

    func handleTransportEventBacklogOverflow(maxEvents: Int) async {
        insideJobLogger.error("Transport event backlog exceeded \(maxEvents), stopping server")
        await stop()
    }

    func cleanupFailedTransportStartup(_ transport: ServerTransport?) async {
        if let transport {
            await transport.stop()
            await getaway.tearDownIfWired(to: transport)
        }
        getaway.identity.tlsActive = false
    }

    func isCurrentResumeAttempt(_ resumeID: UUID) -> Bool {
        guard case .resuming(let attempt) = serverPhase else { return false }
        return attempt.id == resumeID
    }

    func isCurrentStartAttempt(_ startID: UUID) -> Bool {
        guard case .starting(let attempt) = serverPhase else { return false }
        return attempt.id == startID
    }

    func finishFailedStartAttempt(_ startID: UUID, leavesStoppedOnFailure: Bool) {
        guard leavesStoppedOnFailure, isCurrentStartAttempt(startID) else { return }
        serverPhase = .stopped
    }

    func finishFailedResumeAttempt(_ resumeID: UUID) {
        guard isCurrentResumeAttempt(resumeID) else { return }
        guard case .resuming(let attempt) = serverPhase else { return }
        serverPhase = .suspended(attempt.suspendedRuntime)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
