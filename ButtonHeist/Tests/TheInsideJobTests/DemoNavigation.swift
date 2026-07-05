#if canImport(UIKit)
import ButtonHeistTesting

enum DemoNavigation {
    private static let anyBackTarget = ElementPredicateTemplate(traits: [.backButton])
    private static let rootBackTarget = ElementPredicateTemplate(label: .exact("ButtonHeist Demo"), traits: [.button])
    private static let rootTitle = ElementPredicateTemplate(label: .exact("ButtonHeist Demo"), traits: [.header])
    private static let longListFirstRow = ElementPredicateTemplate(label: .exact("Widget 0, Hardware"))
    private static let backChromeSettleTimeout = 0.25

    static let backToRootIfNeeded = HeistDef<Void>("DemoNavigation.backToRootIfNeeded") {
        try backOneLevelIfNeeded()
        try backOneLevelIfNeeded()
        try backOneLevelIfNeeded()
        try backOneLevelIfNeeded()
        try backOneLevelIfNeeded()
        WaitFor(.missing(anyBackTarget), timeout: .seconds(2))
        WaitFor(.missing(rootBackTarget), timeout: .seconds(2))
        WaitFor(.exists(rootTitle), timeout: .seconds(4))
    }

    static let backToRoot = HeistDef<Void>("DemoNavigation.backToRoot") {
        try backToRootIfNeeded()
    }

    static let openMenu = HeistDef<Void>("DemoNavigation.openMenu") {
        try backToRootIfNeeded()

        Activate(.label("Menu"))
            .expect(.change(.screen(.exists(.label("Menu")))), timeout: .seconds(8))
    }

    static let openAdversarialScenario = HeistDef<String>("DemoNavigation.openAdversarialScenario", parameter: "scenario") { scenario in
        try backToRootIfNeeded()

        Activate(.element(.label("Adversarial Lab"), .traits([.button])))
            .expect(.exists(.element(.label("Adversarial Lab"), .traits([.header]))), timeout: .seconds(8))

        Activate(.predicate(ElementPredicateTemplate(label: .exact(scenario), traits: [.button])))
            .expect(.exists(.label(scenario)), timeout: .seconds(8))
    }

    static let backTo = HeistDef<String>("DemoNavigation.backTo", parameter: "title") { title in
        let destinationTitle = ElementPredicateTemplate(label: .exact(title), traits: [.header])

        Activate(.predicate(ElementPredicateTemplate(label: .exact(title), traits: [.backButton])))
            .withoutExpectation("Back navigation is proven by the destination title wait")

        WaitFor(.exists(destinationTitle), timeout: .seconds(8))
    }

    private static let backOneLevelIfNeeded = HeistDef<Void>("DemoNavigation.backOneLevelIfNeeded") {
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

    private static let reanchorLongListIfNeeded = HeistDef<Void>("DemoNavigation.reanchorLongListIfNeeded") {
        If {
            Case(.exists(longListFirstRow)) {
                WaitFor(.exists(longListFirstRow), timeout: .seconds(1))
            }
            Else {}
        }
    }
}

#endif // canImport(UIKit)
