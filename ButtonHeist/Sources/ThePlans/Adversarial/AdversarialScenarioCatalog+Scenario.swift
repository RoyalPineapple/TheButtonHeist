extension AdversarialScenarioCatalog {
    public enum Scenario: String, CaseIterable, Sendable {
        case asyncRevealNotificationPass
        case asyncRevealSilentPass
        case asyncRevealWrongDestinationFails
        case offscreenCheckoutPass
        case offscreenCheckoutDisabledFails
        case duplicateLabelIdentityPass
        case dynamicCellsPass
        case dynamicCellsStaleTargetFails
        case textFieldFallbackPass
        case textFieldFallbackTargetlessFails
        case staleLiveObjectPass
        case staleLiveObjectAmbiguousFails
        case modalObstructionPass
        case modalObstructionBackgroundFails
        case nestedScrollPass
        case nestedScrollImpossibleFails

        public var route: Route {
            switch self {
            case .asyncRevealNotificationPass, .asyncRevealSilentPass, .asyncRevealWrongDestinationFails:
                .asyncReveal
            case .offscreenCheckoutPass, .offscreenCheckoutDisabledFails:
                .offscreenCheckout
            case .duplicateLabelIdentityPass:
                .duplicateLabels
            case .dynamicCellsPass, .dynamicCellsStaleTargetFails:
                .dynamicCells
            case .textFieldFallbackPass, .textFieldFallbackTargetlessFails:
                .textFieldFallback
            case .staleLiveObjectPass, .staleLiveObjectAmbiguousFails:
                .staleLiveObject
            case .modalObstructionPass, .modalObstructionBackgroundFails:
                .modalObstruction
            case .nestedScrollPass, .nestedScrollImpossibleFails:
                .nestedScroll
            }
        }

        public var classification: Classification {
            self == .duplicateLabelIdentityPass || expectedOutcome == .commandFailsWithDiagnostic
                ? .deterministic
                : .statistical
        }

        public var expectedOutcome: ExpectedOutcome {
            expectedEvidence.contains { $0.kind == .diagnostic }
                ? .commandFailsWithDiagnostic
                : .commandSucceeds
        }

        public var expectedEvidence: [Evidence] {
            switch self {
            case .asyncRevealNotificationPass:
                [.notification("Delayed code: 7429")]
            case .asyncRevealSilentPass:
                [.element("Delayed code: 7429")]
            case .asyncRevealWrongDestinationFails:
                [.diagnostic("Delayed code: 9999")]
            case .offscreenCheckoutPass:
                [.element("Checkout activations", value: "1")]
            case .offscreenCheckoutDisabledFails:
                [.diagnostic("Unavailable order")]
            case .duplicateLabelIdentityPass:
                [.element("Home High activations", value: "2")]
            case .dynamicCellsPass:
                [.element("Nebula Noodles")]
            case .dynamicCellsStaleTargetFails:
                [.diagnostic("Generation")]
            case .textFieldFallbackPass:
                [.element("Fallback field", value: "fallback typed")]
            case .textFieldFallbackTargetlessFails:
                [.diagnostic("TypeText")]
            case .staleLiveObjectPass:
                [.element("Submit Order", value: "Generation 2, actions 1, generation 1 actions 0")]
            case .staleLiveObjectAmbiguousFails:
                [.diagnostic("ambiguous")]
            case .modalObstructionPass:
                [.element("Status: Review confirmed")]
            case .modalObstructionBackgroundFails:
                [.diagnostic("Archive order 3")]
            case .nestedScrollPass:
                [.element("Nested target activations", value: "1")]
            case .nestedScrollImpossibleFails:
                [.diagnostic("Album That Does Not Exist")]
            }
        }

        public func manifest() throws -> Manifest {
            Manifest(
                name: rawValue,
                route: route.rawValue,
                classification: classification,
                expectedOutcome: expectedOutcome,
                expectedEvidence: expectedEvidence,
                plan: try plan().canonicalSwiftDSL()
            )
        }

        public func plan() throws -> HeistPlan {
            let body = try bodyPlan()
            return try HeistPlan(HeistPlanName(validating: rawValue)) {
                WaitFor(.exists(.label(route.title)), timeout: 4)
                body
            }
        }

        private func bodyPlan() throws -> HeistPlan {
            switch self {
            case .asyncRevealNotificationPass:
                try HeistPlan {
                    Activate(.label("Reveal with notification"))
                        .expect(.exists(.label("Delayed code: 7429")), timeout: 3)
                }
            case .asyncRevealSilentPass:
                try HeistPlan {
                    Activate(.label("Reveal silently"))
                        .expect(.exists(.label("Delayed code: 7429")), timeout: 3)
                }
            case .asyncRevealWrongDestinationFails:
                try HeistPlan {
                    Activate(.label("Reveal silently"))
                        .withoutExpectation("The failing wait proves async destination diagnostics")
                    WaitFor(.exists(.label("Delayed code: 9999")), timeout: 0.2)
                }
            case .offscreenCheckoutPass:
                try HeistPlan {
                    Activate(.element(.label("Place order"), .traits([.button])))
                        .expect(.exists(.label("Order placed")), timeout: 4)
                    WaitFor(.exists(.element(.label("Checkout activations"), .value("1"))), timeout: 2)
                }
            case .offscreenCheckoutDisabledFails:
                try HeistPlan {
                    Activate(.element(.label("Unavailable order"), .traits([.button])))
                }
            case .duplicateLabelIdentityPass:
                try HeistPlan {
                    let target = AccessibilityTarget.label("Review PR").and(
                        .customContent(.init(label: "Category", value: "Home")),
                        .customContent(.init(label: "Priority", value: "High"))
                    )
                    WaitFor(.exists(target), timeout: 4)
                    Activate(target)
                        .expect(.exists(.element(.label("Home High activations"), .value("1"))), timeout: 6)
                    WaitFor(.exists(.element(.label("Duplicate candidate order"), .value("Reordered"))), timeout: 2)
                    Activate(.label("Return to duplicate top"))
                        .expect(.exists(.element(.label("Duplicate target visibility"), .value("Offscreen"))), timeout: 6)
                    WaitFor(.exists(target), timeout: 2)
                    Activate(target)
                        .expect(.exists(.element(.label("Home High activations"), .value("2"))), timeout: 6)
                    WaitFor(.exists(.element(.label("Work High activations"), .value("0"))), timeout: 2)
                    WaitFor(.exists(.element(.label("Work Low activations"), .value("0"))), timeout: 2)
                }
            case .dynamicCellsPass:
                try HeistPlan {
                    Activate(.label("Churn menu"))
                        .expect(.exists(.label("Menu churned")), timeout: 4)
                    CustomAction("Add to Cart", on: .element(
                        .label("Nebula Noodles"),
                        .customContent(.init(label: "SKU", value: "SKU-72")),
                        .customContent(.init(label: "Generation", value: "2")),
                        .actions([.custom("Add to Cart")])
                    ))
                        .expect(.exists(.element(
                            .label("Nebula Noodles"),
                            .customContent(.init(label: "Quantity", value: "1")),
                            .actions([.custom("Remove from Cart")])
                        )), timeout: 6)
                }
            case .dynamicCellsStaleTargetFails:
                try HeistPlan {
                    Activate(.label("Churn menu"))
                        .expect(.exists(.label("Menu churned")), timeout: 4)
                    CustomAction("Add to Cart", on: .element(
                        .label("Nebula Noodles"),
                        .customContent(.init(label: "SKU", value: "SKU-72")),
                        .customContent(.init(label: "Generation", value: "1")),
                        .actions([.custom("Add to Cart")])
                    ))
                }
            case .textFieldFallbackPass, .textFieldFallbackTargetlessFails,
                 .staleLiveObjectPass, .staleLiveObjectAmbiguousFails,
                 .modalObstructionPass, .modalObstructionBackgroundFails,
                 .nestedScrollPass, .nestedScrollImpossibleFails:
                try remainingBodyPlan()
            }
        }

        private func remainingBodyPlan() throws -> HeistPlan {
            switch self {
            case .textFieldFallbackPass:
                try HeistPlan {
                    TypeText(.replacing("fallback typed"), into: .element(
                        .label("Fallback field"),
                        .traits([.textEntry])
                    ))
                        .expect(.exists(.value("fallback typed")), timeout: 3)
                    dismissKeyboard()
                        .withoutExpectation("Returns the app to navigation after text entry")
                }
            case .textFieldFallbackTargetlessFails:
                try HeistPlan {
                    TypeText("orphan typed")
                }
            case .staleLiveObjectPass:
                try HeistPlan {
                    Activate(.label("Submit Order"))
                        .expect(.exists(.element(
                            .label("Submit Order"),
                            .value("Generation 2, actions 1, generation 1 actions 0")
                        )), timeout: 4)
                }
            case .staleLiveObjectAmbiguousFails:
                try HeistPlan {
                    WaitFor(.exists(.element(
                        .label("Submit Order"),
                        .value("Generation 2, actions 0, generation 1 actions 0")
                    )), timeout: 3)
                    Activate(.label("Show Duplicate Target"))
                        .expect(.exists(.element(
                            .label("Submit Order"),
                            .value("Generation 3, actions 0, generation 1 actions 0")
                        )), timeout: 2)
                    Activate(.label("Submit Order"))
                }
            case .modalObstructionPass:
                try HeistPlan {
                    Activate(.label("Review order"))
                        .expect(.exists(.element(.label("Order review"), .value("Ready"))), timeout: 4)
                    Activate(.label("Confirm review"))
                        .expect(.exists(.label("Status: Review confirmed")), timeout: 2)
                    Activate(.label("Close"))
                        .expect(.missing(.label("Order review")), timeout: 4)
                }
            case .modalObstructionBackgroundFails:
                try HeistPlan {
                    Activate(.label("Review order"))
                        .expect(.exists(.element(.label("Order review"), .value("Ready"))), timeout: 4)
                    Activate(.label("Archive order 3"))
                }
            case .nestedScrollPass:
                try HeistPlan {
                    Activate(.element(
                        .label("Verified by The Vibe Check"),
                        .value("The Vibe Check"),
                        .traits([.button])
                    ))
                        .expect(.exists(.label("Selected Verified")), timeout: 6)
                    WaitFor(.exists(.element(.label("Nested target activations"), .value("1"))), timeout: 2)
                }
            case .nestedScrollImpossibleFails:
                try HeistPlan {
                    Activate(.label("Album That Does Not Exist"))
                }
            case .asyncRevealNotificationPass, .asyncRevealSilentPass,
                 .asyncRevealWrongDestinationFails, .offscreenCheckoutPass,
                 .offscreenCheckoutDisabledFails, .duplicateLabelIdentityPass,
                 .dynamicCellsPass, .dynamicCellsStaleTargetFails:
                preconditionFailure("Scenario is not in the remaining plan partition")
            }
        }
    }
}
