import ArgumentParser
import ButtonHeist
import Foundation

typealias CLIRequestParameters = [FenceParameterKey: HeistValue]

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
        .getSessionState: GetSessionStateCommand.self,
        .connect: ConnectCommand.self,
        .listTargets: ListTargetsCommand.self,
        .startHeist: StartHeistCommand.self,
        .stopHeist: StopHeistCommand.self,
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
        _ parameters: CLIRequestParameters = [:],
        target: ElementTarget? = nil
    ) -> TheFence.CommandArgumentEnvelope {
        CLIRequestBuilder.arguments(parameters: parameters, target: target)
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

extension Dictionary where Key == FenceParameterKey, Value == HeistValue {
    mutating func set(_ key: FenceParameterKey, _ value: HeistValue) {
        self[key] = value
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
}
