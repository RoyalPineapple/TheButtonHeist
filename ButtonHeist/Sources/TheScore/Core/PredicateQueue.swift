import ThePlans

/// One event on the settlement timeline.
///
/// A tick carries exactly one thing: the next snapshot, or the next
/// announcement. Not a snapshot with announcements attached — announcements are
/// peers of snapshots on the same clock, not a side channel riding along.
///
/// A tick that carries nothing is keep-alive bookkeeping and never
/// reaches this queue.
package enum PredicateTick: Sendable {
    /// A settled tree state, and the baseline deltas measure it against.
    ///
    /// The baseline is global to the run, not per predicate and not per fact.
    /// A delta predicate asks the baseline rather than resolving which two
    /// captures it is about.
    case snapshot(current: AccessibilityTraceEvidence, baseline: Interface?)

    /// Spoken accessibility text. Not in the graph, so matched as a string.
    case announcement(String)

    /// Whether a predicate of this kind answers this tick.
    ///
    /// This is the *only* kind-specific question the queue asks. Everything
    /// else — the walk, the blocking, the removal — is written once.
    func isAnswered(by predicate: ResolvedAccessibilityPredicate) -> Bool {
        switch (self, predicate) {
        case (.announcement, .announcement):
            return true
        case (.snapshot, .announcement), (.announcement, _):
            return false
        case (.snapshot, _):
            return true
        }
    }
}

/// The predicates a step is still waiting on, in authored order.
///
/// "Satisfied" is not state. There is no flag on a predicate and no lifecycle:
/// satisfied means *absent from the list*. A predicate cannot be asked a
/// question at the wrong time because there is no wrong time to be in.
///
/// The whole step state is this list plus the baseline, so a session is a fold
/// over ticks and replays identically from the same input.
package struct PredicateQueue: Sendable, Equatable {
    package let pending: [ResolvedAccessibilityPredicate]

    package init(_ pending: [ResolvedAccessibilityPredicate]) {
        self.pending = pending
    }

    package var isEmpty: Bool { pending.isEmpty }

    /// The queue after a tick, leaving this one untouched.
    ///
    /// A tick walks the list in order, asking only the predicates that answer
    /// its type. Each one it satisfies drops out. **The first one that answers
    /// its type and is not satisfied blocks the rest** — the walk stops there,
    /// and everything behind it waits even if this tick would have matched it.
    /// Blocking is the consumption step: it is what stops a later predicate
    /// from being satisfied by an earlier event.
    ///
    /// A predicate of another type is not asked and does not block. A snapshot
    /// tick passes an unsatisfied announcement predicate as if it were absent.
    ///
    /// A tick is **not spent on one predicate** — it keeps satisfying
    /// consecutive predicates of its type until one refuses. A tick is one
    /// *settled* snapshot, and a settled state can evidence several arrivals at
    /// once; spending it per predicate would make the verdict depend on how
    /// finely the tripwire happened to sample, so the same interface would pass
    /// or fail with different frame timing.
    package func advanced(by tick: PredicateTick) -> PredicateQueue {
        let blocked = pending.firstIndex {
            tick.isAnswered(by: $0) && !satisfies(tick, $0)
        } ?? pending.endIndex

        return PredicateQueue(
            pending.enumerated()
                .filter { $0.offset >= blocked || !tick.isAnswered(by: $0.element) }
                .map(\.element)
        )
    }

    private func satisfies(
        _ tick: PredicateTick,
        _ predicate: ResolvedAccessibilityPredicate
    ) -> Bool {
        switch tick {
        case .snapshot(let evidence, _):
            return predicate.evaluate(in: evidence).met
        case .announcement(let spoken):
            guard case .announcement(let match) = predicate else { return false }
            return match.matches(spoken)
        }
    }
}
