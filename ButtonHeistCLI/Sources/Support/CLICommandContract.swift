import ArgumentParser
@_spi(ButtonHeistTooling) import ButtonHeist
import Foundation
import ThePlans

struct CLIRequestParameters: Equatable {
    private var values: [FenceParameterKey: HeistValue]

    init() {
        values = [:]
    }

    init(_ fields: [(FenceParameterKey, HeistValue)]) {
        values = Dictionary(fields, uniquingKeysWith: { _, newest in newest })
    }

    subscript(_ key: FenceParameterKey) -> HeistValue? {
        get { values[key] }
        set { values[key] = newValue }
    }

    var rawValues: [String: HeistValue] {
        Dictionary(
            values.map { ($0.key.rawValue, $0.value) },
            uniquingKeysWith: { _, newest in newest }
        )
    }

    mutating func set(_ key: FenceParameterKey, _ value: HeistValue) {
        values[key] = value
    }

    mutating func set(_ key: FenceParameterKey, _ value: CLIRequestObject) {
        set(key, value.heistValue)
    }

    mutating func set(_ key: FenceParameterKey, _ value: String) {
        set(key, .string(value))
    }

    mutating func set(_ key: FenceParameterKey, _ value: Int) {
        set(key, .int(value))
    }

    mutating func set(_ key: FenceParameterKey, _ value: Double) {
        set(key, .double(value))
    }

    mutating func set(_ key: FenceParameterKey, _ value: Bool) {
        set(key, .bool(value))
    }

    mutating func set(_ key: FenceParameterKey, _ value: [String]) {
        set(key, .array(value.map(HeistValue.string)))
    }

    func adding(_ fields: CommandArgumentWriter.Field?...) -> Self {
        adding(fields)
    }

    func adding(_ fields: [CommandArgumentWriter.Field]) -> Self {
        adding(fields.map(Optional.some))
    }

    func adding(_ fields: [CommandArgumentWriter.Field?]) -> Self {
        var copy = self
        for field in fields.compactMap({ $0 }) {
            copy.values[field.key] = field.value
        }
        return copy
    }
}

struct CLIRequestObject: Equatable {
    private var values: [FenceParameterKey: HeistValue]

    init() {
        values = [:]
    }

    init(_ fields: [(FenceParameterKey, HeistValue)]) {
        values = Dictionary(fields, uniquingKeysWith: { _, newest in newest })
    }

    subscript(_ key: FenceParameterKey) -> HeistValue? {
        get { values[key] }
        set { values[key] = newValue }
    }

    var heistValue: HeistValue {
        .object(rawValues)
    }

    var rawValues: [String: HeistValue] {
        Dictionary(
            values.map { ($0.key.rawValue, $0.value) },
            uniquingKeysWith: { _, newest in newest }
        )
    }

    mutating func set(_ key: FenceParameterKey, _ value: HeistValue) {
        values[key] = value
    }

    mutating func set(_ key: FenceParameterKey, _ value: String) {
        set(key, .string(value))
    }

    mutating func set(_ key: FenceParameterKey, _ value: Int) {
        set(key, .int(value))
    }

    mutating func set(_ key: FenceParameterKey, _ value: Double) {
        set(key, .double(value))
    }

    mutating func set(_ key: FenceParameterKey, _ value: [String]) {
        set(key, .array(value.map(HeistValue.string)))
    }

    mutating func appendOneOrMany(_ value: HeistValue, for key: FenceParameterKey) {
        switch values[key] {
        case nil:
            values[key] = value
        case .array(let existing)?:
            values[key] = .array(existing + [value])
        case let existing?:
            values[key] = .array([existing, value])
        }
    }
}

enum CommandArgumentWriter {
    struct Field: Equatable {
        let key: FenceParameterKey
        let value: HeistValue
    }

    static func parameters(_ fields: Field?...) -> CLIRequestParameters {
        parameters(fields)
    }

    static func parameters(_ fields: [Field]) -> CLIRequestParameters {
        parameters(fields.map(Optional.some))
    }

    static func parameters(_ fields: [Field?]) -> CLIRequestParameters {
        CLIRequestParameters(fields.compactMap { field in
            field.map { ($0.key, $0.value) }
        })
    }

