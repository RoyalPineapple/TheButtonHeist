#if canImport(UIKit)
import XCTest

import ButtonHeistTesting

private enum DemoHome {
    private static let anyBackTarget = ElementPredicateTemplate(traits: [.backButton])
    private static let rootBackTarget = ElementPredicateTemplate(label: .exact("ButtonHeist Demo"), traits: [.button])
    private static let rootTitle = ElementPredicateTemplate(label: .exact("ButtonHeist Demo"), traits: [.header])
    private static let longListFirstRow = ElementPredicateTemplate(label: .exact("Widget 0, Hardware"))
    private static let backChromeSettleTimeout = 0.25

    static let openMenu = HeistDef<Void>("DemoHome.openMenu") {
        try backOneLevelIfNeeded()
        try backOneLevelIfNeeded()
        try backOneLevelIfNeeded()
        try backOneLevelIfNeeded()
        try backOneLevelIfNeeded()
        WaitFor(.missing(anyBackTarget), timeout: .seconds(2))
        WaitFor(.missing(rootBackTarget), timeout: .seconds(2))
        WaitFor(.exists(rootTitle), timeout: .seconds(4))

        Activate(.label("Menu"))
            .expect(.change(.screen(.exists(.label("Menu")))), timeout: .seconds(8))
    }

    private static let backOneLevelIfNeeded = HeistDef<Void>("DemoHome.backOneLevelIfNeeded") {
        try reanchorLongListIfNeeded()

        WaitFor(.exists(rootBackTarget), timeout: .seconds(backChromeSettleTimeout))
            .else {}

        If {
            Case(.exists(rootBackTarget)) {
                Activate(.predicate(rootBackTarget))
                    .expect(.change(.screen()), timeout: .seconds(8))
            }
            Case(.exists(anyBackTarget)) {
                Activate(.predicate(anyBackTarget))
                    .expect(.change(.screen()), timeout: .seconds(8))
            }
            Else {}
        }
    }

    private static let reanchorLongListIfNeeded = HeistDef<Void>("DemoHome.reanchorLongListIfNeeded") {
        If {
            Case(.exists(longListFirstRow)) {
                WaitFor(.exists(longListFirstRow), timeout: .seconds(1))
            }
            Else {}
        }
    }
}

private enum MenuScreen {
    static let addItem = HeistDef<String>("MenuScreen.addItem", parameter: "item") { item in
        CustomAction("Add to Cart", on: .label(item))
            .expect(.change(.elements()), timeout: .seconds(2))
    }

    static let checkout = HeistDef<Void>("MenuScreen.checkout") {
        Activate(.label("Checkout"))
            .expect(.change(.screen(.exists(.label("Checkout")))), timeout: .seconds(8))

        Activate(.label(DemoOrder.confirmPaymentLabel))
            .expect(.change(.screen(.exists(.label("Processing payment")))), timeout: .seconds(8))

        WaitFor(.exists(.label("Payment Successful")), timeout: .seconds(12))
    }
}

private enum DemoOrder {
    static let itemLabels = items.map(\.accessibilityLabel)

    static let confirmPaymentLabel = "Confirm Payment \u{2014} \(total.dogfoodUSDFormatted)"

    private static let items = [
        DemoMenuItem(
            emoji: "\u{1F957}",
            name: "Greek Salad",
            price: Decimal(950) / Decimal(100),
            detail: "Tomato, cucumber, olives, and feta"
        ),
        DemoMenuItem(
            emoji: "\u{1F346}",
            name: "Eggplant Parmesan",
            price: Decimal(1500) / Decimal(100),
            detail: "Breaded eggplant with marinara and cheese"
        ),
    ]

    private static let subtotal = items.reduce(Decimal.zero) { $0 + $1.price }
    private static let total = subtotal + subtotal * (Decimal(8) / Decimal(100))
}

private struct DemoMenuItem {
    let emoji: String
    let name: String
    let price: Decimal
    let detail: String

    var accessibilityLabel: String {
        "\(emoji), \(name), \(price.dogfoodUSDFormatted), \(detail)"
    }
}

@MainActor
final class MenuOrderDogfoodHeistTests: XCTestCase {

    func testMenuOrderFlowUsesReusablePublicHeists() async throws {
        let heist = try await runHeist("MenuOrderDogfood_orderTwoItems") {
            try DemoHome.openMenu()

            ForEach(DemoOrder.itemLabels) { item in
                try MenuScreen.addItem(item)
            }

            try MenuScreen.checkout()
        }

        XCTAssertEqual(heist.result.steps.map(\.kind), [.invoke, .forEachString, .invoke])
        XCTAssertEqual(heist.result.steps.first?.reportDisplayName, #"RunHeist("DemoHome.openMenu")"#)
        XCTAssertEqual(heist.result.steps.last?.reportDisplayName, #"RunHeist("MenuScreen.checkout")"#)
        XCTAssertEqual(heist.result.steps[1].forEachStringEvidence?.iterationCount, DemoOrder.itemLabels.count)
    }
}

private extension Decimal {
    var dogfoodUSDFormatted: String {
        formatted(.currency(code: "USD"))
    }
}

#endif // canImport(UIKit)
