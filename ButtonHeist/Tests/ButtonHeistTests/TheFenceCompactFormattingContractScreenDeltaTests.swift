import ButtonHeistTestSupport
import XCTest
import ThePlans
import AccessibilitySnapshotModel
@_spi(ButtonHeistTooling) @testable import ButtonHeist
import TheScore

extension TheFenceCompactFormattingContractTests {

    func testScreenChangedActionOutputIncludesDestinationSummaryTree() throws {
        let destination = makeTestInterface(elements: [
            makeTestHeistElement(label: "Checkout", identifier: "checkout_title", traits: [.header]),
            makeTestHeistElement(label: "Pay", identifier: "pay_button", traits: [.button], actions: [.activate]),
        ])
        let trace = makeTestTrace(
            before: makeTestInterface(elements: [makeTestHeistElement(label: "Cart", identifier: "cart_title")]),
            after: destination,
            beforeScreenId: "cart",
            afterScreenId: "checkout",
            afterTransition: makeTestScreenChangedTransition()
        )
        let response = FenceResponse.action(
            command: .activate,
            result: ActionResult.success(
                payload: .activate,
                observation: .trace(makeTestTraceEvidence(trace, completeness: .incomplete))
            )
        )

        let delta = try publicJSONProbe(response).object("delta")
        let newInterface = try delta.object("newInterface")
        let compact = response.compactFormatted()
        let human = response.humanFormatted()

        XCTAssertEqual(try delta.string("kind"), "screenChanged")
        XCTAssertEqual(try newInterface.array("tree").count, 2)
        XCTAssertTrue(compact.contains("activate: screen changed\nCheckout\n2 elements"), compact)
        XCTAssertTrue(compact.contains(#""Checkout" header id="checkout_title""#), compact)
        XCTAssertTrue(compact.contains(#""Pay" button id="pay_button""#), compact)
        XCTAssertTrue(human.contains("screen changed]\nCheckout\n2 elements"), human)
        XCTAssertTrue(human.contains(#""Checkout" header id="checkout_title""#), human)
    }

    func testLaterScreenChangeDominatesEarlierElementFactsAndDeduplicatesTransitionEvidence() throws {
        let toast = makeTestHeistElement(label: "Saved", identifier: "saved_toast", traits: [.staticText])
        let cart = makeTestInterface(elements: [
            makeTestHeistElement(label: "Cart", identifier: "cart_title", traits: [.header]),
        ])
        let cartWithToast = makeTestInterface(elements: [toast] + cart.projectedElements)
        let checkout = makeTestInterface(elements: [
            makeTestHeistElement(label: "Checkout", identifier: "checkout_title", traits: [.header]),
        ])
        let before = AccessibilityTrace.Capture(
            sequence: 1,
            interface: cart,
            context: AccessibilityTrace.Context(screenId: "cart")
        )
        let elementChange = AccessibilityTrace.Capture(
            sequence: 2,
            interface: cartWithToast,
            parentHash: before.hash,
            context: AccessibilityTrace.Context(screenId: "cart")
        )
        let after = AccessibilityTrace.Capture(
            sequence: 3,
            interface: checkout,
            parentHash: elementChange.hash,
            context: AccessibilityTrace.Context(screenId: "checkout"),
            transition: makeTestScreenChangedTransition(sequence: 9)
        )
        let trace = AccessibilityTrace(captures: [before, elementChange, after])
        let response = FenceResponse.action(
            command: .activate,
            result: ActionResult.success(
                payload: .activate,
                observation: .trace(makeTestTraceEvidence(trace, completeness: .incomplete))
            )
        )

        let delta = try publicJSONProbe(response).object("delta")

        XCTAssertEqual(try delta.string("kind"), "screenChanged")
        XCTAssertEqual(try delta.array("transient").count, 1)
        XCTAssertEqual(try delta.array("transient").first?.string("identifier"), "saved_toast")
        try delta.assertMissing("edits")
    }
}
