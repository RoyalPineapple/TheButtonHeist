#if canImport(UIKit)
#if DEBUG
import ButtonHeistTestSupport
import Testing

@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

// Finite observation ledger:
// - notification content uses present-text, present-element, and absent-content partitions —
//   `notification admission distinguishes text element and absent content`.
// - current and stale history cursors — `history cursor accepts its end and rejects future positions`.
// - protected retention and released-history gaps —
//   `TheVaultStateTests.testProtectedBoundaryPreventsEvictionUntilReleased` and
//   `testEvictedRangeProducesIncompleteEvidence`.
// - publication order and generation replacement —
//   `SemanticObservationReplayTests.testHistoryRetainsEventsInPublicationOrder` and
//   `ScreenGenerationTests.testCommittedDiscoveryReplacementAdvancesGenerationThroughHistory`.
// - notification ingress callback provenance and live UIAccessibility bridging remain Host/live boundaries.

@Suite struct ObservationInvariantLedgerTests {
    @Test func `notification admission distinguishes text element and absent content`() {
        let element = makeTestHeistElement(label: "Saved", traits: [.button]).semantics
        let cases: [(name: String, text: String?, element: HeistElement.Semantics?, admitted: Bool)] = [
            ("text", "Saved", nil, true),
            ("element", nil, element, true),
            ("absent", nil, nil, false),
        ]

        for entry in cases {
            let notification = Observation.Notification(text: entry.text, element: entry.element)
            #expect(
                (notification != nil) == entry.admitted,
                "Invariant violated: notification admission partition \(entry.name)"
            )
        }
    }

    @Test func `history cursor accepts its end and rejects future positions`() throws {
        var history = Observation.History(retentionLimit: 2)
        _ = history.record([.noChange], protectedBy: nil)
        let currentCursor = history.endIndex

        #expect(try history.events(after: currentCursor).isEmpty)
        #expect(throws: Observation.History.ReadError.rangeUnavailable) {
            try history.events(after: currentCursor + 1)
        }
    }
}
#endif
#endif
