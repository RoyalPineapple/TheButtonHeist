import TheScore
import ThePlans

@_spi(ButtonHeistTooling) public struct FenceParameter<Value: Sendable>: Sendable {
    public let key: FenceParameterKey
    public let defaultValue: Value?
    public let allowedRawValues: [String]?

    let spec: FenceParameterSpec
    let expectedTypeDescription: String
    private let decodeValue: @Sendable (HeistValue, String) throws -> Value
    private let encodeValue: @Sendable (Value) -> HeistValue

    init(
        key: FenceParameterKey,
        spec: FenceParameterSpec,
        expectedTypeDescription: String,
        defaultValue: Value? = nil,
        allowedRawValues: [String]? = nil,
        decodeValue: @escaping @Sendable (HeistValue, String) throws -> Value,
        encodeValue: @escaping @Sendable (Value) -> HeistValue
    ) {
        self.key = key
        self.spec = spec
        self.expectedTypeDescription = expectedTypeDescription
        self.defaultValue = defaultValue
        self.allowedRawValues = allowedRawValues
        self.decodeValue = decodeValue
        self.encodeValue = encodeValue
    }

    public func heistValue(for value: Value) -> HeistValue {
        encodeValue(value)
    }

    func decode(_ value: HeistValue, field: String) throws -> Value {
        try decodeValue(value, field)
    }
}

@_spi(ButtonHeistTooling) public struct FenceParameterSpec: Sendable, Equatable {

    public enum ParamType: String, Sendable, Equatable {
        case string
        case integer
        case number
        case boolean
        case stringArray
        case stringMatch
        case object
        case array
    }

    public let key: String
    let schema: FenceParameterSchema
    public let required: Bool

    init(
        key: String,
        schema: FenceParameterSchema,
        required: Bool
    ) {
        self.key = key
        self.schema = schema
        self.required = required
    }

    public var type: ParamType {
        schema.type
    }

    public var enumValues: [String]? {
        guard case .scalar(let scalar) = schema else { return nil }
        return scalar.constraints.enumValues
    }

    public var defaultValue: HeistValue? {
        guard case .scalar(let scalar) = schema else { return nil }
        return scalar.constraints.defaultValue
    }

    var minimum: Double? {
        guard case .scalar(let scalar) = schema else { return nil }
        return scalar.constraints.minimum
    }

    var maximum: Double? {
        guard case .scalar(let scalar) = schema else { return nil }
        return scalar.constraints.maximum
    }

    var exclusiveMinimum: Double? {
        guard case .scalar(let scalar) = schema else { return nil }
        return scalar.constraints.exclusiveMinimum
    }

    var minLength: Int? {
        guard case .scalar(let scalar) = schema else { return nil }
        return scalar.constraints.minLength
    }

    var minItems: Int? {
        guard case .array(let array) = schema else { return nil }
        return array.constraints.minItems
    }

    var maxItems: Int? {
        guard case .array(let array) = schema else { return nil }
        return array.constraints.maxItems
    }

    var jsonSchema: FenceParameterJSONSchema {
        schema.jsonSchema
    }

    public var objectProperties: [FenceParameterSpec] {
        guard case .object(let object) = schema,
              let properties = object.properties else {
            return []
        }
        return properties
    }

    var objectAdditionalProperties: Bool {
        guard case .object(let object) = schema else { return false }
        return object.additionalProperties ?? false
    }

    var arrayItemType: ParamType? {
        guard case .array(let array) = schema else { return nil }
        return array.items?.type
    }

    public var arrayItemProperties: [FenceParameterSpec] {
        guard case .array(let array) = schema,
              case .object(let object)? = array.items,
              let properties = object.properties else {
            return []
        }
        return properties
    }

    var arrayItemAdditionalProperties: Bool {
        guard case .array(let array) = schema,
              case .object(let object)? = array.items else {
            return false
        }
        return object.additionalProperties ?? false
    }

}

indirect enum FenceParameterSchema: Sendable, Equatable {
    case unconstrained
    case scalar(FenceParameterScalarSpec)
    case object(FenceParameterObjectSpec)
    case array(FenceParameterArraySpec)

    var type: FenceParameterSpec.ParamType {
        switch self {
        case .unconstrained:
            return .object
        case .scalar(let scalar):
            return scalar.kind.type
        case .object:
            return .object
        case .array(let array):
            return array.kind.type
        }
    }

    var jsonSchema: FenceParameterJSONSchema {
        switch self {
        case .unconstrained:
            return .unconstrained
        case .scalar(let scalar):
            return scalar.jsonSchema
        case .object(let object):
            return .object(
                properties: object.properties?.map(FenceParameterJSONSchemaProperty.init),
                additionalProperties: object.additionalProperties
            )
        case .array(let array):
            return .array(
                items: array.items?.jsonSchema,
                constraints: array.constraints.jsonSchemaConstraints
            )
        }
    }

    static func scalar(
        _ kind: FenceParameterScalarKind,
        constraints: FenceParameterScalarConstraints = .empty
    ) -> Self {
        .scalar(FenceParameterScalarSpec(kind: kind, constraints: constraints))
    }

    static func object(
        properties: [FenceParameterSpec]? = nil,
        additionalProperties: Bool? = nil
    ) -> Self {
        .object(FenceParameterObjectSpec(
            properties: properties,
            additionalProperties: additionalProperties
        ))
    }

    static func array(
        kind: FenceParameterArrayKind = .array,
        items: FenceParameterSchema? = nil,
        constraints: FenceParameterArrayConstraints = .empty
    ) -> Self {
        .array(FenceParameterArraySpec(kind: kind, items: items, constraints: constraints))
    }
}

