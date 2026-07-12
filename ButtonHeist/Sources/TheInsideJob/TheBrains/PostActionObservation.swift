#if canImport(UIKit)
#if DEBUG
import Foundation

import AccessibilitySnapshotModel
import ThePlans
import TheScore

/// A settled semantic observation paired with its trace and summary.
struct HeistSemanticObservation {
    let event: SettledSemanticObservationEvent
    let state: PostActionObservation.BeforeState
    let accessibilityTrace: AccessibilityTrace
    let summary: String
}

enum SemanticObservationTiming {
    static let defaultTimeout: Double = 1
    static let visibleTickIntervalSeconds: Double = 0.1
}

struct SemanticObservationDeadline: Sendable, Equatable {
    let start: CFAbsoluteTime
    let timeoutSeconds: Double

    init(start: CFAbsoluteTime, timeoutSeconds: Double) {
        self.start = start
        self.timeoutSeconds = max(0, timeoutSeconds)
    }

    init(start: CFAbsoluteTime, timeoutMs: Int) {
        self.init(start: start, timeoutSeconds: Double(max(0, timeoutMs)) / 1_000)
    }

    func hasTimeRemaining(at now: CFAbsoluteTime) -> Bool {
        now < deadline
    }

    func remainingSeconds(at now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) -> Double {
        max(0, deadline - now)
    }

    func elapsedMilliseconds(at now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) -> Int {
        max(0, Int((now - start) * 1_000))
    }

    private var deadline: CFAbsoluteTime {
        start + timeoutSeconds
    }
}

/// Builds traces, captures, change facts, and action receipts from supplied semantic
/// states. The post-action contract is: refresh/settle → before → action →
/// refresh/settle → after → result.
@MainActor
final class PostActionObservation {
    let stash: TheStash
    let safecracker: TheSafecracker

    enum StateInterfaceProjection {
        case semantic
        case discovery
    }

    /// State captured before an action for delta computation.
    struct BeforeState {
        let screen: InterfaceObservation
        let capture: AccessibilityTrace.Capture
        let tripwireSignal: TheTripwire.TripwireSignal
        let settledObservationSequence: SettledObservationSequence?

        var elements: [AccessibilityElement] { screen.orderedElements.map(\.element) }
        var interface: Interface { capture.interface }
        var interfaceHash: String { screen.tree.interfaceHash }
        @MainActor var screenSnapshot: ScreenClassifier.Snapshot { ScreenClassifier.snapshot(of: screen.tree) }
        var screenId: String? { screen.id }
    }

    enum SettledObservationResult {
        case observed(settle: SettleSession.Outcome, finalState: BeforeState, trace: AccessibilityTrace)
        case unavailable(
            settle: SettleSession.Outcome,
            baselineCapture: AccessibilityTrace.Capture,
            failureMessage: String
        )

        var accessibilityTrace: AccessibilityTrace {
            switch self {
            case .observed(_, _, let trace):
                return trace
            case .unavailable(_, let baselineCapture, _):
                return AccessibilityTrace(capture: baselineCapture)
            }
        }

        var settled: Bool {
            settle.outcome.didSettleCleanly
        }

        var settleTimeMs: Int {
            settle.outcome.timeMs
        }

        private var settle: SettleSession.Outcome {
            switch self {
            case .observed(let settle, _, _),
                 .unavailable(let settle, _, _):
                return settle
            }
        }

        func message(explicit message: String?) -> String? {
            switch self {
            case .observed:
                return message
            case .unavailable(_, _, let failureMessage):
                return failureMessage
            }
        }

        func resultOutcome(
            for outcome: PostActionObservation.ActionOutcome
        ) -> ActionResultOutcome {
            switch self {
            case .observed:
                return outcome.resultOutcome
            case .unavailable:
                return .failure(.actionFailed)
            }
        }

