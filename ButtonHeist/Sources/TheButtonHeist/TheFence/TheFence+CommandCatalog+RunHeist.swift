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
                cliExposure: .notExposed,
                parameters: [
                    param(.step, .string, required: true, minLength: 1),
                ],
                description: "Perform exactly one primitive ButtonHeist step from `step` source. " +
                    "The fence wraps it as `HeistPlan { <step> }`, compiles it through ThePlans, " +
                    "requires one action or simple WaitFor step, then executes it through the heist runtime. " +
                    "Use run_heist for branching, loops, named heists, warnings, failures, or multiple steps."
            )
        case .runHeist:
            return TheFence.Command.commandDescriptor(
                command, family: .heistRuntime,
                requestDecoder: TheFence.decodeRunHeistCommandRequest,
                parameters: [Self.rootArgumentParameter] + Self.planSourceParameters,
                description: "Execute a typed heist plan, supplied as canonical ButtonHeist source via `plan`, " +
                    "or loaded by the fence from a `path` to a .heist package artifact. Provide exactly " +
                    "one source: path or plan. Use `argument` when the root heist declares a string or " +
                    "element_target parameter."
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
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "List a summary menu of the root entry and named reusable heists derived " +
                    "from one runtime-validated plan. Set `detail` to `detailed` to include derived command " +
                    "names, nested heist calls, counts, and safe semantic surface summaries. The plan can " +
                    "be supplied as canonical ButtonHeist source via `plan` or loaded from a `path` to " +
                    "a .heist package artifact."
            )
        case .describeHeist:
            return TheFence.Command.commandDescriptor(
                command, family: .heistRuntime,
                requestDecoder: TheFence.decodeDescribeHeistCommandRequest,
                requiresConnectionBeforeDispatch: false,
                parameters: [
                    param(.heist, .string, required: true),
                ] + Self.planSourceParameters,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "Describe one root entry or reusable heist from a runtime-validated plan. The " +
                    "`heist` parameter selects the entry/capability name; the plan can be supplied as " +
                    "canonical ButtonHeist source via `plan` or loaded from a `path` to a .heist package artifact."
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