enum FenceParameterScalarKind: Sendable, Equatable {
    case string
    case integer
    case number
    case boolean
    case stringMatch(modeValues: [String], description: String)

    var type: FenceParameterSpec.ParamType {
        switch self {
        case .string:
            return .string
        case .integer:
            return .integer
        case .number:
            return .number
        case .boolean:
            return .boolean
        case .stringMatch:
            return .stringMatch
        }
    }
}

struct FenceParameterScalarSpec: Sendable, Equatable {
    let kind: FenceParameterScalarKind
    let constraints: FenceParameterScalarConstraints

    var jsonSchema: FenceParameterJSONSchema {
        switch kind {
        case .string, .integer, .number, .boolean:
            return .scalar(kind.type, constraints: constraints.jsonSchemaConstraints)
        case .stringMatch(let modeValues, let description):
            return .stringMatch(modeValues: modeValues, description: description)
        }
    }
}

struct FenceParameterObjectSpec: Sendable, Equatable {
    let properties: [FenceParameterSpec]?
    let additionalProperties: Bool?
}

struct FenceParameterArraySpec: Sendable, Equatable {
    let kind: FenceParameterArrayKind
    let items: FenceParameterSchema?
    let constraints: FenceParameterArrayConstraints
}

enum FenceParameterArrayKind: Sendable, Equatable {
    case array
    case stringArray

    var type: FenceParameterSpec.ParamType {
        switch self {
        case .array:
            return .array
        case .stringArray:
            return .stringArray
        }
    }
}

struct FenceParameterScalarConstraints: Sendable, Equatable {
    static let empty = Self()

    let enumValues: [String]?
    let defaultValue: HeistValue?
    let minimum: Double?
    let maximum: Double?
    let exclusiveMinimum: Double?
    let minLength: Int?

    init(
        enumValues: [String]? = nil,
        defaultValue: HeistValue? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        exclusiveMinimum: Double? = nil,
        minLength: Int? = nil
    ) {
        self.enumValues = enumValues
        self.defaultValue = defaultValue
        self.minimum = minimum
        self.maximum = maximum
        self.exclusiveMinimum = exclusiveMinimum
        self.minLength = minLength
    }

    var jsonSchemaConstraints: FenceParameterJSONSchemaConstraints {
        FenceParameterJSONSchemaConstraints(
            enumValues: enumValues,
            defaultValue: defaultValue,
            minimum: minimum,
            maximum: maximum,
            exclusiveMinimum: exclusiveMinimum,
            minLength: minLength
        )
    }
}

struct FenceParameterArrayConstraints: Sendable, Equatable {
    static let empty = Self()

    let minItems: Int?
    let maxItems: Int?

    init(
        minItems: Int? = nil,
        maxItems: Int? = nil
    ) {
        self.minItems = minItems
        self.maxItems = maxItems
    }

    var jsonSchemaConstraints: FenceParameterJSONSchemaConstraints {
        FenceParameterJSONSchemaConstraints(
            minItems: minItems,
            maxItems: maxItems
        )
    }
}

indirect enum FenceParameterJSONSchema: Sendable, Equatable {
    case unconstrained
    case scalar(FenceParameterJSONScalarSchema)
    case object(FenceParameterJSONObjectSchema)
    case array(FenceParameterJSONArraySchema)

    var heistValue: HeistValue {
        .object(heistValueProperties)
    }

    private var heistValueProperties: [String: HeistValue] {
        switch self {
        case .unconstrained:
            return [:]
        case .scalar(let schema):
            return schema.heistValueProperties
        case .object(let schema):
            return schema.heistValueProperties
        case .array(let schema):
            return schema.heistValueProperties
        }
    }

    static func scalar(
        _ type: FenceParameterSpec.ParamType,
        constraints: FenceParameterJSONSchemaConstraints = .empty
    ) -> Self {
        .scalar(FenceParameterJSONScalarSchema(type: type, constraints: constraints))
    }

    static func object(
        properties: [FenceParameterJSONSchemaProperty]? = nil,
        additionalProperties: Bool? = nil,
        constraints: FenceParameterJSONSchemaConstraints = .empty
    ) -> Self {
        .object(FenceParameterJSONObjectSchema(
            properties: properties,
            additionalProperties: additionalProperties,
            constraints: constraints
        ))
    }

    static func array(
        items: FenceParameterJSONSchema? = nil,
        constraints: FenceParameterJSONSchemaConstraints = .empty
    ) -> Self {
        .array(FenceParameterJSONArraySchema(items: items, constraints: constraints))
    }

    static func stringMatch(
        modeValues: [String],
        description: String
    ) -> Self {
        .object(
            properties: [
                FenceParameterJSONSchemaProperty(
                    key: .mode,
                    schema: .scalar(.string, constraints: FenceParameterJSONSchemaConstraints(enumValues: modeValues)),
                    required: true
                ),
                FenceParameterJSONSchemaProperty(
                    key: .value,
                    schema: .scalar(.string),
                    required: false
                ),
            ],
            additionalProperties: false,
            constraints: FenceParameterJSONSchemaConstraints(description: description)
        )
    }
}

