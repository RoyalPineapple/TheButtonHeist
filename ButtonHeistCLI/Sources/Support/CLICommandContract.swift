import ArgumentParser
@_spi(ButtonHeistTooling) import ButtonHeist
import Foundation
import ThePlans

struct CommandArgumentEnvelopeBuilder {
    struct Field {
        let key: FenceParameterKey
        let value: HeistValue
    }

    private var values: [String: HeistValue]

    init(_ fields: Field?...) {
        self.init(fields)
    }

    init(_ fields: [Field?]) {
        values = Dictionary(uniqueKeysWithValues: fields.compactMap { field in
            field.map { ($0.key.rawValue, $0.value) }
        })
    }

    init<Payload: Encodable>(payload: Payload) {
        guard case .object(let values) = Self.encodedValue(payload) else {
            preconditionFailure("Command argument payload must encode as an object")
        }
        self.values = values
    }

    mutating func set(_ field: Field?) {
        guard let field else { return }
        values[field.key.rawValue] = field.value
    }

    mutating func set(_ fields: [Field?]) {
        fields.forEach { set($0) }
    }

    func build() -> TheFence.CommandArgumentEnvelope {
        TheFence.CommandArgumentEnvelope(values: values)
    }

    static func value(_ key: FenceParameterKey, _ value: HeistValue) -> Field {
        Field(key: key, value: value)
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

    static func value<Value>(_ parameter: FenceParameter<Value>, _ value: Value) -> Field {
        self.value(parameter.key, parameter.heistValue(for: value))
    }

    static func encoded<Value: Encodable>(_ key: FenceParameterKey, _ value: Value) -> Field {
        self.value(key, encodedValue(value))
    }

    static func optional(_ key: FenceParameterKey, _ value: HeistValue?) -> Field? {
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

    static func optional<Value>(_ parameter: FenceParameter<Value>, _ value: Value?) -> Field? {
        value.map { self.value(parameter, $0) }
    }

    static func optionalEncoded<Value: Encodable>(_ key: FenceParameterKey, _ value: Value?) -> Field? {
        value.map { self.encoded(key, $0) }
    }

    private static func encodedValue<Value: Encodable>(_ value: Value) -> HeistValue {
        do {
            return try TheFence.HeistValuePayloadEncoder.encode(value)
        } catch {
            preconditionFailure("Failed to encode command argument payload: \(error)")
        }
    }
}

/// Marker for CLI commands backed by the Fence command catalog.
///
/// Command identity is intentionally not a protocol requirement: concrete CLI
/// command types should not own or override Fence command identity.
protocol CLICommandContract: ParsableCommand {}

protocol OneShotCLICommand: AsyncParsableCommand, CLICommandContract {
    var runnerConnection: ConnectionOptions { get }
    var runnerFormat: OutputFormat? { get }
    var runnerExecutionMode: CLIRunner.ExecutionMode { get }
    var runnerStatusMessage: String? { get }

    func requestArguments() throws -> TheFence.CommandArgumentEnvelope

    @ButtonHeistActor
    func runnerDescriptor() async throws -> CLIRunner.CommandDescriptor
}

protocol ConnectedOneShotCLICommand: OneShotCLICommand {
    var connection: ConnectionOptions { get }
    var output: OutputOptions { get }
}

protocol LocalOneShotCLICommand: OneShotCLICommand {
    var output: OutputOptions { get }
}

extension OneShotCLICommand {
    var runnerExecutionMode: CLIRunner.ExecutionMode { .connected }
    var runnerStatusMessage: String? { nil }

    func requestArguments() throws -> TheFence.CommandArgumentEnvelope {
        Self.fenceArguments()
    }

    @ButtonHeistActor
    func runnerDescriptor() async throws -> CLIRunner.CommandDescriptor {
        CLIRunner.CommandDescriptor(
            fenceDescriptor: Self.fenceDescriptor,
            connection: runnerConnection,
            format: runnerFormat,
            arguments: try requestArguments(),
            executionMode: runnerExecutionMode,
            statusMessage: runnerStatusMessage
        )
    }

    @ButtonHeistActor
    mutating func run() async throws {
        try await CLIRunner.run(try await runnerDescriptor())
    }
}

extension ConnectedOneShotCLICommand {
    var runnerConnection: ConnectionOptions { connection }
    var runnerFormat: OutputFormat? { output.format }
}

extension LocalOneShotCLICommand {
    var runnerConnection: ConnectionOptions { ConnectionOptions() }
    var runnerFormat: OutputFormat? { output.format }
    var runnerExecutionMode: CLIRunner.ExecutionMode { .direct }
}

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
        .getAnnouncements: GetAnnouncementsCommand.self,
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
    static var fenceDescriptor: FenceCommandDescriptor {
        guard let descriptor = CLICommandAdapterCatalog.descriptor(for: Self.self) else {
            fatalError("No Fence command descriptor registered for CLI adapter \(Self.self)")
        }
        return descriptor
    }

    static var fenceCommand: TheFence.Command {
        fenceDescriptor.command
    }

    static var cliCommandName: String {
        fenceCommand.rawValue
    }

    static func fenceArguments(
        target: AccessibilityTarget? = nil,
        _ fields: CommandArgumentEnvelopeBuilder.Field?...
    ) -> TheFence.CommandArgumentEnvelope {
        var builder = CommandArgumentEnvelopeBuilder(fields)
        builder.set(CommandArgumentEnvelopeBuilder.optionalEncoded(.target, target))
        return builder.build()
    }

    static func fenceArguments<Payload: Encodable>(payload: Payload) -> TheFence.CommandArgumentEnvelope {
        CommandArgumentEnvelopeBuilder(payload: payload).build()
    }

    static func catalogDefaultValue<Value>(for parameter: FenceParameter<Value>) -> Value {
        fenceDescriptor.requiredDefaultValue(for: parameter)
    }

    static func catalogDefaultArgument<Value>(for parameter: FenceParameter<Value>) -> String
    where Value: RawRepresentable, Value.RawValue == String {
        catalogDefaultValue(for: parameter).rawValue
    }

    static func catalogAllowedValuesDescription<Value>(for parameter: FenceParameter<Value>) -> String {
        fenceDescriptor.allowedRawValues(for: parameter).joined(separator: ", ")
    }

    static func catalogCanonicalValue<Value>(
        _ rawValue: String,
        for parameter: FenceParameter<Value>
    ) -> Value? where Value: RawRepresentable, Value.RawValue == String {
        let values = fenceDescriptor.allowedRawValues(for: parameter)
        guard values.contains(rawValue) else { return nil }
        return Value(rawValue: rawValue)
    }
}
