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
        let settledObservationSequence: SettledObservationSequence?
    }

    struct SettleEvidence {
        let outcome: SettleSession.Outcome
        let result: PostActionSettleObservation.Result

        var didSettleCleanly: Bool {
            outcome.outcome.didSettleCleanly
        }

        var timeMs: Int {
            outcome.outcome.timeMs
        }

        var accessibilityNotifications: [AccessibilityNotificationEvidence] {
            switch result {
            case .committed(let event):
                return event.trace.captures.last?.transition.accessibilityNotifications ?? []
            case .diagnostic, .unavailable:
                return []
            }
        }
    }

    struct FinalEvidence {
        let state: BeforeState
        let trace: AccessibilityTrace
    }

    enum ObservationOutcome {
        case cancelled(cancelMs: Int)
        case parseFailed
        case settled(FinalEvidence)
    }

    private enum FinalStateRefinement {
        case state(BeforeState)
        case commitSettledVisibleObservation(Screen)
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
        commitScope: SemanticObservationScope = .visible,
        outcome: SettleSession.Outcome?,
        notificationWindow: AccessibilityNotificationActionWindow? = nil
    ) async -> SettleEvidence {
        let settledObservation = await stash.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: before.tripwireSignal,
            commitScope: commitScope,
            settleOutcome: outcome,
            notificationWindow: notificationWindow
        )
        return SettleEvidence(
            outcome: settledObservation.settle,
            result: settledObservation.result
        )
    }

    func finalSemanticEvidence(
        before: BeforeState,
        settleEvidence: SettleEvidence
    ) async -> FinalEvidence? {
        let observedFinalState: BeforeState
        switch settleEvidence.result {
        case .committed(let visibleEvent):
            observedFinalState = captureFinalSemanticState(after: visibleEvent)
        case .diagnostic(let diagnosticScreen):
            observedFinalState = captureSemanticState(
                from: diagnosticScreen,
                tripwireSignal: tripwire.tripwireSignal(),
                settledObservationSequence: nil
            )
        case .unavailable:
            return nil
        }
        let finalState: BeforeState
        switch refinedScreenChangeFinalState(
            before: before,
            observedFinal: observedFinalState
        ) {
        case .state(let state):
            finalState = state
        case .commitSettledVisibleObservation(let screen):
            let event = stash.semanticObservationStream.commitSettledVisibleObservation(screen)
            finalState = captureFinalSemanticState(after: event)
        case nil:
            finalState = observedFinalState
        }
        let accessibilityNotifications = Self.remapAccessibilityNotifications(
            settleEvidence.accessibilityNotifications,
            from: observedFinalState,
            to: finalState
        )
        let trace = buildPostActionTrace(
            before: before,
            final: finalState,
            settleEvidence: settleEvidence,
            accessibilityNotifications: accessibilityNotifications
        )
        guard trace.captures.last != nil else { return nil }
        return FinalEvidence(state: finalState, trace: trace)
    }

    func observationOutcome(
        before: BeforeState,
        settleEvidence: SettleEvidence
    ) async -> ObservationOutcome {
        if case .cancelled(let cancelMs) = settleEvidence.outcome.outcome {
            return .cancelled(cancelMs: cancelMs)
        }

        guard let finalEvidence = await finalSemanticEvidence(
            before: before,
            settleEvidence: settleEvidence
        ) else {
            return .parseFailed
        }

        return .settled(finalEvidence)
    }

    func captureSemanticState(
        from screen: Screen,
        tripwireSignal: TheTripwire.TripwireSignal,
        settledObservationSequence: SettledObservationSequence?
    ) -> BeforeState {
        let snapshot = stash.selectElements(in: screen)
        let semanticInterface = stash.semanticInterfaceWithHash(for: screen)
        let capture = makeTraceCapture(
            interface: semanticInterface.interface,
            sequence: 0,
            tripwireSignal: tripwireSignal,
            screenId: screen.id
        )
        return BeforeState(
            screen: screen,
            snapshot: snapshot,
            elements: snapshot.map(\.element),
            hierarchy: screen.liveCapture.hierarchy,
            interface: semanticInterface.interface,
            interfaceHash: semanticInterface.hash,
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
        transient: [HeistElement] = [],
        accessibilityNotifications: [AccessibilityNotificationEvidence] = []
    ) -> AccessibilityTrace {
        makeAccessibilityTrace(
            afterInterface: afterInterface,
            parentCapture: parentCapture,
            transition: AccessibilityTrace.Transition(
                screenChangeReason: classification.reason?.rawValue,
                transient: transient,
                accessibilityNotifications: accessibilityNotifications
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
    ) -> FinalStateRefinement? {
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
    ) -> FinalStateRefinement? {
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
        return .commitSettledVisibleObservation(prunedScreen)
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
        settleEvidence: SettleEvidence,
        accessibilityNotifications: [AccessibilityNotificationEvidence]
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
            ),
            accessibilityNotifications: accessibilityNotifications
        )
    }

    private static func remapAccessibilityNotifications(
        _ notifications: [AccessibilityNotificationEvidence],
        from source: BeforeState,
        to destination: BeforeState
    ) -> [AccessibilityNotificationEvidence] {
        notifications.map { notification in
            AccessibilityNotificationEvidence(
                sequence: notification.sequence,
                code: notification.code,
                name: notification.name,
                timestamp: notification.timestamp,
                notificationData: remapAccessibilityNotificationPayload(
                    notification.notificationData,
                    from: source,
                    to: destination
                ),
                associatedElement: remapAccessibilityNotificationPayload(
                    notification.associatedElement,
                    from: source,
                    to: destination
                )
            )
        }
    }

    private static func remapAccessibilityNotificationPayload(
        _ payload: AccessibilityNotificationPayload,
        from source: BeforeState,
        to destination: BeforeState
    ) -> AccessibilityNotificationPayload {
        guard case .element(let reference) = payload else {
            return payload
        }
        guard let heistId = heistId(for: reference, in: source),
              let remappedReference = accessibilityNotificationElementReference(
                for: heistId,
                in: destination,
                resolution: reference.resolution
              )
        else {
            return .unresolvedElement
        }
        return .element(remappedReference)
    }

    private static func heistId(
        for reference: AccessibilityNotificationElementReference,
        in state: BeforeState
    ) -> HeistId? {
        guard reference.path.indices.count == 1,
              let index = reference.path.indices.first,
              index == reference.traversalIndex,
              state.screen.orderedElements.indices.contains(index)
        else {
            return nil
        }
        return state.screen.orderedElements[index].heistId
    }

    private static func accessibilityNotificationElementReference(
        for heistId: HeistId,
        in state: BeforeState,
        resolution: AccessibilityNotificationElementResolution
    ) -> AccessibilityNotificationElementReference? {
        for (index, element) in state.screen.orderedElements.enumerated() where element.heistId == heistId {
            return AccessibilityNotificationElementReference(
                path: TreePath([index]),
                traversalIndex: index,
                resolution: resolution
            )
        }
        return nil
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

    enum ActionOutcome {
        case success(ActionOutcomeSuccess)
        case failure(ActionOutcomeFailure)
    }

    enum ActionOutcomePayload {
        case none
        case immediate(ActionResultPayload)
        case afterState((BeforeState) -> ActionResultPayload?)
    }

    struct ActionOutcomeSuccess {
        let payload: ActionOutcomePayload
        let subjectEvidence: ActionSubjectEvidence?
        let activationTrace: ActivationTrace?

        init(
            payload: ActionOutcomePayload = .none,
            subjectEvidence: ActionSubjectEvidence? = nil,
            activationTrace: ActivationTrace? = nil
        ) {
            self.payload = payload
            self.subjectEvidence = subjectEvidence
            self.activationTrace = activationTrace
        }
    }

    struct ActionOutcomeFailure {
        let errorKind: ErrorKind
        let payload: ActionOutcomePayload
        let activationTrace: ActivationTrace?

        init(
            errorKind: ErrorKind,
            payload: ActionOutcomePayload = .none,
            activationTrace: ActivationTrace? = nil
        ) {
            self.errorKind = errorKind
            self.payload = payload
            self.activationTrace = activationTrace
        }
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

extension ActionResult {
    @MainActor init(
        postActionMethod method: ActionMethod,
        outcome: PostActionObservation.ActionOutcome,
        message: String?,
        before: PostActionObservation.BeforeState,
        settleEvidence: PostActionObservation.SettleEvidence,
        observationOutcome: PostActionObservation.ObservationOutcome
    ) {
        let context = PostActionReceiptContext(
            method: method,
            actionOutcome: outcome,
            message: message
        )
        self = PostActionReceiptState(
            context: context,
            before: before,
            settleEvidence: settleEvidence,
            observationOutcome: observationOutcome
        ).actionResult
    }
}

private struct PostActionReceiptContext {
    let method: ActionMethod
    let actionOutcome: PostActionObservation.ActionOutcome
    let message: String?
}

private struct PostActionReceiptSettleEvidence {
    let settled: Bool
    let settleTimeMs: Int

    init(settled: Bool, settleTimeMs: Int) {
        self.settled = settled
        self.settleTimeMs = settleTimeMs
    }

    init(_ settleEvidence: PostActionObservation.SettleEvidence) {
        self.init(
            settled: settleEvidence.didSettleCleanly,
            settleTimeMs: settleEvidence.timeMs
        )
    }

    static func cancelled(afterMs cancelMs: Int) -> Self {
        Self(settled: false, settleTimeMs: cancelMs)
    }
}

private struct PostActionReceiptEvidence {
    let method: ActionMethod
    let message: String?
    let payload: PostActionReceiptPayload
    let accessibilityTrace: AccessibilityTrace
    let settleEvidence: PostActionReceiptSettleEvidence
    let subjectEvidence: ActionSubjectEvidence?
    let activationTrace: ActivationTrace?

    func successResult() -> ActionResult {
        switch payload {
        case .none:
            return .success(
                method: method,
                message: message,
                accessibilityTrace: accessibilityTrace,
                settled: settleEvidence.settled,
                settleTimeMs: settleEvidence.settleTimeMs,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace
            )
        case .payload(let payload):
            return .success(
                payload: payload,
                message: message,
                accessibilityTrace: accessibilityTrace,
                settled: settleEvidence.settled,
                settleTimeMs: settleEvidence.settleTimeMs,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace
            )
        }
    }

    func failureResult(errorKind: ErrorKind) -> ActionResult {
        switch payload {
        case .none:
            return .failure(
                method: method,
                errorKind: errorKind,
                message: message,
                accessibilityTrace: accessibilityTrace,
                settled: settleEvidence.settled,
                settleTimeMs: settleEvidence.settleTimeMs,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace
            )
        case .payload(let payload):
            return .failure(
                payload: payload,
                errorKind: errorKind,
                message: message,
                accessibilityTrace: accessibilityTrace,
                settled: settleEvidence.settled,
                settleTimeMs: settleEvidence.settleTimeMs,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace
            )
        }
    }
}

private enum PostActionReceiptState {
    case cancelled(PostActionReceiptEvidence)
    case parseFailed(PostActionReceiptEvidence)
    case settledSuccess(PostActionReceiptEvidence)
    case settledFailure(PostActionReceiptEvidence, errorKind: ErrorKind)

    init(
        context: PostActionReceiptContext,
        before: PostActionObservation.BeforeState,
        settleEvidence: PostActionObservation.SettleEvidence,
        observationOutcome: PostActionObservation.ObservationOutcome
    ) {
        switch observationOutcome {
        case .cancelled(let cancelMs):
            self = .cancelled(PostActionReceiptEvidence(
                method: context.method,
                message: "cancelled after \(cancelMs)ms",
                payload: context.actionOutcome.immediatePayload,
                accessibilityTrace: AccessibilityTrace(capture: before.capture),
                settleEvidence: .cancelled(afterMs: cancelMs),
                subjectEvidence: context.actionOutcome.subjectEvidence,
                activationTrace: context.actionOutcome.activationTrace
            ))

        case .parseFailed:
            self = .parseFailed(PostActionReceiptEvidence(
                method: context.method,
                message: "Could not parse post-action accessibility tree",
                payload: context.actionOutcome.immediatePayload,
                accessibilityTrace: AccessibilityTrace(capture: before.capture),
                settleEvidence: PostActionReceiptSettleEvidence(settleEvidence),
                subjectEvidence: context.actionOutcome.subjectEvidence,
                activationTrace: context.actionOutcome.activationTrace
            ))

        case .settled(let finalEvidence):
            let evidence = PostActionReceiptEvidence(
                method: context.method,
                message: context.message,
                payload: context.actionOutcome.resolvedPayload(after: finalEvidence.state),
                accessibilityTrace: finalEvidence.trace,
                settleEvidence: PostActionReceiptSettleEvidence(settleEvidence),
                subjectEvidence: context.actionOutcome.subjectEvidence,
                activationTrace: context.actionOutcome.activationTrace
            )
            switch context.actionOutcome.receiptOutcome {
            case .success:
                self = .settledSuccess(evidence)
            case .failure(let errorKind):
                self = .settledFailure(evidence, errorKind: errorKind)
            }
        }
    }

    var actionResult: ActionResult {
        switch self {
        case .cancelled(let evidence), .parseFailed(let evidence):
            return evidence.failureResult(errorKind: .actionFailed)
        case .settledSuccess(let evidence):
            return evidence.successResult()
        case .settledFailure(let evidence, let errorKind):
            return evidence.failureResult(errorKind: errorKind)
        }
    }
}

private enum PostActionReceiptOutcome {
    case success
    case failure(ErrorKind)
}

private enum PostActionReceiptPayload {
    case none
    case payload(ActionResultPayload)
}

private extension PostActionObservation.ActionOutcomePayload {
    var immediateReceiptPayload: PostActionReceiptPayload {
        switch self {
        case .none, .afterState:
            return .none
        case .immediate(let payload):
            return .payload(payload)
        }
    }

    func resolvedReceiptPayload(after state: PostActionObservation.BeforeState) -> PostActionReceiptPayload {
        switch self {
        case .none:
            return .none
        case .immediate(let payload):
            return .payload(payload)
        case .afterState(let resolve):
            guard let payload = resolve(state) else { return .none }
            return .payload(payload)
        }
    }
}

private extension PostActionObservation.ActionOutcome {
    var immediatePayload: PostActionReceiptPayload {
        switch self {
        case .success(let success):
            return success.payload.immediateReceiptPayload
        case .failure(let failure):
            return failure.payload.immediateReceiptPayload
        }
    }

    var subjectEvidence: ActionSubjectEvidence? {
        switch self {
        case .success(let success):
            return success.subjectEvidence
        case .failure:
            return nil
        }
    }

    var activationTrace: ActivationTrace? {
        switch self {
        case .success(let success):
            return success.activationTrace
        case .failure(let failure):
            return failure.activationTrace
        }
    }

    var receiptOutcome: PostActionReceiptOutcome {
        switch self {
        case .success:
            return .success
        case .failure(let failure):
            return .failure(failure.errorKind)
        }
    }

    func resolvedPayload(after state: PostActionObservation.BeforeState) -> PostActionReceiptPayload {
        switch self {
        case .success(let success):
            return success.payload.resolvedReceiptPayload(after: state)
        case .failure(let failure):
            return failure.payload.immediateReceiptPayload
        }
    }
}

extension Screen {
    func removingElements(withIds removedIds: Set<HeistId>) -> Screen {
        guard !removedIds.isEmpty else { return self }
        let removal = liveCapture.removingElementsWithPathMap(withIds: removedIds)
        return Screen(
            semantic: semantic.removingElements(withIds: removedIds, using: removal.pathMap),
            liveCapture: removal.liveCapture
        )
    }
}

private extension SemanticScreen {
    func removingElements(
        withIds removedIds: Set<HeistId>,
        using pathMap: [TreePath: TreePath]
    ) -> SemanticScreen {
        var remappedElements: [HeistId: Element] = [:]
        remappedElements.reserveCapacity(elements.count)
        for (heistId, entry) in elements where !removedIds.contains(heistId) {
            remappedElements[heistId] = Element(
                heistId: entry.heistId,
                scrollMembership: remap(entry.scrollMembership, using: pathMap),
                observedScrollContentActivationPoint: entry.observedScrollContentActivationPoint,
                element: entry.element
            )
        }

        var remappedContainers: [TreePath: Container] = [:]
        remappedContainers.reserveCapacity(containers.count)
        for entry in containers.values.sorted(by: { $0.path < $1.path }) {
            let remappedPath = pathMap[entry.path] ?? entry.path
            remappedContainers[remappedPath] = Container(
                container: entry.container,
                path: remappedPath,
                containerName: entry.containerName,
                contentRect: entry.contentFrame,
                scrollMembership: remap(entry.scrollMembership, using: pathMap),
                observedScrollContentActivationPoint: entry.observedScrollContentActivationPoint,
                scrollInventory: entry.scrollInventory
            )
        }
        return SemanticScreen(elements: remappedElements, containers: remappedContainers)
    }

    private func remap(
        _ membership: ScrollMembership?,
        using pathMap: [TreePath: TreePath]
    ) -> ScrollMembership? {
        guard let membership else { return nil }
        return ScrollMembership(
            containerPath: pathMap[membership.containerPath] ?? membership.containerPath,
            index: membership.index
        )
    }
}

private struct LiveCaptureRemovalResult {
    let liveCapture: LiveCapture
    let pathMap: [TreePath: TreePath]
}

private struct AccessibilityHierarchyRemovalResult {
    let hierarchy: [AccessibilityHierarchy]
    let heistIdsByPath: [TreePath: HeistId]
    let pathMap: [TreePath: TreePath]
}

private extension LiveCapture {
    func removingElementsWithPathMap(
        withIds removedIds: Set<HeistId>
    ) -> LiveCaptureRemovalResult {
        guard !removedIds.isEmpty else {
            return LiveCaptureRemovalResult(liveCapture: self, pathMap: [:])
        }
        let filteredLiveTree = hierarchy.removingElements(
            withIds: removedIds,
            heistIdsByPath: heistIdsByPath
        )
        let liveCapture = LiveCapture(
            hierarchy: filteredLiveTree.hierarchy,
            containerNamesByPath: Self.remap(containerNamesByPath, using: filteredLiveTree.pathMap),
            heistIdsByPath: filteredLiveTree.heistIdsByPath,
            elementRefs: elementRefs.filter { !removedIds.contains($0.key) },
            containerRefsByPath: Self.remap(containerRefsByPath, using: filteredLiveTree.pathMap),
            containerContentFramesByPath: Self.remap(containerContentFramesByPath, using: filteredLiveTree.pathMap),
            containerScrollMembershipsByPath: Self.remapMemberships(
                containerScrollMembershipsByPath,
                using: filteredLiveTree.pathMap
            ),
            containerObservedScrollContentActivationPointsByPath: Self.remap(
                containerObservedScrollContentActivationPointsByPath,
                using: filteredLiveTree.pathMap
            ),
            scrollInventoriesByPath: Self.remap(scrollInventoriesByPath, using: filteredLiveTree.pathMap),
            firstResponderHeistId: firstResponderHeistId.flatMap { removedIds.contains($0) ? nil : $0 },
            scrollableContainerViewsByPath: Self.remap(scrollableContainerViewsByPath, using: filteredLiveTree.pathMap)
        )
        return LiveCaptureRemovalResult(liveCapture: liveCapture, pathMap: filteredLiveTree.pathMap)
    }

    private static func remap<Value>(
        _ values: [TreePath: Value],
        using pathMap: [TreePath: TreePath]
    ) -> [TreePath: Value] {
        Dictionary(
            uniqueKeysWithValues: values.compactMap { path, value in
                pathMap[path].map { ($0, value) }
            }
        )
    }

    private static func remapMemberships(
        _ memberships: [TreePath: SemanticScreen.ScrollMembership],
        using pathMap: [TreePath: TreePath]
    ) -> [TreePath: SemanticScreen.ScrollMembership] {
        Dictionary(
            uniqueKeysWithValues: memberships.compactMap { path, membership in
                guard let remappedPath = pathMap[path],
                      let remappedContainerPath = pathMap[membership.containerPath]
                else { return nil }
                return (
                    remappedPath,
                    SemanticScreen.ScrollMembership(
                        containerPath: remappedContainerPath,
                        index: membership.index
                    )
                )
            }
        )
    }
}

private extension Array where Element == AccessibilityHierarchy {
    func removingElements(
        withIds removedIds: Set<HeistId>,
        heistIdsByPath: [TreePath: HeistId]
    ) -> AccessibilityHierarchyRemovalResult {
        var hierarchy: [AccessibilityHierarchy] = []
        var remappedHeistIdsByPath: [TreePath: HeistId] = [:]
        var pathMap: [TreePath: TreePath] = [:]
        for (oldIndex, node) in enumerated() {
            let oldPath = TreePath([oldIndex])
            let newPath = TreePath([hierarchy.count])
            guard let filteredNode = node.removingElements(
                withIds: removedIds,
                oldPath: oldPath,
                newPath: newPath,
                heistIdsByPath: heistIdsByPath,
                remappedHeistIdsByPath: &remappedHeistIdsByPath,
                pathMap: &pathMap
            ) else { continue }
            hierarchy.append(filteredNode)
        }
        return AccessibilityHierarchyRemovalResult(
            hierarchy: hierarchy,
            heistIdsByPath: remappedHeistIdsByPath,
            pathMap: pathMap
        )
    }
}

private extension AccessibilityHierarchy {
    func removingElements(
        withIds removedIds: Set<HeistId>,
        oldPath: TreePath,
        newPath: TreePath,
        heistIdsByPath: [TreePath: HeistId],
        remappedHeistIdsByPath: inout [TreePath: HeistId],
        pathMap: inout [TreePath: TreePath]
    ) -> AccessibilityHierarchy? {
        switch self {
        case .element(let element, let traversalIndex):
            guard let heistId = heistIdsByPath[oldPath] else { return self }
            guard !removedIds.contains(heistId) else { return nil }
            pathMap[oldPath] = newPath
            remappedHeistIdsByPath[newPath] = heistId
            return .element(element, traversalIndex: traversalIndex)
        case .container(let container, let children):
            pathMap[oldPath] = newPath
            var filteredChildren: [AccessibilityHierarchy] = []
            for (oldIndex, child) in children.enumerated() {
                let oldChildPath = oldPath.appending(oldIndex)
                let newChildPath = newPath.appending(filteredChildren.count)
                guard let filteredChild = child.removingElements(
                    withIds: removedIds,
                    oldPath: oldChildPath,
                    newPath: newChildPath,
                    heistIdsByPath: heistIdsByPath,
                    remappedHeistIdsByPath: &remappedHeistIdsByPath,
                    pathMap: &pathMap
                ) else { continue }
                filteredChildren.append(filteredChild)
            }
            return .container(
                container,
                children: filteredChildren
            )
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
