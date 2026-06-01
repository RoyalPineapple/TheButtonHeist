#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheBrains {

    struct HeistExecutionRuntime {
        let execute: @MainActor (ClientMessage) async -> ActionResult
        let wait: @MainActor (WaitStep) async -> ActionResult
        let observeCases: @MainActor (HeistPredicateObservationScope, PostActionObservation.BeforeState?, Double?) async -> HeistCaseObservation?
        let settleRefreshRecordBaseline: @MainActor () async -> Void

        static func live(_ brains: TheBrains) -> HeistExecutionRuntime {
            HeistExecutionRuntime(
                execute: { command in
                    await brains.executeCommand(command)
                },
                wait: { waitStep in
                    await brains.performWait(target: WaitTarget(
                        predicate: waitStep.predicate,
                        timeout: waitStep.timeout
                    ))
                },
                observeCases: { scope, baseline, timeout in
                    await brains.observeHeistCases(scope: scope, baseline: baseline, timeout: timeout)
                },
                settleRefreshRecordBaseline: {
                    _ = await brains.tripwire.waitForAllClear(timeout: 0.5)
                    if brains.refresh() != nil {
                        brains.recordSentState()
                    }
                }
            )
        }
    }

    func executeHeistPlan(_ plan: HeistPlan) async -> ActionResult {
        await executeHeistPlan(plan, runtime: .live(self))
    }

    func executeHeistPlanForTest(
        _ plan: HeistPlan,
        runtime: HeistExecutionRuntime
    ) async -> ActionResult {
        await executeHeistPlan(plan, runtime: runtime)
    }

    private func executeHeistPlan(
        _ plan: HeistPlan,
        runtime: HeistExecutionRuntime
    ) async -> ActionResult {
        let heistStart = CFAbsoluteTimeGetCurrent()
        let stepResults = await executeHeistSteps(plan.steps, runtime: runtime)
        let failedIndex = stepResults.firstIndex(where: \.isFailure)

        let heistResult = HeistExecutionResult(
            steps: stepResults,
            totalTimingMs: Int((CFAbsoluteTimeGetCurrent() - heistStart) * 1000),
            failedIndex: failedIndex
        )

        var builder = ActionResultBuilder(method: .heistPlan)
        builder.message = heistExecutionMessage(
            completedCount: stepResults.count(where: { !$0.isSkipped }),
            failedCount: stepResults.count(where: \.isFailure),
            failedIndex: failedIndex
        )

        if failedIndex == nil {
            return builder.success(payload: .heistExecution(heistResult))
        }
        return builder.failure(errorKind: .actionFailed, payload: .heistExecution(heistResult))
    }

    private func executeHeistSteps(
        _ steps: [HeistStep],
        runtime: HeistExecutionRuntime
    ) async -> [HeistExecutionStepResult] {
        var stepResults: [HeistExecutionStepResult] = []
        var failedIndex: Int?

        stepLoop: for (index, step) in steps.enumerated() {
            var stepResult = await executeHeistStep(step, index: index, runtime: runtime)
            if stepResult.isFailure {
                stepResult = stepResult.markingStop()
                failedIndex = index
            }
            stepResults.append(stepResult)

            await runtime.settleRefreshRecordBaseline()

            if failedIndex != nil {
                appendSkippedHeistSteps(
                    afterFailedIndex: index,
                    remainingCount: steps.count - index - 1,
                    into: &stepResults
                )
                break stepLoop
            }
        }

        return stepResults
    }

    private func executeHeistStep(
        _ step: HeistStep,
        index: Int,
        runtime: HeistExecutionRuntime
    ) async -> HeistExecutionStepResult {
        let start = CFAbsoluteTimeGetCurrent()
        switch step {
        case .action(let action):
            return await executeActionStep(action, index: index, start: start, runtime: runtime)
        case .wait(let waitStep):
            let result = await runtime.wait(waitStep)
            return HeistExecutionStepResult(
                index: index,
                kind: .wait,
                actionResult: result,
                expectation: waitStep.predicate.validate(against: result),
                durationMs: elapsedMilliseconds(since: start)
            )
        case .conditional(let conditional):
            return await executeConditionalStep(conditional, index: index, start: start, runtime: runtime)
        case .waitForCases(let waitForCases):
            return await executeWaitForCasesStep(waitForCases, index: index, start: start, runtime: runtime)
        case .forEach(let forEach):
            return await executeForEachStep(forEach, index: index, start: start, runtime: runtime)
        case .warn(let warn):
            return HeistExecutionStepResult(
                index: index,
                kind: .warn,
                message: warn.message,
                durationMs: elapsedMilliseconds(since: start)
            )
        case .fail(let fail):
            return HeistExecutionStepResult(
                index: index,
                kind: .fail,
                message: fail.message,
                durationMs: elapsedMilliseconds(since: start),
                stopsHeist: true
            )
        }
    }

    private func executeForEachStep(
        _ step: ForEachStep,
        index: Int,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime
    ) async -> HeistExecutionStepResult {
        guard let observation = await runtime.observeCases(.fullSemanticExplore, nil, nil) else {
            return HeistExecutionStepResult(
                index: index,
                kind: .forEach,
                message: "Could not observe settled semantic hierarchy before evaluating for_each",
                durationMs: elapsedMilliseconds(since: start),
                stopsHeist: true,
                forEachResult: HeistForEachResult(
                    matchedCount: 0,
                    limit: step.limit,
                    iterationCount: 0,
                    failureReason: "semantic hierarchy unavailable"
                )
            )
        }

        let matchedCount = observation.state.interface.projectedElements.count { step.matching.matches($0) }
        if matchedCount > step.limit {
            let reason = "matched \(matchedCount) element(s), exceeding for_each limit \(step.limit)"
            return HeistExecutionStepResult(
                index: index,
                kind: .forEach,
                message: reason,
                durationMs: elapsedMilliseconds(since: start),
                stopsHeist: true,
                forEachResult: HeistForEachResult(
                    matchedCount: matchedCount,
                    limit: step.limit,
                    iterationCount: 0,
                    failureReason: reason
                )
            )
        }

        var childResults: [HeistExecutionStepResult] = []
        var failureReason: String?
        var iterationCount = 0

        for iterationIndex in 0..<matchedCount {
            let iterationResults = await executeHeistSteps(step.steps, runtime: runtime)
            iterationCount += 1

            for result in iterationResults {
                childResults.append(result.reindexed(childResults.count))
            }

            if iterationResults.contains(where: \.isFailure) {
                failureReason = "iteration \(iterationIndex) failed"
                break
            }
        }

        return HeistExecutionStepResult(
            index: index,
            kind: .forEach,
            message: forEachMessage(
                matchedCount: matchedCount,
                iterationCount: iterationCount,
                failureReason: failureReason
            ),
            durationMs: elapsedMilliseconds(since: start),
            stopsHeist: failureReason != nil,
            forEachResult: HeistForEachResult(
                matchedCount: matchedCount,
                limit: step.limit,
                iterationCount: iterationCount,
                failureReason: failureReason
            ),
            childResults: childResults.isEmpty ? nil : childResults
        )
    }

    private func executeConditionalStep(
        _ step: ConditionalStep,
        index: Int,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime
    ) async -> HeistExecutionStepResult {
        guard let observation = await runtime.observeCases(step.observationScope, nil, nil) else {
            return caseObservationFailure(index: index, kind: .conditional, start: start)
        }

        let selection = evaluatePredicateCases(step.cases, observation: observation)
        if let selectedCaseIndex = selection.selectedCaseIndex {
            let selectionElapsedMs = elapsedMilliseconds(since: start)
            let childResults = await executeHeistSteps(step.cases[selectedCaseIndex].steps, runtime: runtime)
            return HeistExecutionStepResult(
                index: index,
                kind: .conditional,
                message: "matched case \(selectedCaseIndex)",
                durationMs: elapsedMilliseconds(since: start),
                caseSelection: HeistCaseSelectionResult(
                    cases: selection.cases,
                    selectedCaseIndex: selectedCaseIndex,
                    elapsedMs: selectionElapsedMs,
                    lastObservedSummary: observation.summary
                ),
                childResults: childResults
            )
        }

        if let elseSteps = step.elseSteps {
            let selectionElapsedMs = elapsedMilliseconds(since: start)
            let childResults = await executeHeistSteps(elseSteps, runtime: runtime)
            return HeistExecutionStepResult(
                index: index,
                kind: .conditional,
                message: "no case matched; else ran",
                durationMs: elapsedMilliseconds(since: start),
                caseSelection: HeistCaseSelectionResult(
                    cases: selection.cases,
                    selectedCaseIndex: nil,
                    elapsedMs: selectionElapsedMs,
                    elseRan: true,
                    lastObservedSummary: observation.summary
                ),
                childResults: childResults
            )
        }

        return HeistExecutionStepResult(
            index: index,
            kind: .conditional,
            message: "no case matched",
            durationMs: elapsedMilliseconds(since: start),
            caseSelection: HeistCaseSelectionResult(
                cases: selection.cases,
                selectedCaseIndex: nil,
                elapsedMs: elapsedMilliseconds(since: start),
                lastObservedSummary: observation.summary
            )
        )
    }

    private func executeWaitForCasesStep(
        _ step: WaitForCasesStep,
        index: Int,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime
    ) async -> HeistExecutionStepResult {
        let deadline = start + step.timeout
        var baseline: PostActionObservation.BeforeState?
        var lastSelection = PredicateCaseSelection.unevaluated(step.cases)
        var lastSummary: String?

        repeat {
            let remaining = max(0, deadline - CFAbsoluteTimeGetCurrent())
            guard let observation = await runtime.observeCases(
                step.observationScope,
                baseline,
                step.timeout == 0 ? nil : min(remaining, 1.0)
            ) else {
                break
            }
            baseline = observation.state
            lastSummary = observation.summary
            lastSelection = evaluatePredicateCases(step.cases, observation: observation)

            if let selectedCaseIndex = lastSelection.selectedCaseIndex {
                let selectionElapsedMs = elapsedMilliseconds(since: start)
                let childResults = await executeHeistSteps(step.cases[selectedCaseIndex].steps, runtime: runtime)
                return HeistExecutionStepResult(
                    index: index,
                    kind: .waitForCases,
                    message: "matched case \(selectedCaseIndex)",
                    durationMs: elapsedMilliseconds(since: start),
                    caseSelection: HeistCaseSelectionResult(
                        cases: lastSelection.cases,
                        selectedCaseIndex: selectedCaseIndex,
                        elapsedMs: selectionElapsedMs,
                        timeout: step.timeout,
                        lastObservedSummary: observation.summary
                    ),
                    childResults: childResults
                )
            }

            if step.timeout == 0 { break }
        } while CFAbsoluteTimeGetCurrent() < deadline

        if let elseSteps = step.elseSteps {
            let selectionElapsedMs = elapsedMilliseconds(since: start)
            let childResults = await executeHeistSteps(elseSteps, runtime: runtime)
            return HeistExecutionStepResult(
                index: index,
                kind: .waitForCases,
                message: "timed out after \(heistTimeoutDescription(step.timeout))s; else ran",
                durationMs: elapsedMilliseconds(since: start),
                caseSelection: HeistCaseSelectionResult(
                    cases: lastSelection.cases,
                    selectedCaseIndex: nil,
                    elapsedMs: selectionElapsedMs,
                    timeout: step.timeout,
                    timedOut: true,
                    elseRan: true,
                    lastObservedSummary: lastSummary
                ),
                childResults: childResults
            )
        }

        return HeistExecutionStepResult(
            index: index,
            kind: .waitForCases,
            message: waitForCasesTimeoutMessage(step: step, lastObservedSummary: lastSummary),
            durationMs: elapsedMilliseconds(since: start),
            caseSelection: HeistCaseSelectionResult(
                cases: lastSelection.cases,
                selectedCaseIndex: nil,
                elapsedMs: elapsedMilliseconds(since: start),
                timeout: step.timeout,
                timedOut: true,
                lastObservedSummary: lastSummary
            )
        )
    }

    private func executeActionStep(
        _ step: ActionStep,
        index: Int,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime
    ) async -> HeistExecutionStepResult {
        let actionResult = await runtime.execute(step.command)
        let expectationReceipt = await expectationReceipt(
            for: step,
            actionResult: actionResult,
            runtime: runtime
        )

        return HeistExecutionStepResult(
            index: index,
            kind: .action,
            actionResult: actionResult,
            expectationActionResult: expectationReceipt?.actionResult,
            expectation: expectationReceipt?.expectation,
            durationMs: elapsedMilliseconds(since: start)
        )
    }

    private func expectationReceipt(
        for step: ActionStep,
        actionResult: ActionResult,
        runtime: HeistExecutionRuntime
    ) async -> HeistExpectationReceipt? {
        guard actionResult.success else { return nil }
        guard let expectation = step.expectation else { return nil }
        let immediateExpectation = expectation.predicate.validate(against: actionResult)
        if immediateExpectation.met || expectation.timeout == 0 {
            return HeistExpectationReceipt(
                actionResult: actionResult,
                expectation: immediateExpectation
            )
        }

        let waitResult = await runtime.wait(expectation)
        return HeistExpectationReceipt(
            actionResult: waitResult,
            expectation: expectation.predicate.validate(against: waitResult)
        )
    }

    private func appendSkippedHeistSteps(
        afterFailedIndex failedIndex: Int,
        remainingCount: Int,
        into stepResults: inout [HeistExecutionStepResult]
    ) {
        guard remainingCount > 0 else { return }
        for index in (failedIndex + 1)..<(failedIndex + 1 + remainingCount) {
            let skipped = HeistExecutionSkippedStepResult(
                index: index,
                reason: "skipped: heist stopped after step \(failedIndex)",
                afterFailedIndex: failedIndex
            )
            stepResults.append(HeistExecutionStepResult(
                index: index,
                kind: .skipped,
                durationMs: 0,
                skipped: skipped
            ))
        }
    }

    private func heistExecutionMessage(
        completedCount: Int,
        failedCount: Int,
        failedIndex: Int?
    ) -> String {
        if let failedIndex {
            return "Heist execution stopped at step \(failedIndex) after \(completedCount) completed step(s)"
        }
        if failedCount > 0 {
            return "Heist execution completed \(completedCount) step(s) with \(failedCount) failed step(s)"
        }
        return "Heist execution completed \(completedCount) step(s)"
    }

    private func elapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }

    private func evaluatePredicateCases(
        _ cases: [PredicateCase],
        observation: HeistCaseObservation
    ) -> PredicateCaseSelection {
        let evaluatedCases = cases.map {
            HeistCaseMatchResult(
                predicate: $0.predicate,
                result: $0.predicate.evaluate(
                    currentElements: observation.state.interface.projectedElements,
                    delta: observation.delta
                )
            )
        }
        return PredicateCaseSelection(
            cases: evaluatedCases,
            selectedCaseIndex: evaluatedCases.firstIndex(where: \.result.met)
        )
    }

    private func caseObservationFailure(
        index: Int,
        kind: HeistExecutionStepKind,
        start: CFAbsoluteTime
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            index: index,
            kind: kind,
            message: "Could not observe settled accessibility state before evaluating heist cases",
            durationMs: elapsedMilliseconds(since: start),
            stopsHeist: true
        )
    }

    private func waitForCasesTimeoutMessage(
        step: WaitForCasesStep,
        lastObservedSummary: String?
    ) -> String {
        [
            "timed out after \(heistTimeoutDescription(step.timeout))s waiting for heist case",
            "cases: \(step.cases.map(\.predicate.description).joined(separator: "; "))",
            "last observed: \(lastObservedSummary ?? "no settled accessibility state")",
            "Next: add Else, widen predicate, or increase timeout.",
        ].joined(separator: "; ")
    }

    private func heistTimeoutDescription(_ timeout: Double) -> String {
        guard timeout.isFinite else { return "\(timeout)" }
        let rounded = timeout.rounded()
        if abs(timeout - rounded) < 0.000_001 {
            return "\(Int(rounded))"
        }
        return String(format: "%.3f", timeout)
    }

    private func forEachMessage(
        matchedCount: Int,
        iterationCount: Int,
        failureReason: String?
    ) -> String {
        if let failureReason {
            return "for_each stopped after \(iterationCount) of \(matchedCount) iteration(s): \(failureReason)"
        }
        return "for_each completed \(iterationCount) iteration(s) from \(matchedCount) matched element(s)"
    }
}

