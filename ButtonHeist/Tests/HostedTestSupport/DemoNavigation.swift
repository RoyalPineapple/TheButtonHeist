#if canImport(UIKit)
import UIKit
import ButtonHeistTesting

package enum DemoNavigation {
    private static let anyBackTarget = ElementPredicateTemplate(traits: [.backButton])
    private static let rootBackTarget = ElementPredicateTemplate(label: .exact("ButtonHeist Demo"), traits: [.button])
    private static let rootTitle = ElementPredicateTemplate(label: .exact("ButtonHeist Demo"), traits: [.header])
    private static let longListFirstRow = ElementPredicateTemplate(label: .exact("Widget 0, Hardware"))
    private static let backChromeSettleTimeout = 0.25

    package static let backToRootIfNeeded = HeistDef<Void>("DemoNavigation.backToRootIfNeeded") {
        try backOneLevelIfNeeded()
        try backOneLevelIfNeeded()
        try backOneLevelIfNeeded()
        try backOneLevelIfNeeded()
        try backOneLevelIfNeeded()
        WaitFor(.missing(.predicate(anyBackTarget)), timeout: .seconds(2))
        WaitFor(.missing(.predicate(rootBackTarget)), timeout: .seconds(2))
        WaitFor(.exists(.predicate(rootTitle)), timeout: .seconds(4))
    }

    package static let backToRoot = HeistDef<Void>("DemoNavigation.backToRoot") {
        try backToRootIfNeeded()
    }

    package static let openMenu = HeistDef<Void>("DemoNavigation.openMenu") {
        try backToRootIfNeeded()

        Activate(.label("Menu"))
            .expect(.changed(.screen([.exists(.label("Menu"))])), timeout: .seconds(8))
    }

    @MainActor
    package static func openAdversarialScenario(_ scenario: String) throws {
        var components = URLComponents()
        components.scheme = "buttonheist-demo"
        components.host = "adversarial"
        components.queryItems = [URLQueryItem(name: "scenario", value: scenario)]
        guard let url = components.url else {
            throw DemoNavigationError.adversarialRouteUnavailable(scenario)
        }
        UIApplication.shared.open(url, options: [:])
    }

    package static let backTo = HeistDef<String>("DemoNavigation.backTo", parameter: "title") { title in
        let destinationTitle = ElementPredicateTemplate(label: .exact(title), traits: [.header])

        Activate(.predicate(ElementPredicateTemplate(label: .exact(title), traits: [.backButton])))
            .withoutExpectation("Back navigation is proven by the destination title wait")

        WaitFor(.exists(.predicate(destinationTitle)), timeout: .seconds(8))
    }

    private static let backOneLevelIfNeeded = HeistDef<Void>("DemoNavigation.backOneLevelIfNeeded") {
        try reanchorLongListIfNeeded()

        WaitFor(.exists(.predicate(rootBackTarget)), timeout: .seconds(backChromeSettleTimeout))
            .else {}

        If {
            Case(.exists(.predicate(rootBackTarget))) {
                Activate(.predicate(rootBackTarget))
                    .expect(.changed(.screen()), timeout: .seconds(8))
            }
            Case(.exists(.predicate(anyBackTarget))) {
                Activate(.predicate(anyBackTarget))
                    .expect(.changed(.screen()), timeout: .seconds(8))
            }
            Else {}
        }
    }

    private static let reanchorLongListIfNeeded = HeistDef<Void>("DemoNavigation.reanchorLongListIfNeeded") {
        If {
            Case(.exists(.predicate(longListFirstRow))) {
                WaitFor(.exists(.predicate(longListFirstRow)), timeout: .seconds(1))
            }
            Else {}
        }
    }
}

package enum DemoNavigationError: Error {
    case adversarialRouteUnavailable(String)
}

#endif // canImport(UIKit)