        func payload(
            for outcome: PostActionObservation.ActionOutcome
        ) -> ActionResultPayload? {
            switch self {
            case .observed(_, let finalState, _):
                return outcome.resolvedPayload(after: finalState)
            case .unavailable:
                return outcome.immediatePayload
            }
        }
    }

    init(stash: TheStash, safecracker: TheSafecracker) {
        self.stash = stash
        self.safecracker = safecracker
    }

    func captureSemanticState(from observation: SettledSemanticObservation) -> BeforeState {
        captureSemanticState(
            from: observation.screen,
            tripwireSignal: observation.tripwireSignal,
            settledObservationSequence: observation.sequence,
            interfaceProjection: observation.scope.stateInterfaceProjection
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
            ? event.observation.screen.viewportOnly
            : event.observation.screen
        let current = captureSemanticState(
            from: screen,
            tripwireSignal: event.observation.tripwireSignal,
            settledObservationSequence: event.sequence,
            interfaceProjection: event.scope.stateInterfaceProjection
        )
        return HeistSemanticObservation(
            event: event,
            state: current,
            accessibilityTrace: event.trace,
            summary: Self.observationSummary(current)
        )
    }

    func settleObservation(
        before: BeforeState,
        commitScope: SemanticObservationScope = .visible,
        outcome: SettleSession.Outcome?,
        notificationWindow: AccessibilityNotificationActionWindow? = nil
    ) async -> PostActionSettleObservation {
        await stash.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: before.tripwireSignal,
            commitScope: commitScope,
            settleOutcome: outcome,
            notificationWindow: notificationWindow
        )
    }

    func settledObservationResult(
        before: BeforeState,
        observation: PostActionSettleObservation
    ) -> SettledObservationResult {
        switch observation.result {
        case .committed(let event):
            precondition(
                observation.settle.outcome.didSettleCleanly,
                "committed observation requires clean settle"
            )
            let finalState = captureFinalSemanticState(after: event)
            return observedResult(
                before: before,
                finalState: finalState,
                settle: observation.settle,
                accessibilityNotifications: event.trace.captures.last?.transition.accessibilityNotifications ?? []
            )

        case .observedUnsettled(let screen):
            guard case .timedOut = observation.settle.outcome else {
                preconditionFailure("unsettled observation requires settle timeout")
            }
            let finalState = captureSemanticState(
                from: screen,
                tripwireSignal: before.tripwireSignal,
                settledObservationSequence: nil
            )
            return observedResult(
                before: before,
                finalState: finalState,
                settle: observation.settle,
                accessibilityNotifications: []
            )

        case .unavailable:
            switch observation.settle.outcome {
            case .cancelled(let timeMs):
                return .unavailable(
                    settle: observation.settle,
                    baselineCapture: before.capture,
                    failureMessage: "cancelled after \(timeMs)ms"
                )
            case .timedOut:
                return .unavailable(
                    settle: observation.settle,
                    baselineCapture: before.capture,
                    failureMessage: "Could not parse post-action accessibility tree"
                )
            case .settled:
                preconditionFailure("clean settle requires committed observation")
            }
        }
    }

    private func observedResult(
        before: BeforeState,
        finalState: BeforeState,
        settle: SettleSession.Outcome,
        accessibilityNotifications: [AccessibilityNotificationEvidence]
    ) -> SettledObservationResult {
        let accessibilityNotifications = Self.remapAccessibilityNotifications(
            accessibilityNotifications,
            from: finalState,
            to: finalState
        )
        let trace = buildPostActionTrace(
            before: before,
            final: finalState,
            settleOutcome: settle,
            accessibilityNotifications: accessibilityNotifications
        )
        return .observed(
            settle: settle,
            finalState: finalState,
            trace: trace
        )
    }

