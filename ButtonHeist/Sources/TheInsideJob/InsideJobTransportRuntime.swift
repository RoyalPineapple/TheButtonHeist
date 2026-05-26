#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

struct StartedInsideJobTransport {
    let transport: ServerTransport
    let actualPort: UInt16
    let tlsFingerprint: String
}

@MainActor
extension TheInsideJob {
    func startTransportForStartup() async throws -> StartedInsideJobTransport {
        let startedTransport = try await startTransport(phase: "startup", leavesStoppedOnFailure: true)
        let serviceName = advertiseService(port: startedTransport.actualPort)
        logStartupSummary(
            actualPort: startedTransport.actualPort,
            tlsFingerprint: startedTransport.tlsFingerprint,
            bonjourServiceName: serviceName
        )
        return startedTransport
    }

    func startTransportForResume() async throws -> StartedInsideJobTransport {
        let startedTransport = try await startTransport(phase: "resume", leavesStoppedOnFailure: false)
        advertiseService(port: startedTransport.actualPort)
        return startedTransport
    }

    func activateStartedTransport(_ transport: ServerTransport) {
        getaway.identity.tlsActive = true
        serverPhase = .running(transport: transport)
    }

    func stopRuntime() async {
        if case .resuming(_, let task) = serverPhase {
            task.cancel()
        }

        let bridge = pendingForegroundResumeTask
        pendingForegroundResumeTask = nil
        bridge?.cancel()
        await bridge?.value

        if case .running(let activeTransport) = serverPhase {
            pendingTransportStopTask = activeTransport.stop()
        }

        serverPhase = .stopped
        stopPolling()

        tripwire.stopPulse()
        tripwire.onTransition = nil
        brains.stopKeyboardObservation()
    }

    private func startTransport(phase: String, leavesStoppedOnFailure: Bool) async throws -> StartedInsideJobTransport {
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
            return StartedInsideJobTransport(
                transport: transport,
                actualPort: actualPort,
                tlsFingerprint: identity.fingerprint
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