private struct HeistExpectationReceipt {
    let actionResult: ActionResult
    let expectation: ExpectationResult
}

private struct PredicateCaseSelection {
    let cases: [HeistCaseMatchResult]
    let selectedCaseIndex: Int?

    static func unevaluated(_ cases: [PredicateCase]) -> PredicateCaseSelection {
        PredicateCaseSelection(
            cases: cases.map {
                HeistCaseMatchResult(
                    predicate: $0.predicate,
                    result: ExpectationResult(
                        met: false,
                        predicate: $0.predicate,
                        actual: "no settled accessibility state observed"
                    )
                )
            },
            selectedCaseIndex: nil
        )
    }
}

struct HeistCaseObservation {
    let state: PostActionObservation.BeforeState
    let delta: AccessibilityTrace.Delta?
    let summary: String
}

enum HeistPredicateObservationScope: Equatable {
    case visibleRefresh
    case revealTargets([ElementTarget])
    case fullSemanticExplore

    func merged(with other: HeistPredicateObservationScope) -> HeistPredicateObservationScope {
        switch (self, other) {
        case (.fullSemanticExplore, _), (_, .fullSemanticExplore):
            return .fullSemanticExplore
        case (.revealTargets(let left), .revealTargets(let right)):
            return .revealTargets(left + right)
        case (.revealTargets, .visibleRefresh):
            return self
        case (.visibleRefresh, .revealTargets):
            return other
        case (.visibleRefresh, .visibleRefresh):
            return .visibleRefresh
        }
    }
}

