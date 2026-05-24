import ArgumentParser
import ButtonHeist
import Foundation

typealias CLIRequestParameters = [FenceParameterKey: HeistValue]

protocol CLICommandContract {
    static var fenceCommand: TheFence.Command { get }
}

protocol GestureCLICommandContract: CLICommandContract {}

struct CLICommandAdapter {
    let commandType: ParsableCommand.Type
    let fenceDescriptor: FenceCommandDescriptor?

    var fenceCommand: TheFence.Command? {
        fenceDescriptor?.command
    }

    static func fence(
        _ commandType: ParsableCommand.Type,
        _ fenceCommand: TheFence.Command
    ) -> Self {
        Self(commandType: commandType, fenceDescriptor: fenceCommand.descriptor)
    }

    static func cliOnly(_ commandType: ParsableCommand.Type) -> Self {
        Self(commandType: commandType, fenceDescriptor: nil)
    }
}

enum CLICommandAdapterCatalog {
    static let adapters: [CLICommandAdapter] = [
        .fence(ListCommand.self, .listDevices),
        .fence(PingCommand.self, .ping),
        .fence(GetInterfaceCommand.self, .getInterface),
        .fence(ActivateCommand.self, .activate),
        .fence(RotorCommand.self, .rotor),
        .fence(TypeCommand.self, .typeText),
        .fence(ScreenshotCommand.self, .getScreen),
        .fence(ScrollCommand.self, .scroll),
        .fence(SwipeSubcommand.self, .swipe),
        .cliOnly(SessionCommand.self),
        .fence(ConnectCommand.self, .connect),

        .fence(ScrollToVisibleCommand.self, .scrollToVisible),
        .fence(ElementSearchCommand.self, .elementSearch),
        .fence(ScrollToEdgeCommand.self, .scrollToEdge),

        .fence(EditActionCommand.self, .editAction),
        .fence(DismissKeyboardCommand.self, .dismissKeyboard),

        .fence(TapSubcommand.self, .oneFingerTap),
        .fence(LongPressSubcommand.self, .longPress),
        .fence(DragSubcommand.self, .drag),
        .fence(PinchSubcommand.self, .pinch),
        .fence(RotateSubcommand.self, .rotate),
        .fence(TwoFingerTapSubcommand.self, .twoFingerTap),
        .fence(DrawPathCommand.self, .drawPath),
        .fence(DrawBezierCommand.self, .drawBezier),

        .fence(SetPasteboardCommand.self, .setPasteboard),
        .fence(GetPasteboardCommand.self, .getPasteboard),

        .fence(RecordCommand.self, .startRecording),
        .fence(StopRecordingCommand.self, .stopRecording),
        .fence(WaitForChangeCommand.self, .waitForChange),
        .fence(WaitForCommand.self, .waitFor),

        .fence(SessionLogCommand.self, .getSessionLog),
        .fence(ArchiveSessionCommand.self, .archiveSession),
        .fence(GetSessionStateCommand.self, .getSessionState),
        .fence(ListTargetsCommand.self, .listTargets),
        .fence(RunBatchCommand.self, .runBatch),

        .fence(StartHeistCommand.self, .startHeist),
        .fence(StopHeistCommand.self, .stopHeist),
        .fence(PlayHeistCommand.self, .playHeist),
    ]

    static var subcommands: [ParsableCommand.Type] {
        adapters.map(\.commandType)
    }

    static func fenceCommand(for commandType: CLICommandContract.Type) -> TheFence.Command? {
        adapters.first { adapter in
            ObjectIdentifier(adapter.commandType) == ObjectIdentifier(commandType)
        }?.fenceCommand
    }
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