struct FenceParameterJSONScalarSchema: Sendable, Equatable {
    let type: FenceParameterSpec.ParamType
    let constraints: FenceParameterJSONSchemaConstraints

    var heistValueProperties: [String: HeistValue] {
        var properties = ["type": HeistValue.string(type.jsonSchemaType)]
        constraints.add(to: &properties)
        return properties
    }
}

struct FenceParameterJSONObjectSchema: Sendable, Equatable {
    let properties: [FenceParameterJSONSchemaProperty]?
    let additionalProperties: Bool?
    let constraints: FenceParameterJSONSchemaConstraints

    var heistValueProperties: [String: HeistValue] {
        var fields = ["type": HeistValue.string(FenceParameterSpec.ParamType.object.jsonSchemaType)]
        constraints.add(to: &fields)
        if let properties {
            fields["properties"] = .object(Self.heistValueProperties(from: properties))
            let required = properties.filter(\.required).map(\.key)
            if !required.isEmpty {
                fields["required"] = .array(required.map { .string($0) })
            }
        }
        if let additionalProperties {
            fields["additionalProperties"] = .bool(additionalProperties)
        }
        return fields
    }

    private static func heistValueProperties(
        from properties: [FenceParameterJSONSchemaProperty]
    ) -> [String: HeistValue] {
        var projectedProperties: [String: HeistValue] = [:]
        for property in properties where projectedProperties[property.key] == nil {
            projectedProperties[property.key] = property.schema.heistValue
        }
        return projectedProperties
    }
}

struct FenceParameterJSONArraySchema: Sendable, Equatable {
    let items: FenceParameterJSONSchema?
    let constraints: FenceParameterJSONSchemaConstraints

    var heistValueProperties: [String: HeistValue] {
        var fields = ["type": HeistValue.string(FenceParameterSpec.ParamType.array.jsonSchemaType)]
        constraints.add(to: &fields)
        if let items {
            fields["items"] = items.heistValue
        }
        return fields
    }
}

struct FenceParameterJSONSchemaProperty: Sendable, Equatable {
    let key: String
    let schema: FenceParameterJSONSchema
    let required: Bool

    init(
        key: FenceParameterKey,
        schema: FenceParameterJSONSchema,
        required: Bool = false
    ) {
        self.key = key.rawValue
        self.schema = schema
        self.required = required
    }

    init(_ spec: FenceParameterSpec) {
        key = spec.key
        schema = spec.jsonSchema
        required = spec.required
    }
}

struct FenceParameterJSONSchemaConstraints: Sendable, Equatable {
    static let empty = Self()

    let enumValues: [String]?
    let defaultValue: HeistValue?
    let minimum: Double?
    let maximum: Double?
    let exclusiveMinimum: Double?
    let minLength: Int?
    let minItems: Int?
    let maxItems: Int?
    let description: String?

    init(
        enumValues: [String]? = nil,
        defaultValue: HeistValue? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        exclusiveMinimum: Double? = nil,
        minLength: Int? = nil,
        minItems: Int? = nil,
        maxItems: Int? = nil,
        description: String? = nil
    ) {
        self.enumValues = enumValues
        self.defaultValue = defaultValue
        self.minimum = minimum
        self.maximum = maximum
        self.exclusiveMinimum = exclusiveMinimum
        self.minLength = minLength
        self.minItems = minItems
        self.maxItems = maxItems
        self.description = description
    }

    func add(to properties: inout [String: HeistValue]) {
        if let enumValues { properties["enum"] = .array(enumValues.map { .string($0) }) }
        if let defaultValue { properties["default"] = defaultValue }
        if let minimum { properties["minimum"] = jsonSchemaNumber(minimum) }
        if let maximum { properties["maximum"] = jsonSchemaNumber(maximum) }
        if let exclusiveMinimum { properties["exclusiveMinimum"] = jsonSchemaNumber(exclusiveMinimum) }
        if let minLength { properties["minLength"] = .int(minLength) }
        if let minItems { properties["minItems"] = .int(minItems) }
        if let maxItems { properties["maxItems"] = .int(maxItems) }
        if let description { properties["description"] = .string(description) }
    }
}

extension TheFence {

