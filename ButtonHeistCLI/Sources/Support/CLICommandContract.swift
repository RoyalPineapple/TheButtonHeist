import ButtonHeist
import Foundation

protocol CLICommandContract {
    static var fenceCommand: TheFence.Command { get }
}

extension CLICommandContract {
    static var cliCommandName: String {
        fenceCommand.cliCommandName
    }

    static func fenceRequest(_ parameters: [String: Any] = [:]) -> [String: Any] {
        fenceCommand.cliRequest(parameters)
    }

    static func fenceRequest(_ parameters: [FenceParameterKey: Any]) -> [String: Any] {
        fenceCommand.cliRequest(parameters)
    }
}

extension TheFence.Command {
    var cliCommandName: String {
        rawValue
    }

    func cliRequest(_ parameters: [String: Any] = [:]) -> [String: Any] {
        var request = parameters
        request[.command] = rawValue
        return request
    }

    func cliRequest(_ parameters: [FenceParameterKey: Any]) -> [String: Any] {
        cliRequest(FenceParameterKey.rawDictionary(parameters))
    }
}

extension FenceParameterKey {
    static func rawDictionary(_ parameters: [FenceParameterKey: Any]) -> [String: Any] {
        Dictionary(uniqueKeysWithValues: parameters.map { ($0.key.rawValue, $0.value) })
    }
}

extension Dictionary where Key == String, Value == Any {
    subscript(_ key: FenceParameterKey) -> Any? {
        get { self[key.rawValue] }
        set { self[key.rawValue] = newValue }
    }
}
