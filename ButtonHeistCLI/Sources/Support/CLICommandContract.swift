import ButtonHeist
import Foundation

typealias CLIRequestParameters = [FenceParameterKey: HeistValue]

protocol CLICommandContract {
    static var fenceCommand: TheFence.Command { get }
}

protocol GestureCLICommandContract: CLICommandContract {
    static var gestureType: GestureType { get }
}

extension CLICommandContract {
    static var fenceCommand: TheFence.Command {
        let typeName = String(describing: Self.self)
        let commandName = typeName
            .removingSuffix("Command")
            .removingSuffix("Subcommand")
            .lowercasingFirstLetter()

        guard let command = TheFence.Command.descriptors.first(where: { descriptor in
            descriptor.cliExposure == .directCommand
                && String(describing: descriptor.command) == commandName
        })?.command else {
            fatalError("No direct Fence command descriptor matching CLI adapter \(typeName)")
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

extension GestureCLICommandContract {
    static var fenceCommand: TheFence.Command {
        TheFence.Command.command(for: gestureType)
    }
}

private extension String {
    func removingSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix) else { return self }
        return String(dropLast(suffix.count))
    }

    func lowercasingFirstLetter() -> String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}

extension FenceParameterKey {
    static func rawDictionary(_ parameters: CLIRequestParameters) -> [String: Any] {
        Dictionary(
            parameters.map { ($0.key.rawValue, $0.value.toAny()) },
            uniquingKeysWith: { _, newest in newest }
        )
    }
}

extension Dictionary where Key == String, Value == Any {
    subscript(_ key: FenceParameterKey) -> Any? {
        get { self[key.rawValue] }
        set { self[key.rawValue] = newValue }
    }

    mutating func set(_ key: FenceParameterKey, _ value: HeistValue) {
        self[key] = value.toAny()
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
