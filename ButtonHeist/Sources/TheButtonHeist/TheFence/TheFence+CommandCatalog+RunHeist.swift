import ThePlans

extension TheFence.Command {
    func makeHeistRuntimeDescriptor() -> FenceCommandDescriptor {
        switch self {
        case .perform:
            return makeDescriptor(
                family: .heistRuntime,
                parameters: [
                    FenceParameters.performStep.spec,
                ],
                timeout: .performStep,
                responseProjection: .heistExecution,
                projection: .mcpOnly(Self.performDescription)
            )
        case .runHeist:
            return makeDescriptor(
                family: .heistRuntime,
                parameters: [Self.rootArgumentParameter] + Self.planSourceParameters,
                timeout: .fixed(.longAction),
                responseProjection: .heistExecution,
                projection: .cliAndMCP(Self.runHeistDescription)
            )
        case .listHeists:
            return makeDescriptor(
                family: .heistRuntime,
                requiresConnectionBeforeDispatch: false,
                parameters: [
                    FenceParameters.heistCatalogDetail.spec,
                ] + Self.planSourceParameters,
                responseProjection: .heistCatalog,
                projection: .cliAndMCP(
                    "List the root entry and reusable heists in a plan. Use `detail: \"detailed\"` " +
                        "when composing against available capabilities.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            )
        case .describeHeist:
            return makeDescriptor(
                family: .heistRuntime,
                requiresConnectionBeforeDispatch: false,
                parameters: [
                    FenceParameters.heistName.spec,
                ] + Self.planSourceParameters,
                responseProjection: .heistDescription,
                projection: .cliAndMCP(
                    "Describe one root entry or reusable heist from a plan so an agent can call it safely.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            )
        case .ping, .listDevices, .getInterface, .getScreen, .getPasteboard, .getAnnouncements,
             .getSessionState, .connect, .listTargets, .wait, .oneFingerTap, .longPress, .swipe, .drag,
             .scroll, .scrollToVisible, .scrollToEdge, .activate, .rotor, .typeText, .editAction,
             .setPasteboard, .dismissKeyboard:
            preconditionFailure("\(rawValue) is not a heist runtime command")
        }
    }

    private static var planSourceParameters: [FenceParameterSpec] {
        [
            FenceParameters.planPath.spec,
            FenceParameters.inlinePlan.spec,
        ]
    }

    private static let performDescription = """
        Run one durable ButtonHeist DSL instruction from `step`: one action or one `WaitFor(...)` statement.

        Examples:
        `Activate(.label("Pay")).expect(.changed(.screen()))`
        `TypeText("milk", into: .label("Search")).expect(.changed(.elements()))`
        `Increment(.label("Quantity"))`
        `Decrement(.label("Quantity"))`
        `CustomAction("Archive", on: .label("Message"))`
        `Rotor("Headings", on: .label("Article"))`
        `ScreenActions.Dismiss()`
        `ScreenActions.MagicTap()`
        `SetPasteboard("hello")`
        `Edit(.paste)`
        `DismissKeyboard()`
        `Mechanical.Tap(.label("Map"))`
        `Mechanical.Tap(ScreenPoint(x: 888, y: 372))`
        `Mechanical.Tap(.label("Map"), at: UnitPoint(x: 0.5, y: 0.25))`
        `Mechanical.LongPress(.label("Message"), at: UnitPoint(x: 0.5, y: 0.5))`
        `Mechanical.Swipe(.label("Carousel"), .left)`
        `Mechanical.Drag(.label("Slider"), to: ScreenPoint(x: 200, y: 40))`
        `WaitFor(.label("Checkout"), timeout: .seconds(5))`

        Use `perform` when one line is enough. Use `run_heist` when the job needs
        multiple instructions, reusable heists, `RunHeist`, `If`,
        `WaitFor(...).else { ... }`, `ForEach`, `Warn`, or `Fail`.
        """

    private static let runHeistDescription = """
        Run a durable heist from a ButtonHeist source plan in `plan`, or from a generated `.heist` package at `path`.

        Author plans as ButtonHeist source, not raw JSON IR:
        `HeistPlan("shop") { ... }`
        `HeistDef<String>("Cart.addItem", parameter: "item") { item in ... }`
        `RunHeist("Cart.addItem", "Milk").expect(.changed(.elements([.appeared(.element(.label("subtotal"), .value(.contains("1 item"))))])))`
        `If(.label("Pay")) { ... }.else { ... }`
        `WaitFor(.changed(.screen()), timeout: .seconds(10)).else { ... }`
        `ForEach("Milk", "Bread") { item in ... }`
        `ForEach(.element(.label(.prefix("Delete")), .traits([.button])), limit: 20) { target in ... }`
        `Warn("message")`
        `Fail("message")`

        Provide exactly one source: `path` or `plan`. Use `argument` when the root
        heist takes a string or accessibility target. Runtime source is restricted
        ButtonHeist DSL, not arbitrary Swift.
        """

    private static var rootArgumentParameter: FenceParameterSpec {
        objectParam(
            .argument,
            properties: [
                param(
                    .type,
                    .string,
                    required: true,
                    enumValues: [
                        HeistParameterKind.none.rawValue,
                        HeistParameterKind.string.rawValue,
                        HeistParameterKind.accessibilityTarget.rawValue,
                    ]
                ),
                param(.value, .string),
                param(.valueRef, .string),
                objectParam(
                    .target,
                    properties: FenceParameterBlocks.inlineAccessibilityTargetFields
                ),
            ],
            additionalProperties: false
        )
    }
}
