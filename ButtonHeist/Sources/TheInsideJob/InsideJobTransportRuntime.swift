#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

@MainActor
extension TheInsideJob {
    func startRuntimeLeaseForStartup() async throws -> InsideJobRuntimeLease {
        let lease = try await startRuntimeLease(phase: "startup", leavesStoppedOnFailure: true)
        logStartupSummary(
            actualPort: lease.actualPort,
            bonjourServiceName: lease.bonjourServiceName
        )
        return lease
    }

    func startRuntimeLeaseForResume() async throws -> InsideJobRuntimeLease {
        try await startRuntimeLease(phase: "resume", leavesStoppedOnFailure: false)
    }

    func stopRuntime() async {
        if case .resuming(_, let task) = serverPhase {
            task.cancel()
        }

        let bridge = pendingForegroundResumeTask
        pendingForegroundResumeTask = nil
        bridge?.cancel()
        await bridge?.value

        if case .running(let lease) = serverPhase {
            pendingTransportStopTask = lease.release(from: self, policy: .stop)
        } else {
            releaseRuntimeOwnedResources(policy: .stop)
        }

        serverPhase = .stopped
    }

    private func startRuntimeLease(phase: String, leavesStoppedOnFailure: Bool) async throws -> InsideJobRuntimeLease {
        let token = try requireRuntimeToken(phase: phase)
        insideJobLogger.info("TLS PSK material ready")

        let transport = transportFactory(token, runtimeConfiguration.allowedScopes)
        installTransportOverflowHandler(transport)
        await getaway.wireTransport(transport)

        let exposure = ServerExposure(allowedScopes: runtimeConfiguration.allowedScopes)
        do {
            let actualPort = try await transport.start(
                port: runtimeConfiguration.preferredPort,
                bindToLoopback: exposure.bindsToLoopbackOnly
            )
            let serviceName = advertiseService(on: transport, port: actualPort)
            return InsideJobRuntimeLease(
                transport: transport,
                actualPort: actualPort,
                bonjourServiceName: serviceName
            )
        } catch {
            await cleanupFailedTransportStartup(transport)
            if leavesStoppedOnFailure {
                serverPhase = .stopped
            }
            throw error
        }
    }

    func requireRuntimeToken(phase: String) throws -> String {
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
            let stopTask = transport.stop()
            await stopTask.value
            await getaway.tearDownIfWired(to: transport)
        }
        getaway.identity.tlsActive = false
    }

    func isCurrentResumeAttempt(_ resumeID: UUID) -> Bool {
        guard case .resuming(let currentID, _) = serverPhase else { return false }
        return currentID == resumeID
    }

    func finishFailedResumeAttempt(_ resumeID: UUID, startedTransport: ServerTransport?) {
        let stopTask = startedTransport?.stop()
        if let stopTask {
            if let existingStopTask = pendingTransportStopTask {
                pendingTransportStopTask = Task {
                    await existingStopTask.value
                    await stopTask.value
                }
            } else {
                pendingTransportStopTask = stopTask
            }
        }
        guard isCurrentResumeAttempt(resumeID) else { return }
        serverPhase = .suspended
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