    enum DecodeLimits {
        static let maxRunHeistSteps = 100
        static let maxRunHeistRequestBytes = PublicJSONInputLimits.maxRequestBytes
        static let maxRunHeistNestingDepth = PublicJSONInputLimits.maxNestingDepth
        static let maxRunHeistObjectKeys = PublicJSONInputLimits.maxTotalObjectKeys
        static let maxHeistResultRows = maxRunHeistSteps
        static let maxInlineScreenshotBase64Bytes = 1_000_000
    }
}

@_spi(ButtonHeistTooling) public struct FenceParameterKey: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }

    private init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

@_spi(ButtonHeistTooling) public extension FenceParameterKey {
    static let absent = Self("absent"), action = Self("action"), actions = Self("actions"), angle = Self("angle"), app = Self("app")
    static let argument = Self("argument")
    static let after = Self("after")
    static let before = Self("before")
    static let check = Self("check"), checks = Self("checks")
    static let command = Self("command")
    static let container = Self("container")
    static let continuation = Self("continuation")
    static let detail = Self("detail"), device = Self("device"), direction = Self("direction"), duration = Self("duration")
    static let edge = Self("edge"), element = Self("element"), elements = Self("elements"), end = Self("end")
    static let endOffset = Self("endOffset")
    static let elementDirection = Self("elementDirection"), elementToPoint = Self("elementToPoint")
    static let elementUnitPoints = Self("elementUnitPoints")
    static let expect = Self("expect"), from = Self("from"), heistId = Self("heistId")
    static let heist = Self("heist"), hint = Self("hint"), identifier = Self("identifier")
    static let inlineData = Self("inlineData"), path = Self("path"), isImportant = Self("isImportant"), isModalBoundary = Self("isModalBoundary")
    static let kind = Self("kind"), label = Self("label"), match = Self("match"), matcher = Self("matcher")
    static let maxScrollsPerContainer = Self("maxScrollsPerContainer")
    static let maxScrollsPerDiscovery = Self("maxScrollsPerDiscovery")
    static let mode = Self("mode")
    static let newValue = Self("newValue"), oldValue = Self("oldValue"), ordinal = Self("ordinal"), output = Self("output")
    static let point = Self("point"), pointDirection = Self("pointDirection"), pointToPoint = Self("pointToPoint")
    static let plan = Self("plan"), policy = Self("policy"), predicate = Self("predicate"), property = Self("property")
    static let radius = Self("radius")
    static let replacingExisting = Self("replacingExisting")
    static let requestId = Self("requestId")
    static let rotor = Self("rotor"), rotorIndex = Self("rotorIndex"), rotors = Self("rotors")
    static let scale = Self("scale"), spread = Self("spread"), start = Self("start")
    static let startOffset = Self("startOffset")
    static let step = Self("step")
    static let containerName = Self("containerName"), custom = Self("custom"), customContent = Self("customContent")
    static let unitPoint = Self("unitPoint")
    static let states = Self("states"), scopes = Self("scopes"), assertions = Self("assertions"), body = Self("body")
    static let name = Self("name"), parameter = Self("parameter"), definitions = Self("definitions")
    static let subtree = Self("subtree"), target = Self("target"), text = Self("text"), textRange = Self("textRange")
    static let timeout = Self("timeout"), version = Self("version")
    static let to = Self("to"), token = Self("token"), traits = Self("traits"), type = Self("type"), value = Self("value")
    static let valueRef = Self("value_ref")
    static let targetRef = Self("target_ref")
    static let values = Self("values")
    static let `where` = Self("where")
    static let x = Self("x"), y = Self("y")
}

extension FenceParameter where Value == String {
    static func string(
        _ key: FenceParameterKey,
        required: Bool = false,
        defaultValue: String? = nil,
        minLength: Int? = nil
    ) -> Self {
        FenceParameter(
            key: key,
            spec: param(
                key,
                .string,
                required: required,
                defaultValue: defaultValue.map(HeistValue.string),
                minLength: minLength
            ),
            expectedTypeDescription: "string",
            defaultValue: defaultValue,
            decodeValue: { value, field in try decodeString(value, field: field) },
            encodeValue: { .string($0) }
        )
    }

    private static func decodeString(_ value: HeistValue, field: String) throws -> String {
        guard case .string(let string) = value else {
            throw SchemaValidationError(field: field, observed: value.schemaObservedDescription, expected: "string")
        }
        return string
    }
}

extension FenceParameter where Value == Int {
    static func integer(
        _ key: FenceParameterKey,
        required: Bool = false,
        defaultValue: Int? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil
    ) -> Self {
        FenceParameter(
            key: key,
            spec: param(
                key,
                .integer,
                required: required,
                defaultValue: defaultValue.map(HeistValue.int),
                minimum: minimum,
                maximum: maximum
            ),
            expectedTypeDescription: "integer",
            defaultValue: defaultValue,
            decodeValue: { value, field in try decodeInteger(value, field: field) },
            encodeValue: { .int($0) }
        )
    }

    private static func decodeInteger(_ value: HeistValue, field: String) throws -> Int {
        guard let integer = value.integerValue else {
            throw SchemaValidationError(field: field, observed: value.schemaObservedDescription, expected: "integer")
        }
        return integer
    }
}

