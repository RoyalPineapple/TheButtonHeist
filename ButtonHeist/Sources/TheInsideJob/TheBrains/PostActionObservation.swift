#if canImport(UIKit)
#if DEBUG
import Foundation

import AccessibilitySnapshotModel
import ThePlans
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

/// Builds traces, captures, deltas, and action receipts from supplied semantic
/// states. The post-action contract is: refresh/settle → before → action →
/// refresh/settle → after → result.
@MainActor
final class PostActionObservation {
    let stash: TheStash
    let safecracker: TheSafecracker

    /// State captured before an action for delta computation.
    struct BeforeState {
        let screen: Screen
        let capture: AccessibilityTrace.Capture
        let tripwireSignal: TheTripwire.TripwireSignal
        let settledObservationSequence: SettledObservationSequence?

        var elements: [AccessibilityElement] { screen.orderedElements.map(\.element) }
        var interface: Interface { capture.interface }
        var semanticHash: String { screen.semantic.semanticHash }
        @MainActor var screenSnapshot: ScreenClassifier.Snapshot { ScreenClassifier.snapshot(of: screen) }
        var screenId: String? { screen.id }
    }

    enum SettleEvidence {
        case cancelled(cancelMs: Int)
        case unavailable(settleTimeMs: Int)
        case committed(SettleSession.Outcome, SettledSemanticObservationEvent)
        case observedUnsettled(SettleSession.Outcome, Screen)

        var didSettleCleanly: Bool {
            if case .committed = self { return true }
            return false
        }

        var timeMs: Int {
            switch self {
            case .cancelled(let timeMs), .unavailable(let timeMs):
                return timeMs
            case .committed(let outcome, _), .observedUnsettled(let outcome, _):
                return outcome.outcome.timeMs
            }
        }

        var accessibilityNotifications: [AccessibilityNotificationEvidence] {
            switch self {
            case .committed(_, let event):
                return event.trace.captures.last?.transition.accessibilityNotifications ?? []
            case .cancelled, .unavailable, .observedUnsettled:
                return []
            }
        }

        var failureMessage: String? {
            switch self {
            case .cancelled(let cancelMs):
                return "cancelled after \(cancelMs)ms"
            case .unavailable:
                return "Could not parse post-action accessibility tree"
            case .committed, .observedUnsettled:
                return nil
            }
        }

        init(_ observation: PostActionSettleObservation) {
            let settle = observation.settle
            switch observation.result {
            case .committed(let event):
                precondition(settle.outcome.didSettleCleanly, "committed observation requires clean settle")
                self = .committed(settle, event)
            case .observedUnsettled(let screen):
                guard case .timedOut = settle.outcome else {
                    preconditionFailure("unsettled observation requires settle timeout")
                }
                self = .observedUnsettled(settle, screen)
            case .unavailable:
                switch settle.outcome {
                case .cancelled(let timeMs):
                    self = .cancelled(cancelMs: timeMs)
                case .timedOut(let timeMs):
                    self = .unavailable(settleTimeMs: timeMs)
                case .settled:
                    preconditionFailure("clean settle requires committed observation")
                }
            }
        }
    }

    struct FinalEvidence {
        let state: BeforeState
        let trace: AccessibilityTrace
    }

    enum ObservationOutcome {
        case unavailable
        case observed(FinalEvidence)
    }

    init(stash: TheStash, safecracker: TheSafecracker) {
        self.stash = stash
        self.safecracker = safecracker
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
        return SettleEvidence(settledObservation)
    }

    func observationOutcome(
        before: BeforeState,
        settleEvidence: SettleEvidence
    ) async -> ObservationOutcome {
        let observed: (state: BeforeState, settle: SettleSession.Outcome)
        switch settleEvidence {
        case .cancelled, .unavailable:
            return .unavailable
        case .committed(let settle, let event):
            observed = (captureFinalSemanticState(after: event), settle)
        case .observedUnsettled(let settle, let screen):
            observed = (
                captureSemanticState(
                    from: screen,
                    tripwireSignal: before.tripwireSignal,
                    settledObservationSequence: nil
                ),
                settle
            )
        }
        let accessibilityNotifications = Self.remapAccessibilityNotifications(
            settleEvidence.accessibilityNotifications,
            from: observed.state,
            to: observed.state
        )
        let trace = buildPostActionTrace(
            before: before,
            final: observed.state,
            settleOutcome: observed.settle,
            accessibilityNotifications: accessibilityNotifications
        )
        return .observed(FinalEvidence(state: observed.state, trace: trace))
    }

