import ThePlans

enum HeistRuntimeCommand: String, CaseIterable, FenceCommand {
    case perform
    case runHeist = "run_heist"
    case listHeists = "list_heists"
    case describeHeist = "describe_heist"

    var descriptor: FenceCommandDescriptor {
        switch self {
        case .perform:
            return TheFence.Command.commandDescriptor(
                command, family: .heistRuntime,
                requestDecoder: TheFence.decodePerformCommandRequest,
                parameters: [
                    param(.step, .string, required: true, minLength: 1),
                ],
                projection: .mcpOnly(
                    """
                    Run one ButtonHeist DSL instruction from `step`: one action or one simple wait.

                    Examples:
                    `Activate(.label("Pay")).expect(.changed(.screen()))`
                    `TypeText("milk", into: .label("Search")).expect(.changed(.elements))`
                    `Increment(.label("Quantity"))`
                    `Decrement(.label("Quantity"))`
                    `CustomAction("Archive", on: .label("Message"))`
                    `Rotor("Headings", on: .label("Article"))`
                    `SetPasteboard("hello")`
                    `Edit(.paste)`
                    `DismissKeyboard()`
                    `Mechanical.Tap(.label("Map"))`
                    `Mechanical.LongPress(.label("Message"))`
                    `Mechanical.Swipe(.label("Carousel"), .left)`
                    `Mechanical.Drag(.label("Slider"), to: ScreenPoint(x: 200, y: 40))`
                    `WaitFor(.present(.label("Checkout")), timeout: .seconds(5))`

                    Use `perform` when one line is enough. Use `run_heist` when the job needs
                    multiple instructions, reusable heists, `RunHeist`, `If`/`Else`,
                    `WaitFor(...).else { ... }`, `ForEach`, `Warn`, or `Fail`.
                    """
                )
            )
        case .runHeist:
            return TheFence.Command.commandDescriptor(
                command, family: .heistRuntime,
                requestDecoder: TheFence.decodeRunHeistCommandRequest,
                parameters: [Self.rootArgumentParameter] + Self.planSourceParameters,
                projection: .cliAndMCP(
                    """
                    Run a full heist from ButtonHeist DSL source in `plan`, or from a generated `.heist` package at `path`.

                    Author plans as ButtonHeist source, not raw JSON IR:
                    `HeistPlan("shop") { ... }`
                    `HeistDef<String>("Cart.addItem", parameter: "item") { item in ... }`
                    `RunHeist("Cart.addItem", "Milk")`
                    `If(.present(.label("Pay"))) { ... } Else { ... }`
                    `WaitFor(.changed(.screen()), timeout: .seconds(10)).else { ... }`
                    `ForEach(["Milk", "Bread"]) { item in ... }`
                    `ForEach(.matching(.label("Delete")), limit: 20) { target in ... }`
                    `Warn("message")`
                    `Fail("message")`

                    Provide exactly one source: `path` or `plan`. Use `argument` when the root
                    heist takes a string or element target. Runtime source is restricted
                    ButtonHeist DSL, not arbitrary Swift.
                    """
                )
            )
        case .listHeists:
            return TheFence.Command.commandDescriptor(
                command, family: .heistRuntime,
                requestDecoder: TheFence.decodeListHeistsCommandRequest,
                requiresConnectionBeforeDispatch: false,
                parameters: [
                    param(
                        .detail,
                        .string,
                        enumValues: fenceEnumValues(HeistCatalogDetail.self),
                        defaultValue: .string(HeistCatalogDetail.summary.rawValue)
                    ),
                ] + Self.planSourceParameters,
                projection: .cliAndMCP(
                    "List the root entry and reusable heists in a plan. Use `detail: \"detailed\"` " +
                        "when composing against available capabilities.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            )
        case .describeHeist:
            return TheFence.Command.commandDescriptor(
                command, family: .heistRuntime,
                requestDecoder: TheFence.decodeDescribeHeistCommandRequest,
                requiresConnectionBeforeDispatch: false,
                parameters: [
                    param(.heist, .string, required: true),
                ] + Self.planSourceParameters,
                projection: .cliAndMCP(
                    "Describe one root entry or reusable heist from a plan so an agent can call it safely.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            )
        }
    }

    private static var planSourceParameters: [FenceParameterSpec] {
        [
            param(.path, .string),
            param(.plan, .string),
        ]
    }

    private static var rootArgumentParameter: FenceParameterSpec {
        param(
            .argument,
            .object,
            objectProperties: [
                param(
                    .type,
                    .string,
                    required: true,
                    enumValues: ["none", "string", "element_target"]
                ),
                param(.value, .string),
                param(.valueRef, .string),
                param(
                    .target,
                    .object,
                    objectAdditionalProperties: true
                ),
            ],
            objectAdditionalProperties: false
        )
    }
}
