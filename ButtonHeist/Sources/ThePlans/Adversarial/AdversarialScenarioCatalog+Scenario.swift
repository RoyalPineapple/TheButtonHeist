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
        case keyboardViewportReplacementPass
        case keyboardViewportAmbiguousReplacementFails
        case keyboardViewportIdentityMismatchFails
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
            case .keyboardViewportReplacementPass, .keyboardViewportAmbiguousReplacementFails,
                 .keyboardViewportIdentityMismatchFails:
                .keyboardViewport
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
                [
                    .notification("Delayed code: 7429"),
                    .element("Silent terminal state", value: "Generation 2"),
                ]
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
                [.diagnostic("text entry failed")]
            case .keyboardViewportReplacementPass:
                [
                    .element("Post interaction viewport value", value: "admitted viewport text"),
                    .element("Original viewport edits", value: "0"),
                    .element("Replacement viewport value", value: "admitted viewport text"),
                    .element("Keyboard continuation actions", value: "1"),
                    .element("Decoy continuation actions", value: "0"),
                ]
            case .keyboardViewportAmbiguousReplacementFails:
                [.diagnostic("ambiguous")]
            case .keyboardViewportIdentityMismatchFails:
                [.diagnostic("Viewport note")]
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
                    WaitFor(.exists(.element(
                        .label("Silent terminal state"),
                        .value("Generation 2")
                    )), timeout: 3)
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
                 .keyboardViewportReplacementPass, .keyboardViewportAmbiguousReplacementFails,
                 .keyboardViewportIdentityMismatchFails,
                 .staleLiveObjectPass, .staleLiveObjectAmbiguousFails,
                 .modalObstructionPass, .modalObstructionBackgroundFails,
                 .nestedScrollPass, .nestedScrollImpossibleFails:
                try remainingBodyPlan()
            }
        }

        private func remainingBodyPlan() throws -> HeistPlan {
            switch self {
            case .textFieldFallbackPass, .textFieldFallbackTargetlessFails:
                try textFieldFallbackBodyPlan()
            case .keyboardViewportReplacementPass, .keyboardViewportAmbiguousReplacementFails,
                 .keyboardViewportIdentityMismatchFails:
                try keyboardViewportBodyPlan()
            case .staleLiveObjectPass, .staleLiveObjectAmbiguousFails:
                try staleLiveObjectBodyPlan()
            case .modalObstructionPass, .modalObstructionBackgroundFails:
                try modalObstructionBodyPlan()
            case .nestedScrollPass, .nestedScrollImpossibleFails:
                try nestedScrollBodyPlan()
            case .asyncRevealNotificationPass, .asyncRevealSilentPass,
                 .asyncRevealWrongDestinationFails, .offscreenCheckoutPass,
                 .offscreenCheckoutDisabledFails, .duplicateLabelIdentityPass,
                 .dynamicCellsPass, .dynamicCellsStaleTargetFails:
                preconditionFailure("Scenario is not in the remaining plan partition")
            }
        }

        private func textFieldFallbackBodyPlan() throws -> HeistPlan {
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
            default:
                preconditionFailure("Scenario is not a text-field fallback case")
            }
        }

        private func keyboardViewportBodyPlan() throws -> HeistPlan {
            switch self {
            case .keyboardViewportReplacementPass:
                try keyboardViewportReplacementPlan()
            case .keyboardViewportAmbiguousReplacementFails:
                try keyboardViewportFailurePlan(
                    preparationLabel: "Prepare ambiguous viewport replacement",
                    mode: "ambiguous"
                )
            case .keyboardViewportIdentityMismatchFails:
                try keyboardViewportFailurePlan(
                    preparationLabel: "Prepare mismatched viewport replacement",
                    mode: "mismatched"
                )
            default:
                preconditionFailure("Scenario is not a keyboard viewport case")
            }
        }

        private func keyboardViewportReplacementPlan() throws -> HeistPlan {
            try HeistPlan {
                let note = AccessibilityTarget.element(
                    .label("Viewport note"),
                    .traits([.textEntry]),
                    .customContent(.init(label: "Semantic role", value: "body"))
                )
                let commit = AccessibilityTarget.element(
                    .label("Continue after keyboard"),
                    .traits([.button]),
                    .customContent(.init(label: "Action role", value: "commit"))
                )
                TypeText(.replacing("admitted viewport text"), into: note)
                    .expect(.exists(.element(
                        .label("Post interaction viewport value"),
                        .value("admitted viewport text")
                    )), timeout: 6)
                WaitFor(.exists(.element(.label("Original viewport edits"), .value("0"))), timeout: 2)
                WaitFor(.exists(.element(
                    .label("Replacement viewport value"),
                    .value("admitted viewport text")
                )), timeout: 2)
                dismissKeyboard()
                    .withoutExpectation("Dismisses the real keyboard before the next semantic action")
                Activate(commit)
                    .expect(.exists(.element(.label("Keyboard continuation actions"), .value("1"))), timeout: 4)
                WaitFor(.exists(.element(.label("Decoy continuation actions"), .value("0"))), timeout: 2)
            }
        }

        private func keyboardViewportFailurePlan(
            preparationLabel: String,
            mode: String
        ) throws -> HeistPlan {
            try HeistPlan {
                Activate(.label(preparationLabel))
                    .expect(.exists(.element(.label("Viewport replacement mode"), .value(mode))), timeout: 2)
                TypeText(.replacing("must not commit"), into: .element(
                    .label("Viewport note"),
                    .traits([.textEntry]),
                    .customContent(.init(label: "Semantic role", value: "body"))
                ))
            }
        }

        private func staleLiveObjectBodyPlan() throws -> HeistPlan {
            switch self {
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
            default:
                preconditionFailure("Scenario is not a stale live-object case")
            }
        }

        private func modalObstructionBodyPlan() throws -> HeistPlan {
            switch self {
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
            default:
                preconditionFailure("Scenario is not a modal-obstruction case")
            }
        }

        private func nestedScrollBodyPlan() throws -> HeistPlan {
            switch self {
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
            default:
                preconditionFailure("Scenario is not a nested-scroll case")
            }
        }
    }
}