    func captureSemanticState(
        from screen: Screen,
        tripwireSignal: TheTripwire.TripwireSignal,
        settledObservationSequence: SettledObservationSequence?
    ) -> BeforeState {
        let semanticInterface = stash.semanticInterfaceWithHash(for: screen)
        let capture = makeTraceCapture(
            interface: semanticInterface.interface,
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
        screen: Screen? = nil,
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

    private static func remapAccessibilityNotifications(
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
        screen: Screen?,
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

    private func firstResponderTarget(in screen: Screen) -> ElementTarget? {
        guard let firstResponderHeistId = screen.liveCapture.firstResponderHeistId else { return nil }
        let elements = screen.orderedElements.map {
            PredicateSelectionSubjectElement(id: $0.heistId.predicateSelectionElementId, element: $0.element)
        }
        return MinimumPredicateSelector.minimumUniquePredicate(
            for: firstResponderHeistId.predicateSelectionElementId,
            in: elements
        )?.target
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
        self = PostActionResultReceipt(
            method: method,
            outcome: outcome,
            message: message,
            before: before,
            settleEvidence: settleEvidence,
            observationOutcome: observationOutcome
        ).actionResult
    }
}

private struct PostActionResultReceipt {
    let method: ActionMethod
    let outcome: PostActionObservation.ActionOutcome
    let explicitMessage: String?
    let evidence: PostActionReceiptEvidence

    init(
        method: ActionMethod,
        outcome: PostActionObservation.ActionOutcome,
        message: String?,
        before: PostActionObservation.BeforeState,
        settleEvidence: PostActionObservation.SettleEvidence,
        observationOutcome: PostActionObservation.ObservationOutcome
    ) {
        let evidence = PostActionReceiptEvidence(
            before: before,
            settleEvidence: settleEvidence,
            observationOutcome: observationOutcome
        )
        self.method = method
        self.outcome = outcome
        self.explicitMessage = message
        self.evidence = evidence
    }

    var actionResult: ActionResult {
        let resultOutcome = evidence.resultOutcome(for: outcome)
        let message = evidence.message(explicit: explicitMessage)
        let payload = evidence.payload(for: outcome)
        if let payload {
            return ActionResult(
                outcome: resultOutcome,
                payload: payload,
                message: message,
                accessibilityTrace: evidence.accessibilityTrace,
                settled: evidence.settled,
                settleTimeMs: evidence.settleTimeMs,
                subjectEvidence: outcome.subjectEvidence,
                activationTrace: outcome.activationTrace
            )
        }
        return ActionResult(
            outcome: resultOutcome,
            method: method,
            message: message,
            accessibilityTrace: evidence.accessibilityTrace,
            settled: evidence.settled,
            settleTimeMs: evidence.settleTimeMs,
            subjectEvidence: outcome.subjectEvidence,
            activationTrace: outcome.activationTrace
        )
    }
}

private enum PostActionReceiptEvidence {
    case observed(
        finalEvidence: PostActionObservation.FinalEvidence,
        settleEvidence: PostActionObservation.SettleEvidence
    )
    case unavailable(
        baselineCapture: AccessibilityTrace.Capture,
        settleEvidence: PostActionObservation.SettleEvidence
    )

    init(
        before: PostActionObservation.BeforeState,
        settleEvidence: PostActionObservation.SettleEvidence,
        observationOutcome: PostActionObservation.ObservationOutcome
    ) {
        switch observationOutcome {
        case .observed(let finalEvidence):
            self = .observed(
                finalEvidence: finalEvidence,
                settleEvidence: settleEvidence
            )
        case .unavailable:
            precondition(
                settleEvidence.failureMessage != nil,
                "unavailable observation requires settle failure"
            )
            self = .unavailable(
                baselineCapture: before.capture,
                settleEvidence: settleEvidence
            )
        }
    }

    var accessibilityTrace: AccessibilityTrace {
        switch self {
        case .observed(let finalEvidence, _):
            return finalEvidence.trace
        case .unavailable(let baselineCapture, _):
            return AccessibilityTrace(capture: baselineCapture)
        }
    }

    var settled: Bool {
        settleEvidence.didSettleCleanly
    }

    var settleTimeMs: Int {
        settleEvidence.timeMs
    }

    private var settleEvidence: PostActionObservation.SettleEvidence {
        switch self {
        case .observed(_, let settleEvidence), .unavailable(_, let settleEvidence):
            return settleEvidence
        }
    }

    func message(explicit message: String?) -> String? {
        switch self {
        case .observed:
            return message
        case .unavailable:
            return settleEvidence.failureMessage
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
        case .observed(let finalEvidence, _):
            return outcome.resolvedPayload(after: finalEvidence.state)
        case .unavailable:
            return outcome.immediatePayload
        }
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

#endif // DEBUG
#endif // canImport(UIKit)