extension FenceParameter where Value == Double {
    static func number(
        _ key: FenceParameterKey,
        required: Bool = false,
        defaultValue: Double? = nil,
        maximum: Double? = nil,
        exclusiveMinimum: Double? = nil
    ) -> Self {
        FenceParameter(
            key: key,
            spec: param(
                key,
                .number,
                required: required,
                defaultValue: defaultValue.map(jsonSchemaNumber),
                maximum: maximum,
                exclusiveMinimum: exclusiveMinimum
            ),
            expectedTypeDescription: "number",
            defaultValue: defaultValue,
            decodeValue: { value, field in try decodeNumber(value, field: field) },
            encodeValue: { jsonSchemaNumber($0) }
        )
    }

    private static func decodeNumber(_ value: HeistValue, field: String) throws -> Double {
        guard let number = value.numberValue else {
            throw SchemaValidationError(field: field, observed: value.schemaObservedDescription, expected: "number")
        }
        return number
    }
}

extension FenceParameter where Value == Bool {
    static func boolean(
        _ key: FenceParameterKey,
        required: Bool = false,
        defaultValue: Bool? = nil
    ) -> Self {
        FenceParameter(
            key: key,
            spec: param(
                key,
                .boolean,
                required: required,
                defaultValue: defaultValue.map(HeistValue.bool)
            ),
            expectedTypeDescription: "boolean",
            defaultValue: defaultValue,
            decodeValue: { value, field in try decodeBoolean(value, field: field) },
            encodeValue: { .bool($0) }
        )
    }

    private static func decodeBoolean(_ value: HeistValue, field: String) throws -> Bool {
        guard case .bool(let bool) = value else {
            throw SchemaValidationError(field: field, observed: value.schemaObservedDescription, expected: "boolean")
        }
        return bool
    }
}

extension FenceParameter where Value: CaseIterable & RawRepresentable, Value.RawValue == String {
    static func enumValue(
        _ key: FenceParameterKey,
        required: Bool = false,
        defaultValue: Value? = nil
    ) -> Self {
        let rawValues = Value.allCases.map(\.rawValue)
        return FenceParameter(
            key: key,
            spec: param(
                key,
                .string,
                required: required,
                enumValues: rawValues,
                defaultValue: defaultValue.map { .string($0.rawValue) }
            ),
            expectedTypeDescription: SchemaValidationError.expectedEnumValues(rawValues),
            defaultValue: defaultValue,
            allowedRawValues: rawValues,
            decodeValue: { value, field in
                guard case .string(let rawValue) = value else {
                    throw SchemaValidationError(field: field, observed: value.schemaObservedDescription, expected: "string")
                }
                guard let enumValue = Value(rawValue: rawValue) else {
                    throw SchemaValidationError(
                        field: field,
                        observed: "string \"\(rawValue)\"",
                        expected: SchemaValidationError.expectedEnumValues(rawValues)
                    )
                }
                return enumValue
            },
            encodeValue: { .string($0.rawValue) }
        )
    }
}

func fenceEnumValues<E>(_ type: E.Type) -> [String] where E: CaseIterable & RawRepresentable, E.RawValue == String {
    type.allCases.map(\.rawValue)
}

@_spi(ButtonHeistTooling) public enum FenceParameters {
    public static let actionName = FenceParameter<String>.string(.action)
    public static let commandName = FenceParameter<String>.string(.command, required: true)
    public static let connectionTarget = FenceParameter<String>.string(.target)
    public static let device = FenceParameter<String>.string(.device)
    public static let editAction = FenceParameter<EditAction>.enumValue(.action, required: true)
    public static let elementProperty = FenceParameter<ElementProperty>.enumValue(.property)
    public static let heistCatalogDetail = FenceParameter<HeistCatalogDetail>.enumValue(
        .detail,
        defaultValue: .summary
    )
    public static let heistName = FenceParameter<String>.string(.heist, required: true)
    public static let inlineData = FenceParameter<Bool>.boolean(.inlineData)
    public static let inlinePlan = FenceParameter<String>.string(.plan)
    public static let interfaceDetail = FenceParameter<InterfaceDetail>.enumValue(.detail)
    public static let maxScrollsPerContainer = FenceParameter<Int>.integer(
        .maxScrollsPerContainer,
        minimum: 1,
        maximum: 2_000
    )
    public static let maxScrollsPerDiscovery = FenceParameter<Int>.integer(
        .maxScrollsPerDiscovery,
        minimum: 1,
        maximum: 2_000
    )
    public static let output = FenceParameter<String>.string(.output)
    public static let pasteboardText = FenceParameter<String>.string(.text, required: true, minLength: 1)
    public static let performStep = FenceParameter<String>.string(.step, required: true, minLength: 1)
    public static let planPath = FenceParameter<String>.string(.path)
    public static let replacingExisting = FenceParameter<Bool>.boolean(.replacingExisting, defaultValue: false)
    public static let rotorDirection = FenceParameter<RotorDirection>.enumValue(.direction, defaultValue: .next)
    public static let rotorIndex = FenceParameter<Int>.integer(.rotorIndex, minimum: 0)
    public static let rotorName = FenceParameter<String>.string(.rotor)
    public static let scrollDirection = FenceParameter<ScrollDirection>.enumValue(.direction, defaultValue: .down)
    public static let scrollEdge = FenceParameter<ScrollEdge>.enumValue(.edge, defaultValue: .top)
    public static let swipeDirection = FenceParameter<SwipeDirection>.enumValue(.direction, required: true)
    public static let text = FenceParameter<String>.string(.text, required: true)
    public static let timeout = FenceParameter<Double>.number(
        .timeout,
        maximum: defaultWaitTimeout,
        exclusiveMinimum: 0
    )
    public static let token = FenceParameter<String>.string(.token)
    public static let containerType = FenceParameter<ContainerTypeName>.enumValue(.type)
}

