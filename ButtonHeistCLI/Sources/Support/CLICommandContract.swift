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

    var fenceCommand: TheFence.Command? {
        fenceDescriptor?.command
    }

    static func fence(_ commandType: CLICommandContract.Type) -> Self {
        Self(
            commandType: commandType,
            fenceDescriptor: CLICommandAdapterCatalog.descriptor(for: commandType)
        )
    }

    static func cliOnly(_ commandType: ParsableCommand.Type) -> Self {
        Self(commandType: commandType, fenceDescriptor: nil)
    }
}

enum CLICommandAdapterCatalog {
    private static let directCommandTypesByDescriptorOrder: [CLICommandContract.Type] = [
        PingCommand.self,
        ListCommand.self,
        GetInterfaceCommand.self,
        ScreenshotCommand.self,
        WaitForChangeCommand.self,
        TapSubcommand.self,
        LongPressSubcommand.self,
        SwipeSubcommand.self,
        DragSubcommand.self,
        PinchSubcommand.self,
        RotateSubcommand.self,
        TwoFingerTapSubcommand.self,
        DrawPathCommand.self,
        DrawBezierCommand.self,
        ScrollCommand.self,
        ScrollToVisibleCommand.self,
        ElementSearchCommand.self,
        ScrollToEdgeCommand.self,
        ActivateCommand.self,
        RotorCommand.self,
        TypeCommand.self,
        EditActionCommand.self,
        SetPasteboardCommand.self,
        GetPasteboardCommand.self,
        WaitForCommand.self,
        DismissKeyboardCommand.self,
        RecordCommand.self,
        StopRecordingCommand.self,
        RunBatchCommand.self,
        GetSessionStateCommand.self,
        ConnectCommand.self,
        ListTargetsCommand.self,
        SessionLogCommand.self,
        ArchiveSessionCommand.self,
        StartHeistCommand.self,
        StopHeistCommand.self,
        PlayHeistCommand.self,
    ]

    private static let subcommandTypes: [ParsableCommand.Type] = [
        ListCommand.self,
        PingCommand.self,
        GetInterfaceCommand.self,
        ActivateCommand.self,
        RotorCommand.self,
        TypeCommand.self,
        ScreenshotCommand.self,
        ScrollCommand.self,
        SwipeSubcommand.self,
        SessionCommand.self,
        ConnectCommand.self,

        ScrollToVisibleCommand.self,
        ElementSearchCommand.self,
        ScrollToEdgeCommand.self,

        EditActionCommand.self,
        DismissKeyboardCommand.self,

        TapSubcommand.self,
        LongPressSubcommand.self,
        DragSubcommand.self,
        PinchSubcommand.self,
        RotateSubcommand.self,
        TwoFingerTapSubcommand.self,
        DrawPathCommand.self,
        DrawBezierCommand.self,

        SetPasteboardCommand.self,
        GetPasteboardCommand.self,

        RecordCommand.self,
        StopRecordingCommand.self,
        WaitForChangeCommand.self,
        WaitForCommand.self,

        SessionLogCommand.self,
        ArchiveSessionCommand.self,
        GetSessionStateCommand.self,
        ListTargetsCommand.self,
        RunBatchCommand.self,

        StartHeistCommand.self,
        StopHeistCommand.self,
        PlayHeistCommand.self,
    ]

    static let adapters: [CLICommandAdapter] = subcommandTypes.map { commandType in
        if let fenceCommandType = commandType as? CLICommandContract.Type {
            return .fence(fenceCommandType)
        }
        return .cliOnly(commandType)
    }

    static var subcommands: [ParsableCommand.Type] {
        adapters.map(\.commandType)
    }

    static func descriptor(for commandType: CLICommandContract.Type) -> FenceCommandDescriptor? {
        descriptorsByCommandType[ObjectIdentifier(commandType)]
    }

    static func fenceCommand(for commandType: CLICommandContract.Type) -> TheFence.Command? {
        descriptor(for: commandType)?.command
    }

    private static let descriptorsByCommandType: [ObjectIdentifier: FenceCommandDescriptor] = {
        let descriptors = TheFence.Command.descriptors.filter { descriptor in
            descriptor.cliExposure == .directCommand
        }
        precondition(
            descriptors.count == directCommandTypesByDescriptorOrder.count,
            """
            Direct CLI command adapter count must match direct Fence command descriptors. \
            Update CLICommandAdapterCatalog.directCommandTypesByDescriptorOrder when the \
            Fence catalog direct CLI exposure changes.
            """
        )

        return Dictionary(
            uniqueKeysWithValues: zip(directCommandTypesByDescriptorOrder, descriptors).map { commandType, descriptor in
                (ObjectIdentifier(commandType), descriptor)
            }
        )
    }()
}

extension CLICommandContract {
    static var fenceCommand: TheFence.Command {
        guard let command = CLICommandAdapterCatalog.fenceCommand(for: Self.self) else {
            fatalError("No Fence command descriptor registered for CLI adapter \(Self.self)")
        }

        return command
    }

    static var cliCommandName: String {
        fenceCommand.cliCommandName
    }

    static func fenceRequest(_ parameters: CLIRequestParameters = [:]) -> [String: Any] {
        fenceCommand.cliRequest(parameters)
    }

    static func catalogDefaultString(for key: FenceParameterKey) -> String {
        guard case .string(let value)? = fenceCommand.defaultArgumentValue(for: key) else {
            fatalError("No string default registered for \(fenceCommand.rawValue).\(key.rawValue)")
        }
        return value
    }

    static func catalogAllowedValues(for key: FenceParameterKey) -> [String] {
        guard let values = fenceCommand.parameter(named: key)?.enumValues else {
            fatalError("No enum values registered for \(fenceCommand.rawValue).\(key.rawValue)")
        }
        return values
    }

    static func catalogAllowedValuesDescription(for key: FenceParameterKey) -> String {
        catalogAllowedValues(for: key).joined(separator: ", ")
    }

    static func catalogCanonicalStringValue(
        _ value: String,
        for key: FenceParameterKey,
        caseInsensitive: Bool = true
    ) -> String? {
        let values = catalogAllowedValues(for: key)
        if caseInsensitive {
            let normalizedValue = value.lowercased()
            return values.first { $0.lowercased() == normalizedValue }
        }
        return values.contains(value) ? value : nil
    }
}

extension TheFence.Command {
    var cliCommandName: String {
        descriptor.cliName ?? rawValue
    }

    func cliRequest(_ parameters: CLIRequestParameters = [:]) -> [String: Any] {
        CLIRequestBuilder.request(command: self, parameters: parameters)
    }
}

extension FenceParameterKey {
    static func rawDictionary(_ parameters: CLIRequestParameters) -> [String: Any] {
        Dictionary(
            parameters.map { ($0.key.rawValue, $0.value.cliRawValue) },
            uniquingKeysWith: { _, newest in newest }
        )
    }
}

extension HeistValue {
    var cliRawValue: Any {
        switch self {
        case .string(let value):
            value
        case .int(let value):
            value
        case .double(let value):
            value
        case .bool(let value):
            value
        case .array(let values):
            values.map(\.cliRawValue)
        case .object(let values):
            values.mapValues(\.cliRawValue)
        }
    }
}

extension Dictionary where Key == String, Value == Any {
    subscript(_ key: FenceParameterKey) -> Any? {
        get { self[key.rawValue] }
        set { self[key.rawValue] = newValue }
    }

    mutating func set(_ key: FenceParameterKey, _ value: HeistValue) {
        self[key] = value.cliRawValue
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