    func captureSemanticState(
        from screen: InterfaceObservation,
        tripwireSignal: TheTripwire.TripwireSignal,
        settledObservationSequence: SettledObservationSequence?,
        interfaceProjection: StateInterfaceProjection = .semantic
    ) -> BeforeState {
        let interfaceSnapshot = interfaceSnapshot(for: screen, projection: interfaceProjection)
        let capture = makeTraceCapture(
            interface: interfaceSnapshot.interface,
            sequence: 0,
            screen: screen,
            tripwireSignal: tripwireSignal,
            screenId: screen.id
        )
        return BeforeState(
            screen: screen,
            capture: capture,
            tripwireSignal: tripwireSignal,
            settledObservationSequence: settledObservationSequence
        )
    }

    private func interfaceSnapshot(
        for screen: InterfaceObservation,
        projection: StateInterfaceProjection
    ) -> TheStash.SemanticInterfaceSnapshot {
        switch projection {
        case .semantic:
            return stash.semanticInterfaceWithHash(for: screen)
        case .discovery:
            return stash.discoveryInterfaceWithHash(for: screen)
        }
    }

    static func shouldRecordAccessibilityTrace(
        baseline: BeforeState,
        current: BeforeState,
        classification: ScreenClassifier.Classification
    ) -> Bool {
        switch classification {
        case .inferredScreenChange:
            return true
        case .sameGeneration:
            return current.capture.context != baseline.capture.context
                || current.interfaceHash != baseline.interfaceHash
        }
    }

    func makeTraceCapture(
        interface: Interface,
        sequence: Int = 1,
        parentHash: String? = nil,
        screen: InterfaceObservation? = nil,
        tripwireSignal: TheTripwire.TripwireSignal,
        screenId: String? = nil,
        transition: AccessibilityTrace.Transition = .empty
    ) -> AccessibilityTrace.Capture {
        AccessibilityTrace.Capture(
            sequence: sequence,
            interface: interface,
            parentHash: parentHash,
            context: makeCaptureContext(screen: screen, tripwireSignal: tripwireSignal, screenId: screenId),
            transition: transition
        )
    }