func param(
    _ key: FenceParameterKey,
    _ kind: FenceParameterScalarKind,
    required: Bool = false,
    enumValues: [String]? = nil,
    defaultValue: HeistValue? = nil,
    minimum: Double? = nil,
    maximum: Double? = nil,
    exclusiveMinimum: Double? = nil,
    minLength: Int? = nil
) -> FenceParameterSpec {
    let constraints = FenceParameterScalarConstraints(
        enumValues: enumValues,
        defaultValue: defaultValue,
        minimum: minimum,
        maximum: maximum,
        exclusiveMinimum: exclusiveMinimum,
        minLength: minLength
    )
    return FenceParameterSpec(
        key: key.rawValue,
        schema: .scalar(kind, constraints: constraints),
        required: required
    )
}

func objectParam(
    _ key: FenceParameterKey,
    required: Bool = false
) -> FenceParameterSpec {
    FenceParameterSpec(
        key: key.rawValue,
        schema: .object(),
        required: required
    )
}

func objectParam(
    _ key: FenceParameterKey,
    required: Bool = false,
    properties: [FenceParameterSpec],
    additionalProperties: Bool = false
) -> FenceParameterSpec {
    FenceParameterSpec(
        key: key.rawValue,
        schema: .object(properties: properties, additionalProperties: additionalProperties),
        required: required
    )
}

func arrayParam(
    _ key: FenceParameterKey,
    required: Bool = false,
    items: FenceParameterSchema? = nil,
    minItems: Int? = nil,
    maxItems: Int? = nil
) -> FenceParameterSpec {
    FenceParameterSpec(
        key: key.rawValue,
        schema: .array(
            items: items,
            constraints: FenceParameterArrayConstraints(minItems: minItems, maxItems: maxItems)
        ),
        required: required
    )
}

func stringArrayParam(
    _ key: FenceParameterKey,
    required: Bool = false,
    minItems: Int? = nil,
    maxItems: Int? = nil
) -> FenceParameterSpec {
    FenceParameterSpec(
        key: key.rawValue,
        schema: .array(
            kind: .stringArray,
            items: .scalar(.string),
            constraints: FenceParameterArrayConstraints(minItems: minItems, maxItems: maxItems)
        ),
        required: required
    )
}

private func jsonSchemaNumber(_ value: Double) -> HeistValue {
    value.rounded(.towardZero) == value ? .int(Int(value)) : .double(value)
}

@_spi(ButtonHeistTooling) public enum MCPExposure: Sendable, Equatable {
    case directTool
    case notExposed
}

@_spi(ButtonHeistTooling) public struct MCPToolAnnotationSpec: Sendable, Equatable {
    public let readOnlyHint: Bool?
    public let idempotentHint: Bool?

    public init(
        readOnlyHint: Bool? = nil,
        idempotentHint: Bool? = nil
    ) {
        self.readOnlyHint = readOnlyHint
        self.idempotentHint = idempotentHint
    }
}

@_spi(ButtonHeistTooling) public extension FenceParameterSpec.ParamType {
    var jsonSchemaType: String {
        switch self {
        case .stringArray:
            return "array"
        case .stringMatch:
            return "object"
        default:
            return rawValue
        }
    }
}

@_spi(ButtonHeistTooling) public extension FenceCommandDescriptor {
    var inputJSONSchema: HeistValue {
        FenceParameterSpec.jsonInputSchema(
            parameters: parameters
        )
    }
}

@_spi(ButtonHeistTooling) public extension FenceParameterSpec {
    func parameters(named key: FenceParameterKey) -> [FenceParameterSpec] {
        let childMatches = objectProperties.flatMap { $0.parameters(named: key) }
            + arrayItemProperties.flatMap { $0.parameters(named: key) }
        guard self.key == key.rawValue else { return childMatches }
        return [self] + childMatches
    }

    var objectPropertyKeys: Set<String> {
        Set(objectProperties.map(\.key))
    }

    static func jsonSchemaProperties(from specs: [FenceParameterSpec]) -> [String: HeistValue] {
        var properties: [String: HeistValue] = [:]
        for spec in specs where properties[spec.key] == nil {
            properties[spec.key] = spec.jsonSchema.heistValue
        }
        return properties
    }

