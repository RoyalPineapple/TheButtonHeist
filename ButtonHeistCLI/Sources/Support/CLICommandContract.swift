import ButtonHeist
import Foundation

typealias CLIRequestParameters = [FenceParameterKey: HeistValue]

protocol CLICommandContract {
    static var fenceCommand: TheFence.Command { get }
}

protocol CatalogBackedCLICommand: CLICommandContract {
    static var fenceCommandProjection: TheFence.Command.CLIProjection { get }
}

extension CatalogBackedCLICommand {
    static var fenceCommand: TheFence.Command {
        TheFence.Command.cliCommand(for: fenceCommandProjection)
    }
}

extension CLICommandContract {
    static var cliCommandName: String {
        fenceCommand.cliCommandName
    }

    static func fenceRequest(_ parameters: CLIRequestParameters = [:]) -> [String: Any] {
        fenceCommand.cliRequest(parameters)
    }
}

extension TheFence.Command {
    var cliCommandName: String {
        rawValue
    }

    func cliRequest(_ parameters: CLIRequestParameters = [:]) -> [String: Any] {
        var request = FenceParameterKey.rawDictionary(parameters)
        request[.command] = rawValue
        return request
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
