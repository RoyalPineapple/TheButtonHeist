#if canImport(UIKit)
import UIKit
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class SettleSessionTests: XCTestCase {
    func makeElement(
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        traits: UIAccessibilityTraits = .none,
        frame: CGRect = .zero
    ) -> AccessibilityElement {
        .make(
            label: label,
            value: value,
            identifier: identifier,
            traits: traits,
            shape: .frame(AccessibilityRect(frame))
        )
    }

    func makeParseResult(_ elements: [AccessibilityElement]) -> InterfaceObservation {
        return InterfaceObservation.makeForTests(
            elements.enumerated().map { index, element in
                InterfaceObservation.TestEntry(
                    element,
                    heistId: HeistId(rawValue: "settle_\(index)")
                )
            }
        )
    }

    func settleFingerprint(_ elements: [AccessibilityElement]) -> Int {
        SettleTimeline.fingerprint(of: makeParseResult(elements), bucket: 13)
    }

    func makeSession(
        script: [InterfaceObservation?],
        cyclesRequired: Int = 3,
        cycleIntervalMs: Int = 1,
        timeoutMs: Int = 200,
        topVCSequence: [ObjectIdentifier?]? = nil,
        accessibilityNotificationSequence: [UInt64]? = nil
    ) -> SettleSession {
        let scriptBox = ScriptBox(script: script)
        let topVCBox = ScriptBox(script: topVCSequence ?? [nil])
        let notificationBox = ScriptBox(script: accessibilityNotificationSequence ?? [0])
        return SettleSession(
            parseProvider: { scriptBox.next() },
            tripwireSignalProvider: {
                self.tripwireSignal(
                    topmostVC: topVCBox.next(),
                    accessibilityNotificationSequence: notificationBox.next()
                )
            },
            sleeper: { _ in /* no real sleep; loop runs at wall-clock pace */ },
            cyclesRequired: cyclesRequired,
            cycleIntervalMs: cycleIntervalMs,
            timeoutMs: timeoutMs
        )
    }

    func tripwireSignal(
        topmostVC: ObjectIdentifier?,
        accessibilityNotificationSequence: UInt64 = 0
    ) -> TheTripwire.TripwireSignal {
        TheTripwire.TripwireSignal(
            topmostVC: topmostVC,
            navigation: .empty,
            windowStack: .empty,
            accessibilityNotificationSequence: accessibilityNotificationSequence
        )
    }

    final class ScriptBox<T> {
        private var script: [T]
        private var index: Int = 0

        init(script: [T]) {
            self.script = script
        }

        func next() -> T {
            let value = script[min(index, script.count - 1)]
            if index < script.count { index += 1 }
            return value
        }
    }

    final class Counter {
        private var value: Int = 0

        func next() -> Int {
            defer { value += 1 }
            return value
        }
    }

    final class ManualClock {
        private(set) var now = RuntimeElapsed.now

        func currentTime() -> RuntimeElapsed.Instant {
            now
        }

        func advance(milliseconds: Int) {
            now = now.advanced(by: .milliseconds(milliseconds))
        }
    }

    func makeQuietSession(
        script: [InterfaceObservation?],
        clock: ManualClock,
        frameMs: Int = 10,
        quietWindowMs: Int = 30,
        timeoutMs: Int = 500,
        topVCSequence: [ObjectIdentifier?]? = nil,
        accessibilityNotificationSequence: [UInt64]? = nil,
        yieldCount: Counter? = nil
    ) -> SettleSession {
        let scriptBox = ScriptBox(script: script)
        let topVCBox = ScriptBox(script: topVCSequence ?? [nil])
        let notificationBox = ScriptBox(script: accessibilityNotificationSequence ?? [0])
        return SettleSession(
            parseProvider: { scriptBox.next() },
            tripwireSignalProvider: {
                self.tripwireSignal(
                    topmostVC: topVCBox.next(),
                    accessibilityNotificationSequence: notificationBox.next()
                )
            },
            observationYield: { _ in
                _ = yieldCount?.next()
                clock.advance(milliseconds: frameMs)
                return .observed
            },
            clock: { clock.currentTime() },
            quietWindowMs: quietWindowMs,
            timeoutMs: timeoutMs
        )
    }
}
#endif // canImport(UIKit)
