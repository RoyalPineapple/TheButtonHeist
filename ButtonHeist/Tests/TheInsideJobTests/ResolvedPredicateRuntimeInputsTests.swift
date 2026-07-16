#if canImport(UIKit)
import XCTest
@_spi(ButtonHeistInternals) @testable import ThePlans
@testable import TheInsideJob

final class ResolvedPredicateRuntimeInputsTests: XCTestCase {
    func testWaitInputPreservesAuthoredEvidenceAndResolvedEvaluation() throws {
        let title: HeistReferenceName = "title"
        let expression = AccessibilityPredicate.exists(.label(.exact(title)))
        let input = try ResolvedWaitRuntimeInput(
            resolving: WaitStep(predicate: expression, timeout: 4),
            in: HeistExecutionEnvironment(strings: [title: "Dashboard"])
        )

        XCTAssertEqual(input.predicateExpression, expression)
        XCTAssertEqual(
            input.predicate,
            try AccessibilityPredicate.exists(.label("Dashboard")).resolve(in: .empty)
        )
        XCTAssertEqual(input.timeout, 4)

    }

    func testPredicateCaseInputPreservesOneBodyAndResolvedEvaluation() throws {
        let title: HeistReferenceName = "title"
        let expression = ChangeDeclaration.ScreenAssertion.exists(.label(.exact(title)))
        let body = [HeistStep.warn(WarnStep(message: "matched"))]
        let input = try ResolvedPredicateCaseRuntimeInput(
            resolving: PredicateCase(predicate: expression, body: body),
            in: HeistExecutionEnvironment(strings: [title: "Dashboard"])
        )

        XCTAssertEqual(input.predicateExpression, expression)
        XCTAssertEqual(
            input.predicate.rootPredicate,
            try AccessibilityPredicate.exists(.label("Dashboard")).resolve(in: .empty)
        )
        XCTAssertEqual(input.body, body)
    }
}
#endif
