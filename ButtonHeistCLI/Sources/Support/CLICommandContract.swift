import ArgumentParser
@_spi(ButtonHeistTooling) import ButtonHeist
import Foundation
import ThePlans
import TheScore

struct CommandArgumentFields {
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

    var envelope: TheFence.CommandArgumentEnvelope {
        TheFence.CommandArgumentEnvelope(values: values)
    }

    mutating func insert(_ field: Field?) {
        guard let field else { return }
        values[field.key.rawValue] = field.value
    }

    mutating func insert(_ fields: [Field?]) {
        fields.forEach { insert($0) }
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

protocol OneShotCLICommand: AsyncParsableCommand {
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

enum CLICommandCatalog {
    // MARK: - Pure CLI Wiring
    //
    // This table binds catalog-owned command identities to concrete
    // ArgumentParser adapter types. It must not carry product command
    // semantics: public names, defaults, parameters, and help all
    // project from FenceCommandDescriptor/FenceParameterSpec below.
    private static let commandTypesByFenceCommand: [TheFence.Command: OneShotCLICommand.Type] = [
        .ping: PingCommand.self,
        .listDevices: ListDevicesCommand.self,
        .getInterface: GetInterfaceCommand.self,
        .getScreen: GetScreenCommand.self,
        .wait: WaitCommand.self,
        .oneFingerTap: OneFingerTapCommand.self,
        .longPress: LongPressCommand.self,
        .swipe: SwipeCommand.self,
        .drag: DragCommand.self,
        .scroll: ScrollCommand.self,
        .scrollToVisible: ScrollToVisibleCommand.self,
        .scrollToEdge: ScrollToEdgeCommand.self,
        .activate: ActivateCommand.self,
        .rotor: RotorCommand.self,
        .typeText: TypeTextCommand.self,
        .editAction: EditActionCommand.self,
        .setPasteboard: SetPasteboardCommand.self,
        .getPasteboard: GetPasteboardCommand.self,
        .getAnnouncements: GetAnnouncementsCommand.self,
        .dismissKeyboard: DismissKeyboardCommand.self,
        .runHeist: RunHeistCommand.self,
        .validateHeist: ValidateHeistCommand.self,
        .listHeists: ListHeistsCommand.self,
        .describeHeist: DescribeHeistCommand.self,
        .getSessionState: GetSessionStateCommand.self,
        .connect: ConnectCommand.self,
        .listTargets: ListTargetsCommand.self,
    ]

    static let subcommands: [ParsableCommand.Type] = {
        let directDescriptors = TheFence.Command.cliDirectCommandDescriptors
        let directCommandSet = Set(directDescriptors.map(\.command))
        precondition(
            Set(commandTypesByFenceCommand.keys) == directCommandSet,
            """
            CLI command map must cover exactly the Fence descriptors marked directCommand. \
            Update CLICommandCatalog.commandTypesByFenceCommand when descriptor CLI exposure changes.
            """
        )

        let directCommands = directDescriptors.map { descriptor -> ParsableCommand.Type in
            guard let commandType = commandTypesByFenceCommand[descriptor.command] else {
                preconditionFailure("Missing CLI command type for direct Fence command \(descriptor.command.rawValue)")
            }
            return commandType
        }
        return directCommands + [JSONLinesCommand.self]
    }()

    static func descriptor(for commandType: OneShotCLICommand.Type) -> FenceCommandDescriptor? {
        commandTypesByFenceCommand.first {
            ObjectIdentifier($0.value) == ObjectIdentifier(commandType)
        }?.key.descriptor
    }
}

extension OneShotCLICommand {
    static var fenceDescriptor: FenceCommandDescriptor {
        guard let descriptor = CLICommandCatalog.descriptor(for: Self.self) else {
            fatalError("No Fence command descriptor registered for CLI command \(Self.self)")
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
        _ fields: CommandArgumentFields.Field?...
    ) -> TheFence.CommandArgumentEnvelope {
        var fields = CommandArgumentFields(fields)
        fields.insert(CommandArgumentFields.optionalEncoded(.target, target))
        return fields.envelope
    }

    static func fenceArguments<Payload: Encodable>(payload: Payload) -> TheFence.CommandArgumentEnvelope {
        CommandArgumentFields(payload: payload).envelope
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