    static func jsonInputSchema(
        parameters: [FenceParameterSpec]
    ) -> HeistValue {
        FenceParameterJSONSchema.object(
            properties: parameters.map(FenceParameterJSONSchemaProperty.init),
            additionalProperties: false
        ).heistValue
    }
}

@_spi(ButtonHeistTooling) public enum CLIExposure: Sendable, Equatable {
    case directCommand
    case notExposed
}

enum FenceParameterBlocks: Sendable {
    private static let matcherFields = ElementTarget.predicateSchemaFields.map(elementTargetFieldSpec)
    static let inlineElementTargetFields = ElementTarget.inlineSchemaFields.map(elementTargetFieldSpec)

    static let elementTarget: [FenceParameterSpec] = [
        objectParam(.target, properties: inlineElementTargetFields),
    ]
    static let gestureElement = objectParam(.element, properties: inlineElementTargetFields)
    static let gestureUnitPoint = objectParam(.unitPoint, properties: unitPoint)
    static let gesturePoint = objectParam(.point, properties: screenPoint)

    static let gesturePointSelection: [FenceParameterSpec] = [
        gestureElement,
        gestureUnitPoint,
        gesturePoint,
    ]

    static let swipeElementDirection = objectParam(
        .elementDirection,
        properties: [
            gestureElement,
            FenceParameters.swipeDirection.spec,
        ]
    )

    static let swipeElementUnitPoints = objectParam(
        .elementUnitPoints,
        properties: [
            gestureElement,
            objectParam(.start, required: true, properties: unitPoint),
            objectParam(.end, required: true, properties: unitPoint),
        ]
    )

    static let swipePointToPoint = objectParam(
        .pointToPoint,
        properties: [
            objectParam(.start, required: true, properties: screenPoint),
            objectParam(.end, required: true, properties: screenPoint),
        ]
    )

    static let swipePointDirection = objectParam(
        .pointDirection,
        properties: [
            objectParam(.start, required: true, properties: screenPoint),
            FenceParameters.swipeDirection.spec,
        ]
    )

    static let swipeIntents = [
        swipeElementDirection,
        swipeElementUnitPoints,
        swipePointToPoint,
        swipePointDirection,
    ]

    static let dragElementToPoint = objectParam(
        .elementToPoint,
        properties: [
            gestureElement,
            objectParam(.start, properties: unitPoint),
            objectParam(.end, required: true, properties: screenPoint),
        ]
    )

    static let dragPointToPoint = objectParam(
        .pointToPoint,
        properties: [
            objectParam(.start, required: true, properties: screenPoint),
            objectParam(.end, required: true, properties: screenPoint),
        ]
    )

    static let dragIntents = [
        dragElementToPoint,
        dragPointToPoint,
    ]

    static let elementFilter = matcherFields

    private static let subtreeElementProperties = matcherFields

    private static let subtreeContainerProperties: [FenceParameterSpec] = [
        param(.containerName, .string),
        FenceParameters.containerType.spec,
        param(.label, .string), param(.value, .string), param(.identifier, .string),
        param(.isModalBoundary, .boolean),
    ]

    // `subtree.container` is a plain object matcher in the public schema — MCP
    // (OpenAI) tool input schemas reject JSON Schema combinators, so this must
    // never emit `oneOf`/`anyOf`/`allOf`. Pass the container name as
    // `{ "container": { "containerName": "main_scroll" } }`.
    private static let subtreeContainer = objectParam(
        .container,
        properties: subtreeContainerProperties
    )

    static let interfaceSubtree: FenceParameterSpec = objectParam(
        .subtree,
        properties: [
            objectParam(.element, properties: subtreeElementProperties),
            subtreeContainer,
            param(.ordinal, .integer, minimum: 0),
        ]
    )

    private static let predicateType = param(
        .type, .string, required: true,
        enumValues: AccessibilityPredicate.wireTypeValues
    )

    /// Documented fields of an `AccessibilityPredicate.State` object (`exists`,
    /// `missing`, `all`). A `State` is recursive — `all` nests further states —
    /// so item objects allow additional keys and the decoder enforces the
    /// per-type required-field rules.
    private static let stateProperties: [FenceParameterSpec] = [
        param(.type, .string, enumValues: ["exists", "missing", "all"]),
        objectParam(.element, properties: matcherFields),
        objectParam(.target, properties: inlineElementTargetFields),
        param(.targetRef, .string),
        arrayParam(.states, items: .object(properties: [], additionalProperties: true)),
    ]

    private static let assertionProperties: [FenceParameterSpec] = [
        param(.type, .string, enumValues: ["exists", "missing", "all", "appeared", "disappeared", "updated"]),
        objectParam(.element, properties: matcherFields),
        objectParam(.target, properties: inlineElementTargetFields),
        param(.targetRef, .string),
        FenceParameters.elementProperty.spec,
        objectParam(.before, properties: matcherFields),
        objectParam(.after, properties: matcherFields),
        arrayParam(.states, items: .object(properties: [], additionalProperties: true)),
    ]

