#if canImport(UIKit)
import XCTest
import ThePlans

import TheInsideJob

private enum DemoHome {
    static let openMenu = HeistDef<Void>("DemoHome.openMenu") {
        Activate(.label("Menu"))
            .expect(.changed(.screen(where: .present(.label("Menu")))), timeout: .seconds(8))
    }
}

private enum MenuScreen {
    static let addItem = HeistDef<String>("MenuScreen.addItem", parameter: "item") { item in
        try rawAction(
            .viewportScrollToVisible(.label(item)),
            waiver: "scroll_to_visible is the viewport precondition for the row custom action"
        )

        CustomAction("Add to Cart", on: .label(item))
            .expect(.changed(.elements), timeout: .seconds(2))
    }

    static let checkout = HeistDef<Void>("MenuScreen.checkout") {
        Activate(.label("Checkout"))
            .expect(.changed(.screen(where: .present(.label("Checkout")))), timeout: .seconds(8))

        Activate(.label(DemoOrder.confirmPaymentLabel))
            .expect(.changed(.screen(where: .present(.label("Processing payment")))), timeout: .seconds(8))

        WaitFor(.present(.label("Payment Successful")), timeout: .seconds(12))
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
        let heist = try await RunHeist("MenuOrderDogfood_orderTwoItems") {
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

private func rawAction(
    _ command: HeistActionCommand,
    expectation: WaitStep? = nil,
    waiver: String? = nil
) throws -> HeistStep {
    .action(try ActionStep(command: command, expectation: expectation, expectationWaiver: waiver))
}

#endif // canImport(UIKit)
