#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit

import TheScore

@MainActor
extension TheInsideJob {
    func makeRuntimeStartAttempt(
        id: UUID,
        phase: InsideJobRuntimeStartPhase
    ) throws -> InsideJobStartAttempt {
        InsideJobStartAttempt(
            id: id,
            transport: try makeRuntimeTransport(phase: phase)
        )
    }

    func makeRuntimeTransport(phase: InsideJobRuntimeStartPhase) throws -> ServerTransport {
        let token = try requireRuntimeToken(phase: phase)
        insideJobLogger.info("TLS PSK material ready")
        return transportFactory(token, runtimeConfiguration.allowedScopes)
    }

    func startRuntimeResources(
        from effects: [InsideJobLifecycleMachine.Effect]
    ) async throws -> InsideJobRuntimeResources {
        guard effects.count == 1,
              case .startTransport(let request) = effects[0]
        else {
            throw CancellationError()
        }
        return try await startRuntimeResources(for: request)
    }

    func stopRuntime() async {
        let attempt = InsideJobStopAttempt(id: UUID())
        let change = applyLifecycleEvent(.stopRequested(attempt))
        guard !change.effects.isEmpty else {
            return
        }

        await performLifecycleEffects(change.effects)
        if change.effects.contains(where: \.isCancelResumeEffect) {
            guard case .suspended = serverPhase else { return }
            await stopRuntime()
            return
        }

        let finishChange = applyLifecycleEvent(.stopFinished(attempt.id))
        await performLifecycleEffects(finishChange.effects)
    }

    private func startRuntimeResources(
        for request: InsideJobTransportStartRequest
    ) async throws -> InsideJobRuntimeResources {
        installTransportOverflowHandler(request.transport)
        await getaway.wireTransport(request.transport)

        let exposure = ServerExposure(
            allowedScopes: runtimeConfiguration.allowedScopes,
            addressFamily: runtimeConfiguration.addressFamily
        )
        let actualPort = try await request.transport.start(
            port: runtimeConfiguration.preferredPort,
            bindToLoopback: exposure.bindsToLoopbackOnly,
            addressFamily: exposure.addressFamily
        )
        let serviceName = advertiseService(on: request.transport, port: actualPort)
        let resources = InsideJobRuntimeResources(
            transport: request.transport,
            actualPort: actualPort,
            bonjourServiceName: serviceName,
            idleTimerBaseline: request.idleTimerBaseline
        )
        if request.phase == .startup {
            logStartupSummary(
                actualPort: resources.actualPort,
                bonjourServiceName: resources.bonjourServiceName
            )
        }
        return resources
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

    func performLifecycleEffects(_ effects: [InsideJobLifecycleMachine.Effect]) async {
        for effect in effects {
            await performLifecycleEffect(effect)
        }
    }

    func performLifecycleSchedulingEffects(_ effects: [InsideJobLifecycleMachine.Effect]) {
        for effect in effects {
            switch effect {
            case .scheduleSuspend:
                spawnLifecycleTask { [weak self] in
                    await self?.suspend()
                }
            case .scheduleResume(let attempt):
                spawnLifecycleTask { [weak self] in
                    if let attempt {
                        await self?.performLifecycleEffect(.cancelResume(attempt))
                    }
                    await self?.resumeAfterLifecycleBoundary()
                }
            case .scheduleStop:
                spawnLifecycleTask { [weak self] in
                    await self?.stop()
                }
            case .startTransport,
                 .stopTransport,
                 .cleanupTransport,
                 .releaseResources,
                 .cancelResume,
                 .activateRuntime,
                 .tearDownRuntimeServices:
                spawnLifecycleTask { [weak self] in
                    await self?.performLifecycleEffect(effect)
                }
            }
        }
    }

    func performLifecycleEffect(_ effect: InsideJobLifecycleMachine.Effect) async {
        switch effect {
        case .scheduleSuspend:
            spawnLifecycleTask { [weak self] in
                await self?.suspend()
            }
        case .scheduleResume(let attempt):
            spawnLifecycleTask { [weak self] in
                if let attempt {
                    await self?.performLifecycleEffect(.cancelResume(attempt))
                }
                await self?.resumeAfterLifecycleBoundary()
            }
        case .scheduleStop:
            spawnLifecycleTask { [weak self] in
                await self?.stop()
            }
        case .startTransport:
            assertionFailure("startTransport effects must be awaited by the lifecycle operation that requested them")
        case .stopTransport(let transport):
            await transport.stop()
        case .cleanupTransport(let transport):
            await cleanupFailedTransportStartup(transport)
        case .releaseResources(let policy, let idleTimerBaseline):
            releaseRuntimeOwnedResources(policy: policy, idleTimerBaseline: idleTimerBaseline)
        case .cancelResume(let attempt):
            attempt.task.cancel()
            await attempt.task.value
        case .activateRuntime(let resources):
            activateRuntime(resources)
        case .tearDownRuntimeServices:
            await muscle.tearDown()
            await getaway.tearDown()
        }
    }
}

private extension InsideJobLifecycleMachine.Effect {
    var isCancelResumeEffect: Bool {
        if case .cancelResume = self { return true }
        return false
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
