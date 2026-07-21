#if canImport(UIKit)
import XCTest
@testable import TheInsideJob

@MainActor
final class TheTripwirePolicyTests: XCTestCase {

    func testPulseReadingSettlementDependsOnlyOnLayoutAndQuietFrames() {
        let viewController = UIViewController()
        let cases: [(
            name: String,
            layoutPending: Bool,
            quietFrames: Int,
            topmostVC: ObjectIdentifier?,
            expected: Bool
        )] = [
            ("quiet", false, 2, nil, true),
            ("layout pending", true, 5, nil, false),
            ("one quiet frame", false, 1, nil, false),
            ("keyboard and view-controller signals", false, 2, ObjectIdentifier(viewController), true),
        ]

        for testCase in cases {
            let reading = TheTripwire.PulseReading(
                tick: 10,
                timestamp: CFAbsoluteTimeGetCurrent(),
                layoutPending: testCase.layoutPending,
                fingerprint: fingerprint(),
                topmostVC: testCase.topmostVC,
                tripwireSignal: .empty,
                windowCount: 3,
                quietFrames: testCase.quietFrames
            )

            XCTAssertEqual(reading.isSettled, testCase.expected, testCase.name)
        }
    }

    func testPresentationFingerprintRequiresStableLayerGeometry() {
        let baseline = fingerprint()
        let cases: [(name: String, candidate: TheTripwire.PresentationFingerprint, expected: Bool)] = [
            ("identical", baseline, true),
            ("within tolerance", fingerprint(frameMinXSum: 100.3, frameMinYSum: 200.4), true),
            ("origin drift", fingerprint(frameMinXSum: 101), false),
            ("size drift", fingerprint(frameWidthSum: 301), false),
            ("layer count drift", fingerprint(layerCount: 6), false),
        ]

        for testCase in cases {
            XCTAssertEqual(baseline.matches(testCase.candidate), testCase.expected, testCase.name)
        }
    }

    func testSemanticSignalProjectsOnlyDurableWindowFacts() {
        let viewController = UIViewController()
        let window = UIWindow()
        let signal = TheTripwire.TripwireSignal(
            topmostVC: ObjectIdentifier(viewController),
            navigation: .empty,
            windowStack: TheTripwire.WindowStackSignal(windows: [
                TheTripwire.WindowSignal(
                    id: ObjectIdentifier(window),
                    level: 7,
                    isKeyWindow: true
                ),
            ]),
            accessibilityNotificationSequence: 42
        )

        XCTAssertEqual(
            signal.semanticValue,
            TheTripwire.SemanticSignal(windows: [
                TheTripwire.SemanticWindowSignal(level: 7, isKeyWindow: true),
            ])
        )
    }

    private func fingerprint(
        frameMinXSum: CGFloat = 100,
        frameMinYSum: CGFloat = 200,
        frameWidthSum: CGFloat = 300,
        frameHeightSum: CGFloat = 400,
        layerCount: Int = 5
    ) -> TheTripwire.PresentationFingerprint {
        TheTripwire.PresentationFingerprint(
            frameMinXSum: frameMinXSum,
            frameMinYSum: frameMinYSum,
            frameWidthSum: frameWidthSum,
            frameHeightSum: frameHeightSum,
            layerCount: layerCount
        )
    }
}

#endif // canImport(UIKit)
