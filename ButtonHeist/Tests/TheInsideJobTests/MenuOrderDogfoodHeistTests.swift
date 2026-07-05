#if canImport(UIKit)
import XCTest

import ButtonHeistTesting

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
    static let greekSaladLabel = greekSalad.accessibilityLabel
    static let eggplantParmesanLabel = eggplantParmesan.accessibilityLabel
    static let itemLabels = items.map(\.accessibilityLabel)

    static let confirmPaymentLabel = "Confirm Payment \u{2014} \(total.dogfoodUSDFormatted)"

    private static let greekSalad = DemoMenuItem(
        emoji: "\u{1F957}",
        name: "Greek Salad",
        price: Decimal(950) / Decimal(100),
        detail: "Tomato, cucumber, olives, and feta"
    )
    private static let eggplantParmesan = DemoMenuItem(
        emoji: "\u{1F346}",
        name: "Eggplant Parmesan",
        price: Decimal(1500) / Decimal(100),
        detail: "Breaded eggplant with marinara and cheese"
    )
    private static let items = [greekSalad, eggplantParmesan]

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
            try DemoNavigation.openMenu()

            ForEach(DemoOrder.greekSaladLabel, DemoOrder.eggplantParmesanLabel) { item in
                try MenuScreen.addItem(item)
            }

            try MenuScreen.checkout()
        }

        XCTAssertEqual(heist.result.steps.map(\.kind), [.invoke, .forEachString, .invoke])
        XCTAssertEqual(heist.result.steps.first?.reportDisplayName, #"RunHeist("DemoNavigation.openMenu")"#)
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
