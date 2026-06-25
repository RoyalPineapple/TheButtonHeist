#if canImport(UIKit)
#if DEBUG
import Foundation

import AccessibilitySnapshotModel
import TheScore

/// A settled semantic observation paired with its trace, delta, and summary.
struct HeistSemanticObservation {
    let event: SettledSemanticObservationEvent
    let state: PostActionObservation.BeforeState
    let accessibilityTrace: AccessibilityTrace
    let delta: AccessibilityTrace.Delta?
    let summary: String
}

enum SemanticObservationTiming {
    static let defaultTimeout: Double = 1
}

/// Builds traces, captures, deltas, and action receipts from supplied semantic
/// states. The post-action contract is: refresh/settle → before → action →
/// refresh/settle → after → result.
@MainActor
final class PostActionObservation {
    let stash: TheStash
    let safecracker: TheSafecracker
    let tripwire: TheTripwire
    let navigation: Navigation

    /// State captured before an action for delta computation.
    struct BeforeState {
        let screen: Screen
        let snapshot: [Screen.ScreenElement]
        let elements: [AccessibilityElement]
        let hierarchy: [AccessibilityHierarchy]
        let interface: Interface
        let interfaceHash: String
        let semanticHash: String
        let capture: AccessibilityTrace.Capture
        let tripwireSignal: TheTripwire.TripwireSignal
        let screenSnapshot: ScreenClassifier.Snapshot
        let screenId: String?
        let settledObservationSequence: UInt64?
    }

    struct SettleEvidence {
        let outcome: SettleSession.Outcome
        let visibleEvent: SettledSemanticObservationEvent?
        let diagnosticScreen: Screen?

        var didSettleCleanly: Bool {
            outcome.outcome.didSettleCleanly
        }

        var timeMs: Int {
            outcome.outcome.timeMs
        }
    }

    struct FinalEvidence {
        let state: BeforeState
        let trace: AccessibilityTrace

        var capture: AccessibilityTrace.Capture? {
            trace.captures.last
        }
    }

    init(stash: TheStash, safecracker: TheSafecracker, tripwire: TheTripwire, navigation: Navigation) {
        self.stash = stash
        self.safecracker = safecracker
        self.tripwire = tripwire
        self.navigation = navigation
    }

    func captureSemanticState(from observation: SettledSemanticObservation) -> BeforeState {
        captureSemanticState(
            from: observation.screen,
            tripwireSignal: observation.tripwireSignal,
            settledObservationSequence: observation.sequence
        )
    }

    func captureSemanticState(from evidence: VisibleSemanticObservationEvidence) -> BeforeState {
        captureSemanticState(
            from: evidence.screen,
            tripwireSignal: evidence.tripwireSignal,
            settledObservationSequence: evidence.settledObservationSequence
        )
    }

    func semanticObservation(from event: SettledSemanticObservationEvent) -> HeistSemanticObservation {
        let screen = event.scope == .visible
            ? event.observation.screen.visibleOnly
            : event.observation.screen
        let current = captureSemanticState(
            from: screen,
            tripwireSignal: event.observation.tripwireSignal,
            settledObservationSequence: event.sequence
        )
        return HeistSemanticObservation(
            event: event,
            state: current,
            accessibilityTrace: event.trace,
            delta: event.delta,
            summary: Self.observationSummary(current)
        )
    }