private extension TheBrains {
    func observeHeistCases(
        scope: HeistPredicateObservationScope,
        baseline: PostActionObservation.BeforeState?,
        timeout: Double?
    ) async -> HeistCaseObservation? {
        let baseline = baseline ?? postActionObservation.captureSemanticState()
        guard var current = await settledVisibleState(after: baseline, timeout: timeout) else {
            return nil
        }

        switch scope {
        case .visibleRefresh:
            break
        case .fullSemanticExplore:
            _ = await navigation.exploreAndPrune()
            current = postActionObservation.captureSemanticState()
        case .revealTargets(let targets):
            let needsExplore = await revealHeistObservationTargets(targets)
            if needsExplore {
                _ = await navigation.exploreAndPrune()
                current = postActionObservation.captureSemanticState()
            } else if !targets.isEmpty, let refreshed = await settledVisibleState(after: current, timeout: timeout) {
                current = refreshed
            }
        }

        let trace = postActionObservation.makeClassifiedAccessibilityTrace(after: current, parent: baseline)
        return HeistCaseObservation(
            state: current,
            delta: trace.endpointDeltaProjection,
            summary: heistObservationSummary(current)
        )
    }

    func settledVisibleState(
        after baseline: PostActionObservation.BeforeState,
        timeout: Double?
    ) async -> PostActionObservation.BeforeState? {
        let settleSession = SettleSession.live(
            stash: stash,
            tripwire: tripwire,
            timeoutMs: heistObservationTimeoutMs(timeout)
        )
        let settle = await settleSession.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: baseline.tripwireSignal
        )
        guard settle.outcome.didSettleCleanly else { return nil }
        if let screen = settle.finalScreen {
            stash.commitVisibleRefresh(screen)
        } else if refresh() == nil {
            return nil
        }
        return await postActionObservation.semanticStateAfterVisibleRefresh(baseline: baseline)
    }

    func revealHeistObservationTargets(_ targets: [ElementTarget]) async -> Bool {
        var needsExplore = false
        for target in targets {
            switch stash.resolveTarget(target) {
            case .resolved:
                _ = await navigation.executeScrollToVisible(elementTarget: target)
            case .ambiguous:
                continue
            case .notFound:
                needsExplore = true
            }
        }
        return needsExplore
    }

    func heistObservationTimeoutMs(_ timeout: Double?) -> Int {
        guard let timeout, timeout > 0 else { return SettleSession.defaultTimeoutMs }
        return max(1, Int(min(timeout, 1.0) * 1000))
    }

    func heistObservationSummary(_ state: PostActionObservation.BeforeState) -> String {
        var parts = ["known: \(state.interface.projectedElements.count) elements"]
        if let screenId = state.screenId {
            parts.insert("screen: \(screenId)", at: 0)
        }
        return parts.joined(separator: "; ")
    }
}

