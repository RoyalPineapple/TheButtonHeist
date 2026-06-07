import ThePlans

enum HeistRuntimeCommand: String, CaseIterable, FenceCommand {
    case runHeist = "run_heist"
    case listHeists = "list_heists"
    case describeHeist = "describe_heist"

    var descriptor: FenceCommandDescriptor {
        switch self {
        case .runHeist:
            return TheFence.Command.commandDescriptor(
                command, family: .heistRuntime,
                requestDecoder: TheFence.decodeRunHeistCommandRequest,
                parameters: [Self.rootArgumentParameter] + Self.runHeistPlanSourceParameters,
                description: "Execute a typed heist plan, supplied as canonical ButtonHeist source via `plan`, " +
                    "as structured HeistPlan fields (version, name, parameter, definitions, body), or " +
                    "loaded by the fence from a `path` to a .heist package artifact. Provide exactly one " +
                    "source: path, plan, or structured plan fields. Use `argument` when the root heist " +
                    "declares a string or element_target parameter."
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
                ] + Self.structuredPlanSourceParameters,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "List a summary menu of the root entry and named reusable heists derived " +
                    "from one runtime-validated plan. Set `detail` to `detailed` to include derived command " +
                    "names, nested heist calls, counts, and safe semantic surface summaries. The plan can " +
                    "be supplied as canonical ButtonHeist source via `plan`, as structured HeistPlan fields " +
                    "(version, name, parameter, definitions, body), or loaded from a `path` to a .heist " +
                    "package artifact."
            )
        case .describeHeist:
            return TheFence.Command.commandDescriptor(
                command, family: .heistRuntime,
                requestDecoder: TheFence.decodeDescribeHeistCommandRequest,
                requiresConnectionBeforeDispatch: false,
                parameters: [
                    param(.heist, .string, required: true),
                ] + Self.structuredPlanSourceParameters,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "Describe one root entry or reusable heist from a runtime-validated plan. The " +
                    "`heist` parameter selects the entry/capability name; the plan can be supplied as " +
                    "canonical ButtonHeist source via `plan`, as structured HeistPlan fields (version, name, " +
                    "parameter, definitions, body), or loaded from a `path` to a .heist package artifact."
            )
        }
    }

    private static var runHeistPlanSourceParameters: [FenceParameterSpec] {
        [
            param(.path, .string),
            param(.plan, .string),
        ] + Self.structuredPlanFields
    }

    private static var structuredPlanSourceParameters: [FenceParameterSpec] {
        [
            param(.path, .string),
            param(.plan, .string),
        ] + Self.structuredPlanFields
    }

    private static var structuredPlanFields: [FenceParameterSpec] {
        [
            param(.version, .integer),
            param(.name, .string),
            param(.parameter, .object),
            param(
                .definitions, .array,
                arrayItemType: .object,
                arrayItemAdditionalProperties: true
            ),
            param(
                .body, .array,
                minItems: 1,
                maxItems: TheFence.DecodeLimits.maxRunHeistSteps,
                arrayItemType: .object,
                arrayItemProperties: [
                    param(
                        .type,
                        .string,
                        required: true,
                        enumValues: [
                            "action",
                            "wait",
                            "conditional",
                            "wait_for_cases",
                            "for_each_element",
                            "for_each_string",
                            "heist",
                            "invoke",
                            "warn",
                            "fail",
                        ]
                    ),
                ],
                arrayItemAdditionalProperties: true
            ),
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