    func settleEvidence(
        before: BeforeState,
        outcome: SettleSession.Outcome?
    ) async -> SettleEvidence {
        let settledObservation = await stash.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: before.tripwireSignal,
            settleOutcome: outcome
        )
        return SettleEvidence(
            outcome: settledObservation.settle,
            visibleEvent: settledObservation.event,
            diagnosticScreen: settledObservation.diagnosticScreen
        )
    }

    func finalSemanticEvidence(
        before: BeforeState,
        settleEvidence: SettleEvidence
    ) async -> FinalEvidence? {
        let observedFinalState: BeforeState
        if let visibleEvent = settleEvidence.visibleEvent {
            observedFinalState = captureFinalSemanticState(after: visibleEvent)
        } else if let diagnosticScreen = settleEvidence.diagnosticScreen {
            observedFinalState = captureSemanticState(
                from: diagnosticScreen,
                tripwireSignal: tripwire.tripwireSignal(),
                settledObservationSequence: nil
            )
        } else {
            return nil
        }
        let finalState = refinedScreenChangeFinalState(
            before: before,
            observedFinal: observedFinalState
        ) ?? observedFinalState
        let trace = buildPostActionTrace(
            before: before,
            final: finalState,
            settleEvidence: settleEvidence
        )
        return FinalEvidence(state: finalState, trace: trace)
    }

    func captureSemanticState(
        from screen: Screen,
        tripwireSignal: TheTripwire.TripwireSignal,
        settledObservationSequence: UInt64?
    ) -> BeforeState {
        let snapshot = stash.selectElements(in: screen)
        let (interface, interfaceHash) = stash.semanticInterfaceWithHash(for: screen)
        let capture = makeTraceCapture(
            interface: interface,
            sequence: 0,
            tripwireSignal: tripwireSignal,
            screenId: screen.id
        )
        return BeforeState(
            screen: screen,
            snapshot: snapshot,
            elements: snapshot.map(\.element),
            hierarchy: screen.liveCapture.hierarchy,
            interface: interface,
            interfaceHash: interfaceHash,
            semanticHash: screen.semantic.semanticHash,
            capture: capture,
            tripwireSignal: tripwireSignal,
            screenSnapshot: ScreenClassifier.snapshot(of: screen),
            screenId: screen.id,
            settledObservationSequence: settledObservationSequence
        )
    }

    static func shouldRecordAccessibilityTrace(
        baseline: BeforeState,
        current: BeforeState,
        classification: ScreenClassifier.Classification
    ) -> Bool {
        classification.isScreenChange
            || current.capture.context != baseline.capture.context
            || current.semanticHash != baseline.semanticHash
    }

    func makeTraceCapture(
        interface: Interface,
        sequence: Int = 1,
        parentHash: String? = nil,
        tripwireSignal: TheTripwire.TripwireSignal? = nil,
        screenId: String? = nil,
        transition: AccessibilityTrace.Transition = .empty
    ) -> AccessibilityTrace.Capture {
        AccessibilityTrace.Capture(
            sequence: sequence,
            interface: interface,
            parentHash: parentHash,
            context: makeCaptureContext(tripwireSignal: tripwireSignal, screenId: screenId),
            transition: transition
        )
    }

    func makeAccessibilityTrace(
        afterInterface: Interface,
        parentCapture: AccessibilityTrace.Capture? = nil,
        transition: AccessibilityTrace.Transition = .empty
    ) -> AccessibilityTrace {
        let capture = makeTraceCapture(
            interface: afterInterface,
            sequence: parentCapture == nil ? 1 : 2,
            parentHash: parentCapture?.hash,
            transition: transition
        )
        if let parentCapture {
            return AccessibilityTrace(captures: [parentCapture, capture])
        }
        return AccessibilityTrace(capture: capture)
    }

    func makeAccessibilityTrace(
        afterInterface: Interface,
        parentCapture: AccessibilityTrace.Capture,
        classification: ScreenClassifier.Classification,
        transient: [HeistElement] = []
    ) -> AccessibilityTrace {
        makeAccessibilityTrace(
            afterInterface: afterInterface,
            parentCapture: parentCapture,
            transition: AccessibilityTrace.Transition(
                screenChangeReason: classification.reason?.rawValue,
                transient: transient
            )
        )
    }

    func makeClassifiedAccessibilityTrace(after: BeforeState, parent: BeforeState) -> AccessibilityTrace {
        let classification = ScreenClassifier.classify(
            before: parent.screenSnapshot,
            after: after.screenSnapshot
        )
        let capture = AccessibilityTrace.Capture(
            sequence: after.capture.sequence,
            interface: after.capture.interface,
            parentHash: after.capture.parentHash,
            context: after.capture.context,
            transition: AccessibilityTrace.Transition(screenChangeReason: classification.reason?.rawValue),
            hash: after.capture.hash
        )
        return AccessibilityTrace(captures: [parent.capture, capture])
    }

    private func captureFinalSemanticState(after visibleEvent: SettledSemanticObservationEvent) -> BeforeState {
        let observation = visibleEvent.observation
        let screen = visibleEvent.scope == .visible
            ? observation.screen.visibleOnly
            : observation.screen
        return captureSemanticState(
            from: screen,
            tripwireSignal: observation.tripwireSignal,
            settledObservationSequence: observation.sequence
        )
    }

    private func refinedScreenChangeFinalState(
        before: BeforeState,
        observedFinal: BeforeState
    ) -> BeforeState? {
        guard observedFinal.settledObservationSequence != nil else { return nil }
        let classification = ScreenClassifier.classify(
            before: before.screenSnapshot,
            after: observedFinal.screenSnapshot
        )
        guard classification.isScreenChange else { return nil }

        let observedOverlap = Self.visibleOverlapCount(before: before, after: observedFinal)
        guard observedOverlap > 0 else { return nil }
        if let pruned = prunedScreenChangeFinalState(
            before: before,
            observedFinal: observedFinal,
            classification: classification,
            observedOverlap: observedOverlap
        ) {
            return pruned
        }
        return nil
    }

    private func prunedScreenChangeFinalState(
        before: BeforeState,
        observedFinal: BeforeState,
        classification: ScreenClassifier.Classification,
        observedOverlap: Int
    ) -> BeforeState? {
        guard Self.shouldPruneOldVisibleOverlap(classification) else { return nil }
        let beforeVisibleIds = Set(before.snapshot.map(\.heistId))
        let prunedScreen = observedFinal.screen.removingElements(withIds: beforeVisibleIds)
        let candidate = captureSemanticState(
            from: prunedScreen,
            tripwireSignal: observedFinal.tripwireSignal,
            settledObservationSequence: observedFinal.settledObservationSequence
        )
        guard Self.visibleOverlapCount(before: before, after: candidate) < observedOverlap else {
            return nil
        }
        let event = stash.semanticObservationStream.commitSettledVisibleObservation(prunedScreen)
        return captureFinalSemanticState(after: event)
    }

    private static func shouldPruneOldVisibleOverlap(_ classification: ScreenClassifier.Classification) -> Bool {
        switch classification.reason {
        case .navigationMarkerChanged, .modalBoundaryChanged:
            return true
        case .selectedTabChanged, .primaryHeaderChanged, .rootShapeChanged, nil:
            return false
        }
    }

    private static func visibleOverlapCount(before: BeforeState, after: BeforeState) -> Int {
        Set(before.snapshot.map(\.heistId)).intersection(after.snapshot.map(\.heistId)).count
    }

    private func buildPostActionTrace(
        before: BeforeState,
        final: BeforeState,
        settleEvidence: SettleEvidence
    ) -> AccessibilityTrace {
        let classification = ScreenClassifier.classify(
            before: before.screenSnapshot,
            after: final.screenSnapshot
        )
        return makeAccessibilityTrace(
            afterInterface: final.interface,
            parentCapture: before.capture,
            classification: classification,
            transient: Self.transientElements(
                settleResult: settleEvidence.outcome,
                before: before,
                final: final,
                classification: classification
            )
        )
    }

    private func makeCaptureContext(
        tripwireSignal: TheTripwire.TripwireSignal? = nil,
        screenId: String? = nil
    ) -> AccessibilityTrace.Context {
        let signal = tripwireSignal ?? tripwire.tripwireSignal()
        let windows = signal.windowStack.windows.enumerated().map { index, window in
            AccessibilityTrace.WindowContext(
                index: index,
                level: Double(window.level),
                isKeyWindow: window.isKeyWindow
            )
        }
        return AccessibilityTrace.Context(
            keyboardVisible: safecracker.isKeyboardVisible(),
            screenId: screenId ?? stash.lastScreenId,
            windowStack: windows
        )
    }

    // MARK: - Result Building

    /// Inputs for building a post-action receipt from settle and final evidence.
    struct ResultInput {
        let success: Bool
        let method: ActionMethod
        let message: String?
        let payload: ResultPayload?
        let afterStatePayload: ((BeforeState) -> ResultPayload?)?
        let errorKind: ErrorKind?
        let subjectEvidence: ActionSubjectEvidence?
        let activationTrace: ActivationTrace?
        let before: BeforeState
        let settleEvidence: SettleEvidence
        let finalEvidence: FinalEvidence?
    }

    /// Build the action receipt from before/settle/final evidence. Cancellation
    /// and parse-failure are settled here from the evidence, not by a separate
    /// worldview.
    static func result(_ input: ResultInput) -> ActionResult {
        if let cancelled = cancelledActionResult(
            method: input.method,
            payload: input.payload,
            subjectEvidence: input.subjectEvidence,
            activationTrace: input.activationTrace,
            before: input.before,
            settleEvidence: input.settleEvidence
        ) {
            return cancelled
        }

        guard let finalEvidence = input.finalEvidence else {
            return parseFailureResult(
                method: input.method,
                payload: input.payload,
                subjectEvidence: input.subjectEvidence,
                activationTrace: input.activationTrace,
                before: input.before,
                settleEvidence: input.settleEvidence
            )
        }

        let resolvedPayload = input.success
            ? (input.afterStatePayload?(finalEvidence.state) ?? input.payload)
            : input.payload

        guard finalEvidence.capture != nil else {
            return failedActionResult(
                method: input.method,
                capture: input.before.capture,
                message: input.message,
                payload: resolvedPayload,
                subjectEvidence: input.subjectEvidence,
                activationTrace: input.activationTrace
            )
        }

        return actionResult(
            method: input.method,
            capture: finalEvidence.capture ?? finalEvidence.state.capture,
            message: input.message,
            payload: resolvedPayload,
            errorKind: input.errorKind,
            accessibilityTrace: finalEvidence.trace,
            subjectEvidence: input.subjectEvidence,
            activationTrace: input.activationTrace,
            settled: input.settleEvidence.didSettleCleanly,
            settleTimeMs: input.settleEvidence.timeMs,
            success: input.success
        )
    }

    static func actionResult(
        method: ActionMethod,
        capture: AccessibilityTrace.Capture,
        message: String?,
        payload: ResultPayload?,
        errorKind: ErrorKind? = nil,
        accessibilityTrace: AccessibilityTrace? = nil,
        subjectEvidence: ActionSubjectEvidence? = nil,
        activationTrace: ActivationTrace? = nil,
        settled: Bool? = nil,
        settleTimeMs: Int? = nil,
        success: Bool
    ) -> ActionResult {
        var builder = ActionResultBuilder(method: method, capture: capture)
        builder.message = message
        if let accessibilityTrace {
            builder.accessibilityTrace = accessibilityTrace
        }
        builder.settled = settled
        builder.settleTimeMs = settleTimeMs
        builder.subjectEvidence = subjectEvidence
        builder.activationTrace = activationTrace
        if success {
            return builder.success(payload: payload)
        }
        return builder.failure(errorKind: errorKind ?? .actionFailed, payload: payload)
    }

    static func failedActionResult(
        method: ActionMethod,
        capture: AccessibilityTrace.Capture,
        message: String?,
        payload: ResultPayload?,
        errorKind: ErrorKind? = .actionFailed,
        subjectEvidence: ActionSubjectEvidence? = nil,
        activationTrace: ActivationTrace? = nil,
        settled: Bool? = nil,
        settleTimeMs: Int? = nil
    ) -> ActionResult {
        actionResult(
            method: method,
            capture: capture,
            message: message,
            payload: payload,
            errorKind: errorKind,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace,
            settled: settled,
            settleTimeMs: settleTimeMs,
            success: false
        )
    }

    private static func cancelledActionResult(
        method: ActionMethod,
        payload: ResultPayload?,
        subjectEvidence: ActionSubjectEvidence?,
        activationTrace: ActivationTrace?,
        before: BeforeState,
        settleEvidence: SettleEvidence
    ) -> ActionResult? {
        guard case .cancelled(let cancelMs) = settleEvidence.outcome.outcome else { return nil }
        return failedActionResult(
            method: method,
            capture: before.capture,
            message: "cancelled after \(cancelMs)ms",
            payload: payload,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace,
            settled: false,
            settleTimeMs: cancelMs
        )
    }

    private static func parseFailureResult(
        method: ActionMethod,
        payload: ResultPayload?,
        subjectEvidence: ActionSubjectEvidence?,
        activationTrace: ActivationTrace?,
        before: BeforeState,
        settleEvidence: SettleEvidence
    ) -> ActionResult {
        failedActionResult(
            method: method,
            capture: before.capture,
            message: "Could not parse post-action accessibility tree",
            payload: payload,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace,
            settled: settleEvidence.didSettleCleanly,
            settleTimeMs: settleEvidence.timeMs
        )
    }

    // MARK: - Observation Helpers

    static func observationSummary(_ state: BeforeState) -> String {
        var parts = ["known: \(state.interface.projectedElements.count) elements"]
        if let screenId = state.screenId {
            parts.insert("screen: \(screenId)", at: 0)
        }
        return parts.joined(separator: "; ")
    }

    static func transientElements(
        settleResult: SettleSession.Outcome,
        before: BeforeState,
        final: BeforeState,
        classification: ScreenClassifier.Classification
    ) -> [HeistElement] {
        guard !classification.isScreenChange,
              !settleResult.events.containsTripwireSignalChange else {
            return []
        }
        return SettleSession.transientElements(
            seenByKey: settleResult.elementsByKey,
            baseline: before.elements,
            final: final.elements
        ).map { TheStash.WireConversion.convert($0) }
    }
}