private extension ConditionalStep {
    var observationScope: HeistPredicateObservationScope {
        cases
            .map(\.predicate.observationScope)
            .reduce(.visibleRefresh) { $0.merged(with: $1) }
    }
}

private extension WaitForCasesStep {
    var observationScope: HeistPredicateObservationScope {
        cases
            .map(\.predicate.observationScope)
            .reduce(.visibleRefresh) { $0.merged(with: $1) }
    }
}

private extension AccessibilityPredicate {
    var observationScope: HeistPredicateObservationScope {
        switch self {
        case .state(let state):
            return state.observationScope
        case .changed(let change):
            return change.observationScope
        }
    }
}

private extension AccessibilityPredicate.State {
    var observationScope: HeistPredicateObservationScope {
        switch self {
        case .present(let predicate), .absent(let predicate):
            return .revealTargets([.predicate(predicate)])
        case .presentTarget(let target), .absentTarget(let target):
            return .revealTargets([target])
        case .all(let states):
            return states
                .map(\.observationScope)
                .reduce(.visibleRefresh) { $0.merged(with: $1) }
        }
    }
}

private extension AccessibilityPredicate.Change {
    var observationScope: HeistPredicateObservationScope {
        switch self {
        case .screen(let state):
            return state?.observationScope ?? .visibleRefresh
        case .elements:
            return .visibleRefresh
        case .appeared:
            return .fullSemanticExplore
        case .disappeared(let predicate):
            return .revealTargets([.predicate(predicate)])
        case .updated(let update):
            guard let predicate = update.element else { return .visibleRefresh }
            return .revealTargets([.predicate(predicate)])
        }
    }
}

private extension HeistExecutionStepResult {
    func markingStop() -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            index: index,
            kind: kind,
            actionResult: actionResult,
            expectationActionResult: expectationActionResult,
            expectation: expectation,
            message: message,
            durationMs: durationMs,
            stopsHeist: true,
            skipped: skipped,
            caseSelection: caseSelection,
            forEachResult: forEachResult,
            childResults: childResults
        )
    }

    func reindexed(_ newIndex: Int) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            index: newIndex,
            kind: kind,
            actionResult: actionResult,
            expectationActionResult: expectationActionResult,
            expectation: expectation,
            message: message,
            durationMs: durationMs,
            stopsHeist: stopsHeist,
            skipped: skipped,
            caseSelection: caseSelection,
            forEachResult: forEachResult,
            childResults: childResults
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
