#if canImport(UIKit)
#if DEBUG
import ButtonHeistSupport

struct RevealPathGraceMachine: SimpleStateMachine, Equatable {
    let silentReparseInterval: Double

    func advance(
        _ state: RevealPathGraceState,
        with event: RevealPathGraceEvent
    ) -> RevealPathGraceTransition {
        switch (state, event) {
        case (.idle, .begin(let cursor, let remaining)):
            return waitOrFinish(
                RevealPathGraceLoopContext(cursor: cursor, didRetryReveal: false),
                remaining: remaining
            )

        case (.waitingForTransition(let context), .transitionWaitCompleted(let cursor)):
            return change(
                to: .yieldingFrame(context.advanced(to: cursor)),
                effect: .yieldRealFrame
            )

        case (.yieldingFrame(let context), .frameYielded):
            return change(to: .refreshingVisibleTree(context), effect: .refreshVisibleTree)

        case (.refreshingVisibleTree(let context), .visibleTreeRefreshCompleted(true, _)):
            return change(to: .resolvingVisibleTarget(context), effect: .resolveVisibleTarget)

        case (.refreshingVisibleTree(let context), .visibleTreeRefreshCompleted(false, let remaining)):
            return waitOrFinish(context, remaining: remaining)

        case (.resolvingVisibleTarget, .visibleTargetResolved):
            return finish(.resolvedVisible)

        case (.resolvingVisibleTarget, .visibleTargetFailed):
            return finish(.failedVisibleTarget)

        case (.resolvingVisibleTarget(let context), .visibleTargetMissing(let remaining)):
            guard !context.didRetryReveal else {
                return waitOrFinish(context, remaining: remaining)
            }
            return change(
                to: .attemptingKnownTargetReveal(context.markingRevealRetried()),
                effect: .attemptKnownTargetReveal
            )

        case (.attemptingKnownTargetReveal, .knownTargetRevealAttempted(.revealed(let didReveal), _)):
            return finish(.resolvedAfterKnownReveal(didReveal: didReveal))

        case (.attemptingKnownTargetReveal(let context), .knownTargetRevealAttempted(.unavailable, let remaining)),
             (.attemptingKnownTargetReveal(let context), .knownTargetRevealAttempted(.failed, let remaining)):
            return waitOrFinish(context, remaining: remaining)

        case (.idle, .cancelled),
             (.waitingForTransition, .cancelled),
             (.yieldingFrame, .cancelled),
             (.refreshingVisibleTree, .cancelled),
             (.resolvingVisibleTarget, .cancelled),
             (.attemptingKnownTargetReveal, .cancelled):
            return finish(.cancelled)

        case (.finished, _):
            return .rejected(.alreadyFinished, stayingIn: state)

        default:
            return .rejected(.invalidTransition, stayingIn: state)
        }
    }

    private func waitOrFinish(
        _ context: RevealPathGraceLoopContext,
        remaining: Double
    ) -> RevealPathGraceTransition {
        guard remaining > 0 else {
            return finish(.timedOut)
        }
        return change(
            to: .waitingForTransition(context),
            effect: .waitForTransitionEvent(
                after: context.cursor,
                timeout: min(max(0, silentReparseInterval), remaining)
            )
        )
    }

    private func finish(_ reason: RevealPathGraceFinish) -> RevealPathGraceTransition {
        change(to: .finished, effect: .finish(reason))
    }

    private func change(
        to state: RevealPathGraceState,
        effect: RevealPathGraceEffect
    ) -> RevealPathGraceTransition {
        .changed(to: state, effects: [effect])
    }
}

typealias RevealPathGraceTransition = StateChange<
    RevealPathGraceState,
    RevealPathGraceEffect,
    RevealPathGraceRejection
>

struct RevealPathGraceLoopContext: Sendable, Equatable {
    let cursor: AccessibilityNotificationCursor
    let didRetryReveal: Bool

    func advanced(to cursor: AccessibilityNotificationCursor?) -> RevealPathGraceLoopContext {
        guard let cursor else { return self }
        return RevealPathGraceLoopContext(cursor: cursor, didRetryReveal: didRetryReveal)
    }

    func markingRevealRetried() -> RevealPathGraceLoopContext {
        RevealPathGraceLoopContext(cursor: cursor, didRetryReveal: true)
    }
}

enum RevealPathGraceState: Sendable, Equatable {
    case idle
    case waitingForTransition(RevealPathGraceLoopContext)
    case yieldingFrame(RevealPathGraceLoopContext)
    case refreshingVisibleTree(RevealPathGraceLoopContext)
    case resolvingVisibleTarget(RevealPathGraceLoopContext)
    case attemptingKnownTargetReveal(RevealPathGraceLoopContext)
    case finished
}

enum RevealPathGraceEvent: Sendable, Equatable {
    case begin(cursor: AccessibilityNotificationCursor, remaining: Double)
    case transitionWaitCompleted(AccessibilityNotificationCursor?)
    case frameYielded
    case visibleTreeRefreshCompleted(Bool, remaining: Double)
    case visibleTargetResolved
    case visibleTargetFailed
    case visibleTargetMissing(remaining: Double)
    case knownTargetRevealAttempted(RevealPathGraceKnownRevealResult, remaining: Double)
    case cancelled
}

enum RevealPathGraceEffect: Sendable, Equatable {
    case waitForTransitionEvent(after: AccessibilityNotificationCursor, timeout: Double)
    case yieldRealFrame
    case refreshVisibleTree
    case resolveVisibleTarget
    case attemptKnownTargetReveal
    case finish(RevealPathGraceFinish)
}

enum RevealPathGraceFinish: Sendable, Equatable {
    case resolvedVisible
    case failedVisibleTarget
    case resolvedAfterKnownReveal(didReveal: Bool)
    case timedOut
    case cancelled
}

enum RevealPathGraceKnownRevealResult: Sendable, Equatable {
    case unavailable
    case failed
    case revealed(didReveal: Bool)
}

enum RevealPathGraceRejection: Sendable, Equatable {
    case invalidTransition
    case alreadyFinished
}

extension StateChange
where State == RevealPathGraceState,
      Effect == RevealPathGraceEffect,
      Rejection == RevealPathGraceRejection {
    var revealPathGraceEffect: RevealPathGraceEffect {
        guard let effect = singleEffect else {
            preconditionFailure("RevealPathGraceMachine must emit exactly one effect per accepted event.")
        }
        return effect
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