private extension Screen {
    func removingElements(withIds removedIds: Set<HeistId>) -> Screen {
        guard !removedIds.isEmpty else { return self }
        return Screen(
            semantic: SemanticScreen(
                elements: semantic.elements.filter { !removedIds.contains($0.key) },
                containers: semantic.containers
            ),
            liveCapture: liveCapture.removingElements(withIds: removedIds)
        )
    }
}

private extension LiveCapture {
    func removingElements(withIds removedIds: Set<HeistId>) -> LiveCapture {
        guard !removedIds.isEmpty else { return self }
        let removedElements = Set(heistIdByElement.compactMap { element, heistId in
            removedIds.contains(heistId) ? element : nil
        })
        let filteredHierarchy = hierarchy.compactMap {
            $0.removingElements(removedElements)
        }
        return LiveCapture(
            hierarchy: filteredHierarchy,
            containerNames: containerNames,
            containerNamesByPath: containerNamesByPath,
            heistIdByElement: heistIdByElement.filter { !removedIds.contains($0.value) },
            elementRefs: elementRefs.filter { !removedIds.contains($0.key) },
            containerRefsByPath: containerRefsByPath,
            containerContentFramesByPath: containerContentFramesByPath,
            containerScrollContentLocationsByPath: containerScrollContentLocationsByPath,
            firstResponderHeistId: firstResponderHeistId.flatMap { removedIds.contains($0) ? nil : $0 },
            scrollableContainerViews: scrollableContainerViews,
            scrollableContainerViewsByPath: scrollableContainerViewsByPath
        )
    }
}

private extension AccessibilityHierarchy {
    func removingElements(_ removedElements: Set<AccessibilityElement>) -> AccessibilityHierarchy? {
        switch self {
        case .element(let element, _):
            return removedElements.contains(element) ? nil : self
        case .container(let container, let children):
            return .container(
                container,
                children: children.compactMap { $0.removingElements(removedElements) }
            )
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
