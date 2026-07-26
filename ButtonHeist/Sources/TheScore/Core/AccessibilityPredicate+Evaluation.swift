import ThePlans
import Foundation

package extension ResolvedAccessibilityPredicate {
    /// Answer this predicate from stored captures.
    ///
    /// The captures of a trace are a tick sequence, so a stored trace is
    /// replayed through the same `Expectation` a live run drains: each capture's
    /// interface is a snapshot, a replacement edge vacates the old screen and
    /// names the new one first, and a closing `noChange()` opens the settlement
    /// gate. One algebra, fed from history instead of the wire.
    func evaluate(in evidence: AccessibilityTraceEvidence) -> PredicateEvaluationResult {
        var expectation = Expectation([self])
        var previous: AccessibilityTrace.Capture?
        for capture in evidence.trace.captures {
            if let previous,
               AccessibilityObservationChangeReducer.reduce(between: previous, and: capture) == .screenChanged {
                expectation.empty(at: capture.interface.timestamp)
                expectation.screenChanged(ScreenFacts(
                    idAfter: InterfaceSummary.screenName(for: capture.interface)
                ))
            }
            expectation.snapshot(capture.interface)
            previous = capture
        }
        expectation.noChange()
        return PredicateEvaluationResult(
            met: expectation.isMet,
            actual: expectation.isMet ? nil : expectation.outstanding.joined(separator: "; ")
        )
    }

    func validate(against result: ActionResult) -> PredicateEvaluationResult {
        guard let evidence = result.traceEvidence else {
            return PredicateEvaluationResult(met: false, actual: "no observed accessibility trace")
        }
        return evaluate(in: evidence)
    }
}
