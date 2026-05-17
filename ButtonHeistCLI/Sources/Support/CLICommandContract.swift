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
}

extension TheFence.Command {
    var cliCommandName: String {
        rawValue
    }

    func cliRequest(_ parameters: [String: Any] = [:]) -> [String: Any] {
        var request = parameters
        request["command"] = rawValue
        return request
    }
}