    func makeAccessibilityTrace(
        afterInterface: Interface,
        parentCapture: AccessibilityTrace.Capture? = nil,
        transition: AccessibilityTrace.Transition = .empty
    ) -> AccessibilityTrace {
        let capture = AccessibilityTrace.Capture(
            sequence: parentCapture == nil ? 1 : 2,
            interface: afterInterface,
            parentHash: parentCapture?.hash,
            context: parentCapture?.context ?? .empty,
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
        let transition: AccessibilityTrace.Transition
        switch classification {
        case .sameGeneration:
            transition = AccessibilityTrace.Transition(
                transient: transient,
                accessibilityNotifications: accessibilityNotifications
            )
        case .inferredScreenChange(let reason):
            AccessibilityObservationFallbackLog.record(
                reason,
                source: .postAction
            )
            transition = AccessibilityTrace.Transition(
                fallbackReason: reason,
                transient: transient,
                accessibilityNotifications: accessibilityNotifications
            )
        }
        return makeAccessibilityTrace(
            afterInterface: afterInterface,
            parentCapture: parentCapture,
            transition: transition
        )
    }

    func makeClassifiedAccessibilityTrace(after: BeforeState, parent: BeforeState) -> AccessibilityTrace {
        let classification = ScreenClassifier.classify(
            before: parent.screenSnapshot,
            after: after.screenSnapshot
        )
        let transition: AccessibilityTrace.Transition
        switch classification {
        case .sameGeneration:
            transition = .empty
        case .inferredScreenChange(let reason):
            transition = AccessibilityTrace.Transition(fallbackReason: reason)
        }
        let capture = AccessibilityTrace.Capture(
            sequence: after.capture.sequence,
            interface: after.capture.interface,
            parentHash: after.capture.parentHash,
            context: after.capture.context,
            transition: transition,
            hash: after.capture.hash
        )
        return AccessibilityTrace(captures: [parent.capture, capture])
    }

    private func captureFinalSemanticState(after visibleEvent: SettledSemanticObservationEvent) -> BeforeState {
        let observation = visibleEvent.observation
        let screen = visibleEvent.scope == .visible
            ? observation.screen.viewportOnly
            : observation.screen
        return captureSemanticState(
            from: screen,
            tripwireSignal: observation.tripwireSignal,
            settledObservationSequence: observation.sequence
        )
    }

    private func buildPostActionTrace(
        before: BeforeState,
        final: BeforeState,
        settleOutcome: SettleSession.Outcome,
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
                settleResult: settleOutcome,
                before: before,
                final: final,
                classification: classification
            ),
            accessibilityNotifications: accessibilityNotifications
        )
    }

    static func remapAccessibilityNotifications(
        _ notifications: [AccessibilityNotificationEvidence],
        from source: BeforeState,
        to destination: BeforeState
    ) -> [AccessibilityNotificationEvidence] {
        notifications.map { notification in
            AccessibilityNotificationEvidence(
                sequence: notification.sequence,
                kind: notification.kind,
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
        TheStash.WireConversion.semanticInterfaceProjection(from: state.screen.tree)
            .heistId(for: reference)
    }

    private static func accessibilityNotificationElementReference(
        for heistId: HeistId,
        in state: BeforeState,
        resolution: AccessibilityNotificationElementResolution
    ) -> AccessibilityNotificationElementReference? {
        TheStash.WireConversion.semanticInterfaceProjection(from: state.screen.tree)
            .accessibilityNotificationElementReference(for: heistId, resolution: resolution)
    }

    private func makeCaptureContext(
        screen: InterfaceObservation?,
        tripwireSignal: TheTripwire.TripwireSignal,
        screenId: String? = nil
    ) -> AccessibilityTrace.Context {
        let windows = tripwireSignal.windowStack.windows.enumerated().map { index, window in
            AccessibilityTrace.WindowContext(
                index: index,
                level: Double(window.level),
                isKeyWindow: window.isKeyWindow
            )
        }
        return AccessibilityTrace.Context(
            firstResponder: screen.flatMap { firstResponderTarget(in: $0) },
            keyboardVisible: safecracker.isKeyboardVisible(),
            screenId: screenId ?? stash.lastScreenId,
            windowStack: windows
        )
    }

    private func firstResponderTarget(in screen: InterfaceObservation) -> AccessibilityTarget? {
        guard let firstResponderHeistId = screen.liveCapture.firstResponderHeistId else { return nil }
        return stash.minimumUniqueTarget(for: firstResponderHeistId, in: screen.tree)
    }

    // MARK: - Result Building

    enum ActionOutcome {
        case success(ActionOutcomeSuccess)
        case failure(ActionOutcomeFailure)
    }

    enum ActionOutcomePayload {
        case none
        case immediate(ActionResultPayload)
        case afterState((BeforeState) -> ResolvedActionOutcomePayload)
    }

    enum ResolvedActionOutcomePayload {
        case none
        case payload(ActionResultPayload)

        var payload: ActionResultPayload? {
            switch self {
            case .none:
                return nil
            case .payload(let payload):
                return payload
            }
        }
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
        var parts = ["interface: \(state.interface.projectedElements.count) elements"]
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
        guard case .sameGeneration = classification,
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

private extension SemanticObservationScope {
    var stateInterfaceProjection: PostActionObservation.StateInterfaceProjection {
        switch self {
        case .visible:
            return .semantic
        case .discovery:
            return .discovery
        }
    }
}

extension ActionResult {
    @MainActor init(
        postActionMethod method: ActionMethod,
        outcome: PostActionObservation.ActionOutcome,
        message: String?,
        settledObservation: PostActionObservation.SettledObservationResult
    ) {
        let resultOutcome = settledObservation.resultOutcome(for: outcome)
        let message = settledObservation.message(explicit: message)
        let payload = settledObservation.payload(for: outcome)
        let settlement: ActionSettlementEvidence = settledObservation.settled
            ? .settled(durationMs: settledObservation.settleTimeMs)
            : .timedOut(durationMs: settledObservation.settleTimeMs)
        let evidence = ActionResultEvidence(
            accessibilityTrace: settledObservation.accessibilityTrace,
            settlement: settlement,
            subjectEvidence: outcome.subjectEvidence,
            activationTrace: outcome.activationTrace
        )
        if let payload {
            self = ActionResult(
                outcome: resultOutcome,
                payload: payload,
                message: message,
                evidence: evidence
            )
            return
        }
        self = ActionResult(
            outcome: resultOutcome,
            method: method,
            message: message,
            evidence: evidence
        )
    }
}

private extension PostActionObservation.ActionOutcomePayload {
    var immediatePayload: ActionResultPayload? {
        switch self {
        case .none, .afterState:
            return nil
        case .immediate(let payload):
            return payload
        }
    }

    func resolvedPayload(after state: PostActionObservation.BeforeState) -> ActionResultPayload? {
        switch self {
        case .none:
            return nil
        case .immediate(let payload):
            return payload
        case .afterState(let resolve):
            return resolve(state).payload
        }
    }
}

private extension PostActionObservation.ActionOutcome {
    var resultOutcome: ActionResultOutcome {
        switch self {
        case .success:
            return .success
        case .failure(let failure):
            return .failure(failure.errorKind)
        }
    }

    var immediatePayload: ActionResultPayload? {
        switch self {
        case .success(let success):
            return success.payload.immediatePayload
        case .failure(let failure):
            return failure.payload.immediatePayload
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

    func resolvedPayload(after state: PostActionObservation.BeforeState) -> ActionResultPayload? {
        switch self {
        case .success(let success):
            return success.payload.resolvedPayload(after: state)
        case .failure(let failure):
            return failure.payload.immediatePayload
        }
    }
}

extension InterfaceObservation {
    func removingElements(withIds removedIds: Set<HeistId>) -> InterfaceObservation {
        guard !removedIds.isEmpty else { return self }
        let removal = liveCapture.removingElementsWithPathMap(withIds: removedIds)
        return InterfaceObservation(
            tree: tree.removingElements(withIds: removedIds, using: removal.pathMap),
            liveCapture: removal.liveCapture
        )
    }
}

private extension InterfaceTree {
    func removingElements(
        withIds removedIds: Set<HeistId>,
        using pathMap: [TreePath: TreePath]
    ) -> InterfaceTree {
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
        return InterfaceTree(elements: remappedElements, containers: remappedContainers)
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

private extension LiveCapture {
    func removingElementsWithPathMap(
        withIds removedIds: Set<HeistId>
    ) -> LiveCaptureRemovalResult {
        guard !removedIds.isEmpty else {
            return LiveCaptureRemovalResult(liveCapture: self, pathMap: [:])
        }
        let filteredLiveTree = hierarchy.removingElements(
            withIds: removedIds,
            idsByPath: heistIdsByPath
        )
        let liveCapture = LiveCapture(
            hierarchy: filteredLiveTree.hierarchy,
            containerNamesByPath: Self.remap(containerNamesByPath, using: filteredLiveTree.pathMap),
            heistIdsByPath: filteredLiveTree.idsByPath,
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
        _ memberships: [TreePath: InterfaceTree.ScrollMembership],
        using pathMap: [TreePath: TreePath]
    ) -> [TreePath: InterfaceTree.ScrollMembership] {
        Dictionary(
            uniqueKeysWithValues: memberships.compactMap { path, membership in
                guard let remappedPath = pathMap[path],
                      let remappedContainerPath = pathMap[membership.containerPath]
                else { return nil }
                return (
                    remappedPath,
                    InterfaceTree.ScrollMembership(
                        containerPath: remappedContainerPath,
                        index: membership.index
                    )
                )
            }
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
