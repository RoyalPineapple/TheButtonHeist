#if canImport(UIKit)
#if DEBUG
import Foundation

import ThePlans
@_spi(ButtonHeistInternals) import TheScore

// MARK: - Heist Execution

extension TheBrains {

    internal struct HeistExecutionScope {
        internal let rootPlan: HeistPlan
        internal let plan: HeistPlan
        internal var definitionPath: [HeistPlanName] = []
        internal var invocationStack: Set<HeistInvocationPath> = []

        internal init(
            plan: HeistPlan,
            rootPlan: HeistPlan? = nil,
            definitionPath: [HeistPlanName] = [],
            invocationStack: Set<HeistInvocationPath> = []
        ) {
            self.rootPlan = rootPlan ?? plan
            self.plan = plan
            self.definitionPath = definitionPath
            self.invocationStack = invocationStack
        }
    }
}

extension TheBrains {
    internal func executeHeistPlan(_ plan: HeistPlan, argument: HeistArgument = .none) async -> ActionResult {
        guard semanticObservationIsActive else {
            return runtimeInactiveResult(payload: .heist(nil))
        }

        if tripwire.isPulseRunning,
           await interactionCoordinator.refreshedVisibleObservation() == nil {
            return await treeUnavailableResult(payload: .heist(nil))
        }
        let host = HeistExecution.Host(brains: self)
        await host.start()
        let result = await executeHeistPlan(plan, argument: argument, host: host)
        await host.finish()
        return result
    }

    private func executeHeistPlan(
        _ plan: HeistPlan,
        argument: HeistArgument,
        host: HeistExecution.Host
    ) async -> ActionResult {
        let notificationScope = vault.accessibilityNotifications.beginHeistScope()
        defer { notificationScope.cancel() }

        let heistStart = RuntimeElapsed.now
        let environment: HeistExecutionEnvironment
        do {
            environment = try HeistExecutionEnvironment.empty.binding(argument: argument, to: plan.parameter)
        } catch {
            return .failure(
                payload: .heist(nil),
                failureKind: .validationError,
                message: "Could not bind root heist argument: \(error)"
            )
        }
        let execution = await executeHeistStepAccumulator(
            plan.body,
            host: host,
            environment: environment,
            scope: HeistExecutionScope(plan: plan),
            path: .body
        )
        var stepResults = execution.values
        let abortedAtPath = execution.abortedAtPath
        if let failedPath = abortedAtPath,
           let mode = failureEvidencePolicy.captureMode,
           let failureScreenshotStep = await failureScreenshotStep(
            host: host,
            failedPath: failedPath,
            mode: mode
           ) {
            stepResults.append(failureScreenshotStep)
        }
        let durationMs = elapsedMilliseconds(since: heistStart)
        let result: HeistResult
        do {
            result = try HeistResult(steps: stepResults, durationMs: durationMs)
        } catch {
            return .failure(
                payload: .heist(nil),
                failureKind: .validationError,
                message: "Could not admit heist execution result: \(error)"
            )
        }

        let message = heistExecutionMessage(
            completedCount: stepResults.count,
            abortedAtPath: abortedAtPath
        )

        if abortedAtPath == nil {
            return .success(payload: .heist(result), message: message)
        }
        return .failure(
            payload: .heist(result),
            failureKind: .actionFailed,
            message: message
        )
    }

    internal func executeHeistSteps(
        _ steps: [HeistStep],
        host: HeistExecution.Host,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope,
        path: HeistExecutionPath = .body
    ) async -> HeistExecutedChildren {
        await executeHeistStepAccumulator(
            steps,
            host: host,
            environment: environment,
            scope: scope,
            path: path
        )
    }

    private func executeHeistStepAccumulator(
        _ steps: [HeistStep],
        host: HeistExecution.Host,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope,
        path: HeistExecutionPath
    ) async -> HeistExecutedChildren {
        var children = HeistExecutedChildren.empty

        for (index, step) in steps.enumerated() {
            let stepPath = path.step(at: index)

            if children.abortedAtPath != nil {
                children.append(.skipped(path: stepPath, durationMs: 0, step: step))
                continue
            } else {
                let stepResult = await executeHeistStep(
                    step,
                    index: index,
                    path: stepPath,
                    host: host,
                    environment: environment,
                    scope: scope
                )
                children.append(stepResult)
            }
        }
        return children
    }

    private func executeHeistStep(
        _ step: HeistStep,
        index: Int,
        path: HeistExecutionPath,
        host: HeistExecution.Host,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> HeistExecutionStepResult {
        let start = RuntimeElapsed.now
        switch step {
        case .action(let action):
            return await executeActionStep(
                action,
                index: index,
                path: path,
                start: start,
                host: host,
                environment: environment
            )
        case .wait(let waitStep):
            return await executeWaitStep(
                waitStep,
                index: index,
                path: path,
                start: start,
                host: host,
                environment: environment,
                scope: scope
            )
        case .conditional(let conditional):
            return await executeConditionalStep(
                conditional,
                index: index,
                path: path,
                start: start,
                host: host,
                environment: environment,
                scope: scope
            )
        case .forEachElement(let forEach):
            return await executeForEachElementStep(
                forEach,
                index: index,
                path: path,
                start: start,
                host: host,
                environment: environment,
                scope: scope
            )
        case .forEachString(let forEach):
            return await executeForEachStringStep(
                forEach,
                index: index,
                path: path,
                start: start,
                host: host,
                environment: environment,
                scope: scope
            )
        case .repeatUntil(let repeatUntil):
            return await executeRepeatUntilStep(
                repeatUntil,
                index: index,
                path: path,
                start: start,
                host: host,
                environment: environment,
                scope: scope
            )
        case .warn(let warn):
            return executeWarnStep(warn, path: path, start: start)
        case .fail(let fail):
            return executeFailStep(fail, path: path, start: start)
        case .heist(let plan):
            return await executeInlineHeistStep(
                plan,
                index: index,
                path: path,
                start: start,
                host: host,
                environment: environment,
                scope: scope
            )
        case .invoke(let invoke):
            return await executeInvocationStep(
                invoke,
                index: index,
                path: path,
                start: start,
                host: host,
                environment: environment,
                scope: scope
            )
        }
    }

    private func executeInlineHeistStep(
        _ plan: HeistPlan,
        index _: Int,
        path: HeistExecutionPath,
        start: RuntimeElapsed.Instant,
        host: HeistExecution.Host,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> HeistExecutionStepResult {
        let children = await executeHeistSteps(
            plan.body,
            host: host,
            environment: environment,
            scope: HeistExecutionScope(
                plan: plan,
                rootPlan: plan,
                definitionPath: scope.definitionPath,
                invocationStack: scope.invocationStack
            ),
            path: path.heistBody()
        )
        switch children {
        case .passed(let children):
            return .heist(
                path: path,
                durationMs: elapsedMilliseconds(since: start),
                name: plan.name,
                completion: .passed(children: children)
            )
        case .aborted(let children):
            return .heist(
                path: path,
                durationMs: elapsedMilliseconds(since: start),
                name: plan.name,
                completion: .childAborted(
                    failure: childFailureDetail(
                        category: .invocation,
                        childPath: children.abortedAtPath
                    ),
                    children: children
                )
            )
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