    static func object(_ fields: Field?...) -> CLIRequestObject {
        object(fields)
    }

    static func object(_ fields: [Field]) -> CLIRequestObject {
        object(fields.map(Optional.some))
    }

    static func object(_ fields: [Field?]) -> CLIRequestObject {
        CLIRequestObject(fields.compactMap { field in
            field.map { ($0.key, $0.value) }
        })
    }

    static func value(_ key: FenceParameterKey, _ value: HeistValue) -> Field {
        Field(key: key, value: value)
    }

    static func value(_ key: FenceParameterKey, _ value: CLIRequestObject) -> Field {
        self.value(key, value.heistValue)
    }

    static func value(_ key: FenceParameterKey, _ value: String) -> Field {
        self.value(key, .string(value))
    }

    static func value(_ key: FenceParameterKey, _ value: Int) -> Field {
        self.value(key, .int(value))
    }

    static func value(_ key: FenceParameterKey, _ value: Double) -> Field {
        self.value(key, .double(value))
    }

    static func value(_ key: FenceParameterKey, _ value: Bool) -> Field {
        self.value(key, .bool(value))
    }

    static func value(_ key: FenceParameterKey, _ value: [String]) -> Field {
        self.value(key, .array(value.map(HeistValue.string)))
    }

    static func optional(_ key: FenceParameterKey, _ value: HeistValue?) -> Field? {
        value.map { self.value(key, $0) }
    }

    static func optional(_ key: FenceParameterKey, _ value: CLIRequestObject?) -> Field? {
        value.map { self.value(key, $0) }
    }

    static func optional(_ key: FenceParameterKey, _ value: String?) -> Field? {
        value.map { self.value(key, $0) }
    }

    static func optional(_ key: FenceParameterKey, _ value: Int?) -> Field? {
        value.map { self.value(key, $0) }
    }

    static func optional(_ key: FenceParameterKey, _ value: Double?) -> Field? {
        value.map { self.value(key, $0) }
    }

    static func optional(_ key: FenceParameterKey, _ value: Bool?) -> Field? {
        value.map { self.value(key, $0) }
    }

    static func optional(_ key: FenceParameterKey, _ value: [String]?) -> Field? {
        value.map { self.value(key, $0) }
    }
}

/// Marker for CLI commands backed by the Fence command catalog.
///
/// Command identity is intentionally not a protocol requirement: concrete CLI
/// command types should not own or override Fence command identity.
protocol CLICommandContract: ParsableCommand {}

protocol GestureCLICommandContract: CLICommandContract {}

struct CLICommandAdapter {
    let commandType: ParsableCommand.Type
    let fenceDescriptor: FenceCommandDescriptor?

    static func fence(_ commandType: CLICommandContract.Type, descriptor: FenceCommandDescriptor) -> Self {
        Self(
            commandType: commandType,
            fenceDescriptor: descriptor
        )
    }

    static func cliOnly(_ commandType: ParsableCommand.Type) -> Self {
        Self(commandType: commandType, fenceDescriptor: nil)
    }
}

enum CLICommandAdapterCatalog {
    // MARK: - Pure Adapter Wiring
    //
    // This table binds catalog-owned command identities to concrete
    // ArgumentParser adapter types. It must not carry product command
    // semantics: public names, defaults, parameters, and help all
    // project from FenceCommandDescriptor/FenceParameterSpec below.
    private static let commandTypesByFenceCommand: [TheFence.Command: CLICommandContract.Type] = [
        .ping: PingCommand.self,
        .listDevices: ListCommand.self,
        .getInterface: GetInterfaceCommand.self,
        .getScreen: ScreenshotCommand.self,
        .wait: WaitCommand.self,
        .oneFingerTap: TapSubcommand.self,
        .longPress: LongPressSubcommand.self,
        .swipe: SwipeSubcommand.self,
        .drag: DragSubcommand.self,
        .scroll: ScrollCommand.self,
        .scrollToVisible: ScrollToVisibleCommand.self,
        .scrollToEdge: ScrollToEdgeCommand.self,
        .activate: ActivateCommand.self,
        .rotor: RotorCommand.self,
        .typeText: TypeCommand.self,
        .editAction: EditActionCommand.self,
        .setPasteboard: SetPasteboardCommand.self,
        .getPasteboard: GetPasteboardCommand.self,
        .dismissKeyboard: DismissKeyboardCommand.self,
        .runHeist: RunHeistCommand.self,
        .listHeists: ListHeistsCommand.self,
        .describeHeist: DescribeHeistCommand.self,
        .getSessionState: GetSessionStateCommand.self,
        .connect: ConnectCommand.self,
        .listTargets: ListTargetsCommand.self,
    ]

