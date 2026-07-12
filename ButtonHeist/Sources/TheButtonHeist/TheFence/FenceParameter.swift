import TheScore

@_spi(ButtonHeistTooling) public struct FenceParameter<Value: Sendable>: Sendable {
    public let key: FenceParameterKey
    public let defaultValue: Value?

    internal let spec: FenceParameterSpec
    private let convertValue: @Sendable (HeistValue) -> Value?
    private let encodeValue: @Sendable (Value) -> HeistValue

    internal init(
        key: FenceParameterKey,
        spec: FenceParameterSpec,
        defaultValue: Value? = nil,
        convertValue: @escaping @Sendable (HeistValue) -> Value?,
        encodeValue: @escaping @Sendable (Value) -> HeistValue
    ) {
        precondition(spec.key == key.rawValue, "FenceParameter key must match its schema")
        guard case .scalar = spec.schema else {
            preconditionFailure("FenceParameter requires a scalar schema")
        }
        precondition(
            defaultValue.map(encodeValue) == spec.defaultValue,
            "FenceParameter default must match its schema"
        )
        self.key = key
        self.spec = spec
        self.defaultValue = defaultValue
        self.convertValue = convertValue
        self.encodeValue = encodeValue
    }

    public var allowedRawValues: [String]? {
        spec.enumValues
    }

    internal var expectedTypeDescription: String {
        spec.expectedTypeDescription
    }

    public func heistValue(for value: Value) -> HeistValue {
        encodeValue(value)
    }

    internal func decode(_ value: HeistValue, field: String) throws -> Value {
        try spec.validateScalar(value, field: field)
        guard let decoded = convertValue(value) else {
            preconditionFailure("FenceParameter converter disagrees with schema for \(key.rawValue)")
        }
        return decoded
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
    static let columnCount = Self("columnCount")
    static let container = Self("container")
    static let continuation = Self("continuation")
    static let detail = Self("detail"), device = Self("device"), direction = Self("direction"), duration = Self("duration")
    static let edge = Self("edge"), element = Self("element"), elements = Self("elements"), end = Self("end")
    static let endOffset = Self("endOffset")
    static let elementDirection = Self("elementDirection"), elementToPoint = Self("elementToPoint")
    static let elementUnitPoints = Self("elementUnitPoints")
    static let expect = Self("expect"), from = Self("from"), heistId = Self("heistId")
    static let header = Self("header")
    static let heist = Self("heist"), hint = Self("hint"), id = Self("id"), identifier = Self("identifier")
    static let inlineData = Self("inlineData"), path = Self("path"), isImportant = Self("isImportant"), isModalBoundary = Self("isModalBoundary")
    static let kind = Self("kind"), label = Self("label"), match = Self("match"), matcher = Self("matcher")
    static let maxScrollsPerContainer = Self("maxScrollsPerContainer")
    static let maxScrollsPerDiscovery = Self("maxScrollsPerDiscovery")
    static let mode = Self("mode")
    static let newValue = Self("newValue"), oldValue = Self("oldValue"), ordinal = Self("ordinal"), output = Self("output")
    static let point = Self("point"), pointDirection = Self("pointDirection"), pointToPoint = Self("pointToPoint")
    static let plan = Self("plan"), policy = Self("policy"), predicate = Self("predicate"), property = Self("property")
    static let radius = Self("radius")
    static let ref = Self("ref")
    static let replacingExisting = Self("replacingExisting")
    static let requestId = Self("requestId")
    static let rotor = Self("rotor"), rotorIndex = Self("rotorIndex"), rotors = Self("rotors")
    static let rowCount = Self("rowCount")
    static let scale = Self("scale"), scope = Self("scope"), semantic = Self("semantic"), spread = Self("spread"), start = Self("start")
    static let startOffset = Self("startOffset")
    static let step = Self("step")
    static let containerName = Self("containerName"), custom = Self("custom"), customContent = Self("customContent")
    static let unitPoint = Self("unitPoint")
    static let assertions = Self("assertions"), body = Self("body")
    static let name = Self("name"), parameter = Self("parameter"), definitions = Self("definitions")
    static let subtree = Self("subtree"), target = Self("target"), text = Self("text"), textRange = Self("textRange")
    static let timeout = Self("timeout"), version = Self("version")
    static let to = Self("to"), token = Self("token"), traits = Self("traits"), type = Self("type"), value = Self("value")
    static let valueRef = Self("value_ref")
    static let values = Self("values")
    static let `where` = Self("where")
    static let x = Self("x"), y = Self("y")
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

@_spi(ButtonHeistTooling) public enum CLIExposure: Sendable, Equatable {
    case directCommand
    case notExposed
}