    private static let changeScopeProperties: [FenceParameterSpec] = [
        param(.type, .string, enumValues: ["screen", "elements", "all"]),
        arrayParam(
            .assertions,
            items: .object(properties: assertionProperties, additionalProperties: true)
        ),
        arrayParam(
            .scopes,
            items: .object(properties: [], additionalProperties: true)
        ),
    ]

    /// Object properties for an `AccessibilityPredicate` (the `expect` slot and
    /// the `wait` `predicate` field). State predicates use `element`, `target`,
    /// `target_ref`, or `states`; change predicates use `scopes`, whose children
    /// carry `screen` state assertions or `elements` delta assertions.
    private static let accessibilityPredicateProperties: [FenceParameterSpec] = [
        predicateType,
        objectParam(.element, properties: matcherFields),
        objectParam(.target, properties: inlineElementTargetFields),
        param(.targetRef, .string),
        FenceParameters.elementProperty.spec,
        objectParam(.before, properties: matcherFields),
        objectParam(.after, properties: matcherFields),
        arrayParam(
            .states,
            items: .object(properties: stateProperties, additionalProperties: true)
        ),
        arrayParam(
            .scopes,
            items: .object(properties: changeScopeProperties, additionalProperties: true)
        ),
    ]

    static let expect: FenceParameterSpec = objectParam(
        .expect,
        properties: accessibilityPredicateProperties
    )

    static let predicate: FenceParameterSpec = objectParam(
        .predicate, required: true,
        properties: accessibilityPredicateProperties
    )

    static let expectationTimeout = FenceParameters.timeout.spec
    static let expectation: [FenceParameterSpec] = [expect, expectationTimeout]

    /// Parameters for the unified `wait` command: a predicate plus a timeout.
    static let wait: [FenceParameterSpec] = [predicate, expectationTimeout]

    static let unitPoint: [FenceParameterSpec] = [
        param(.x, .number, required: true), param(.y, .number, required: true),
    ]
    static let screenPoint: [FenceParameterSpec] = unitPoint
    static let gestureDuration = param(
        .duration, .number,
        maximum: GestureDuration.maximumSeconds,
        exclusiveMinimum: 0
    )

    private static func stringMatchParam(_ key: FenceParameterKey, allowsArray: Bool = false) -> FenceParameterSpec {
        let modeValues = StringMatch<String>.Mode.allCases.map(\.rawValue)
        let description = "StringMatch object with mode \(modeValues.joined(separator: "/")) and optional value. " +
            "Use mode exact for exact matching. Broad modes require a non-empty value; isEmpty must omit value." +
            (allowsArray
                ? " Element matcher fields also accept an array of StringMatch objects; every object must match."
                : "")
        return FenceParameterSpec(
            key: key.rawValue,
            schema: .scalar(.stringMatch(modeValues: modeValues, description: description)),
            required: false
        )
    }

    private static func elementTargetFieldSpec(_ field: ElementTarget.SchemaField) -> FenceParameterSpec {
        guard let key = FenceParameterKey(rawValue: field.name) else {
            preconditionFailure("ElementTarget field '\(field.name)' is not a Fence parameter key")
        }
        switch field.kind {
        case .predicateChecks:
            return predicateChecksParam(key)
        case .string:
            return param(key, .string)
        case .stringMatch:
            return stringMatchParam(key, allowsArray: true)
        case .stringArray:
            return stringArrayParam(key)
        case .stringMatchArray:
            return stringMatchArrayParam(key)
        case .actionArray:
            return actionArrayParam(key)
        case .customContentMatch:
            return customContentMatchParam(key)
        case .nonNegativeInteger:
            return param(key, .integer, minimum: 0)
        }
    }

    private static func predicateChecksParam(_ key: FenceParameterKey) -> FenceParameterSpec {
        arrayParam(
            key,
            items: .object(
                properties: [
                    param(
                        .kind, .string, required: true,
                        enumValues: ElementPredicateCheck<String>.Kind.allCases.map(\.rawValue)
                    ),
                    stringMatchParam(.match),
                    predicateCheckValuesParam(.values),
                    objectParam(.check),
                ],
                additionalProperties: false
            )
        )
    }

    private static func predicateCheckValuesParam(_ key: FenceParameterKey) -> FenceParameterSpec {
        arrayParam(key, items: .unconstrained)
    }

    private static func actionArrayParam(_ key: FenceParameterKey) -> FenceParameterSpec {
        arrayParam(key, items: .unconstrained)
    }

    private static func stringMatchArrayParam(_ key: FenceParameterKey) -> FenceParameterSpec {
        arrayParam(key, items: stringMatchParam(.values).schema)
    }

    private static func customContentMatchParam(_ key: FenceParameterKey) -> FenceParameterSpec {
        objectParam(
            key,
            properties: [
                stringMatchParam(.label),
                stringMatchParam(.value),
                param(.isImportant, .boolean),
            ]
        )
    }
}
