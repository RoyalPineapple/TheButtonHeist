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
            tlsFingerprint: lease.tlsFingerprint,
            bonjourServiceName: lease.bonjourServiceName
        )
        return lease
    }

    func startRuntimeLeaseForResume() async throws -> InsideJobRuntimeLease {
        try await startRuntimeLease(phase: "resume", leavesStoppedOnFailure: false)
    }

    func activateRuntimeLease(_ lease: InsideJobRuntimeLease) {
        lease.activate(on: self)
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
        let identity = try makeTLSIdentity(phase: phase)
        insideJobLogger.info("TLS identity ready: \(identity.fingerprint)")

        let transport = transportFactory(identity, runtimeConfiguration.allowedScopes)
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
                tlsFingerprint: identity.fingerprint,
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

    static func defaultTLSIdentityProvider() throws -> TLSIdentity {
        do {
            return try TLSIdentity.getOrCreate()
        } catch {
            throw InsideJobStartupError.tlsIdentityUnavailable(
                phase: "identity-creation",
                reason: error.localizedDescription
            )
        }
    }

    func makeTLSIdentity(phase: String) throws -> TLSIdentity {
        do {
            return try tlsIdentityProvider()
        } catch let error as InsideJobStartupError {
            getaway.identity.tlsActive = false
            throw error
        } catch {
            getaway.identity.tlsActive = false
            throw InsideJobStartupError.tlsIdentityUnavailable(
                phase: phase,
                reason: error.localizedDescription
            )
        }
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
