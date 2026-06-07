#if canImport(UIKit)
import XCTest

import TheInsideJob

private enum DemoHome {
    static let openMenu = HeistDef<Void>("DemoHome.openMenu") {
        Activate(.label("Menu"))
            .expect(.changed(.screen(where: .present(.label("Menu")))), timeout: .seconds(8))
    }
}

private enum MenuScreen {
    static let addItem = HeistDef<String>("MenuScreen.addItem", parameter: "item") { item in
        Activate(.label(item))
            .expect(.present(.label("Add to Cart")), timeout: .seconds(2))

        Activate(.label("Add to Cart"))
            .expect(.changed(.elements), timeout: .seconds(2))

        WaitFor(.absent(.label("Add to Cart")), timeout: .seconds(2))
    }

    static let checkout = HeistDef<Void>("MenuScreen.checkout") {
        Activate(.label("Place Order"))
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
            emoji: "\u{1F355}",
            name: "Margherita Pizza",
            price: Decimal(1400) / Decimal(100),
            detail: "San Marzano tomato, mozzarella, basil"
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
        let heist = try await Heist {
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