    // MARK: - Catalog Projection

    private static let cliOnlyAdapters: [CLICommandAdapter] = [
        .cliOnly(JSONLinesCommand.self),
    ]

    static let adapters: [CLICommandAdapter] = {
        let directDescriptors = TheFence.Command.cliDirectCommandDescriptors
        let directCommands = Set(directDescriptors.map(\.command))
        precondition(
            Set(commandTypesByFenceCommand.keys) == directCommands,
            """
            CLI adapter command map must cover exactly the Fence descriptors marked directCommand. \
            Update CLICommandAdapterCatalog.commandTypesByFenceCommand when descriptor CLI exposure changes.
            """
        )

        let directAdapters = directDescriptors.map { descriptor -> CLICommandAdapter in
            guard let commandType = commandTypesByFenceCommand[descriptor.command] else {
                preconditionFailure("Missing CLI adapter for direct Fence command \(descriptor.command.rawValue)")
            }
            return .fence(commandType, descriptor: descriptor)
        }
        return directAdapters + cliOnlyAdapters
    }()

    static var subcommands: [ParsableCommand.Type] {
        adapters.map(\.commandType)
    }

    static func descriptor(for commandType: CLICommandContract.Type) -> FenceCommandDescriptor? {
        descriptorsByCommandType[ObjectIdentifier(commandType)]
    }

    private static let descriptorsByCommandType: [ObjectIdentifier: FenceCommandDescriptor] = {
        return Dictionary(
            uniqueKeysWithValues: adapters.compactMap { adapter in
                guard let commandType = adapter.commandType as? CLICommandContract.Type,
                      let descriptor = adapter.fenceDescriptor else { return nil }
                return (ObjectIdentifier(commandType), descriptor)
            }
        )
    }()
}

extension CLICommandContract {
    static var fenceCommand: TheFence.Command {
        guard let command = CLICommandAdapterCatalog.descriptor(for: Self.self)?.command else {
            fatalError("No Fence command descriptor registered for CLI adapter \(Self.self)")
        }

        return command
    }

    static var cliCommandName: String {
        fenceCommand.rawValue
    }

    static func fenceArguments(
        _ parameters: CLIRequestParameters = CLIRequestParameters(),
        target: ElementTarget? = nil
    ) -> TheFence.CommandArgumentEnvelope {
        CLIRequestBuilder.arguments(parameters: parameters, target: target)
    }

    static func fenceArguments(
        target: ElementTarget? = nil,
        _ fields: CommandArgumentWriter.Field?...
    ) -> TheFence.CommandArgumentEnvelope {
        CLIRequestBuilder.arguments(
            parameters: CommandArgumentWriter.parameters(fields),
            target: target
        )
    }

    static func catalogDefaultString(for key: FenceParameterKey) -> String {
        fenceCommand.descriptor.requiredDefaultString(for: key)
    }

    static func catalogAllowedValues(for key: FenceParameterKey) -> [String] {
        guard let values = fenceCommand.descriptor.parameter(named: key)?.enumValues else {
            fatalError("No enum values registered for \(fenceCommand.rawValue).\(key.rawValue)")
        }
        return values
    }

    static func catalogAllowedValuesDescription(for key: FenceParameterKey) -> String {
        catalogAllowedValues(for: key).joined(separator: ", ")
    }

    static func catalogCanonicalStringValue(
        _ value: String,
        for key: FenceParameterKey
    ) -> String? {
        let values = catalogAllowedValues(for: key)
        return values.contains(value) ? value : nil
    }
}
