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
            case .observedUnsettled, .unavailable:
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
        case .observedUnsettled(let screen):
            observedFinalState = captureSemanticState(
                from: screen,
                tripwireSignal: before.tripwireSignal,
                settledObservationSequence: nil
            )
        case .unavailable:
            return nil
        }
        let accessibilityNotifications = Self.remapAccessibilityNotifications(
            settleEvidence.accessibilityNotifications,
            from: observedFinalState,
            to: observedFinalState
        )
        let trace = buildPostActionTrace(
            before: before,
            final: observedFinalState,
            settleEvidence: settleEvidence,
            accessibilityNotifications: accessibilityNotifications
        )
        guard trace.captures.last != nil else { return nil }
        return FinalEvidence(state: observedFinalState, trace: trace)
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

        return .observed(finalEvidence)
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
            screen: screen,
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
            (id: $0.heistId.predicateSelectionElementId, element: $0.element)
        }
        return minimumUniquePredicate(
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
    let projection: PostActionResultProjection
    let message: String?
    let evidence: PostActionReceiptEvidence
    let subjectEvidence: ActionSubjectEvidence?
    let activationTrace: ActivationTrace?

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
        self.projection = evidence.projection(method: method, outcome: outcome)
        self.message = evidence.message(explicit: message)
        self.evidence = evidence
        self.subjectEvidence = outcome.subjectEvidence
        self.activationTrace = outcome.activationTrace
    }

    var actionResult: ActionResult {
        switch projection {
        case .success(let method):
            return .success(
                method: method,
                message: message,
                accessibilityTrace: evidence.accessibilityTrace,
                settled: evidence.settled,
                settleTimeMs: evidence.settleTimeMs,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace
            )
        case .successPayload(let payload):
            return .success(
                payload: payload,
                message: message,
                accessibilityTrace: evidence.accessibilityTrace,
                settled: evidence.settled,
                settleTimeMs: evidence.settleTimeMs,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace
            )
        case .failure(let method, let errorKind):
            return .failure(
                method: method,
                errorKind: errorKind,
                message: message,
                accessibilityTrace: evidence.accessibilityTrace,
                settled: evidence.settled,
                settleTimeMs: evidence.settleTimeMs,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace
            )
        case .failurePayload(let payload, let errorKind):
            return .failure(
                payload: payload,
                errorKind: errorKind,
                message: message,
                accessibilityTrace: evidence.accessibilityTrace,
                settled: evidence.settled,
                settleTimeMs: evidence.settleTimeMs,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace
            )
        }
    }
}

private enum PostActionReceiptEvidence {
    case observed(
        finalEvidence: PostActionObservation.FinalEvidence,
        settleEvidence: PostActionObservation.SettleEvidence
    )
    case fallback(
        message: String,
        accessibilityTrace: AccessibilityTrace,
        settled: Bool,
        settleTimeMs: Int
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
        case .cancelled(let cancelMs):
            self = .fallback(
                message: "cancelled after \(cancelMs)ms",
                accessibilityTrace: AccessibilityTrace(capture: before.capture),
                settled: false,
                settleTimeMs: cancelMs
            )
        case .parseFailed:
            self = .fallback(
                message: "Could not parse post-action accessibility tree",
                accessibilityTrace: AccessibilityTrace(capture: before.capture),
                settled: settleEvidence.didSettleCleanly,
                settleTimeMs: settleEvidence.timeMs
            )
        }
    }

    var accessibilityTrace: AccessibilityTrace {
        switch self {
        case .observed(let finalEvidence, _):
            return finalEvidence.trace
        case .fallback(_, let accessibilityTrace, _, _):
            return accessibilityTrace
        }
    }

    var settled: Bool {
        switch self {
        case .observed(_, let settleEvidence):
            return settleEvidence.didSettleCleanly
        case .fallback(_, _, let settled, _):
            return settled
        }
    }

    var settleTimeMs: Int {
        switch self {
        case .observed(_, let settleEvidence):
            return settleEvidence.timeMs
        case .fallback(_, _, _, let settleTimeMs):
            return settleTimeMs
        }
    }

    func projection(
        method: ActionMethod,
        outcome: PostActionObservation.ActionOutcome
    ) -> PostActionResultProjection {
        switch self {
        case .observed(let finalEvidence, _):
            return PostActionResultProjection(
                method: method,
                outcome: outcome,
                payload: outcome.resolvedPayload(after: finalEvidence.state)
            )
        case .fallback:
            return PostActionResultProjection(
                method: method,
                payload: outcome.immediatePayload,
                failure: .actionFailed
            )
        }
    }

    func message(explicit message: String?) -> String? {
        switch self {
        case .observed:
            return message
        case .fallback(let fallbackMessage, _, _, _):
            return fallbackMessage
        }
    }
}

private enum PostActionResultProjection {
    case success(ActionMethod)
    case successPayload(ActionResultPayload)
    case failure(ActionMethod, ErrorKind)
    case failurePayload(ActionResultPayload, ErrorKind)

    init(
        method: ActionMethod,
        outcome: PostActionObservation.ActionOutcome,
        payload: ActionResultPayload?
    ) {
        switch outcome {
        case .success:
            self.init(method: method, payload: payload)
        case .failure(let failure):
            self.init(method: method, payload: payload, failure: failure.errorKind)
        }
    }

    init(method: ActionMethod, payload: ActionResultPayload?) {
        if let payload {
            self = .successPayload(payload)
        } else {
            self = .success(method)
        }
    }

    init(method: ActionMethod, payload: ActionResultPayload?, failure: ErrorKind) {
        if let payload {
            self = .failurePayload(payload, failure)
        } else {
            self = .failure(method, failure)
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
