#if canImport(UIKit)
import XCTest
@testable import TheInsideJob

@MainActor
final class TheTripwirePolicyTests: XCTestCase {

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
}

#endif // canImport(UIKit)
