import Foundation

// MARK: - Heist Execution Environment

public typealias HeistReferenceName = String

public struct HeistExecutionEnvironment: Sendable, Equatable {
    public static let empty = HeistExecutionEnvironment()

    public let targets: [HeistReferenceName: ElementTarget]
    public let strings: [HeistReferenceName: String]

    public init(
        targets: [HeistReferenceName: ElementTarget] = [:],
        strings: [HeistReferenceName: String] = [:]
    ) {
        self.targets = targets
        self.strings = strings
    }

    public func binding(target: ElementTarget, to parameter: HeistReferenceName) -> HeistExecutionEnvironment {
        var targets = self.targets
        targets[parameter] = target
        return HeistExecutionEnvironment(targets: targets, strings: strings)
    }

    public func binding(string: String, to parameter: HeistReferenceName) -> HeistExecutionEnvironment {
        var strings = self.strings
        strings[parameter] = string
        return HeistExecutionEnvironment(targets: targets, strings: strings)
    }
}

public enum HeistExpressionError: Error, Sendable, Equatable, CustomStringConvertible {
    case unresolvedTargetReference(String)
    case unresolvedStringReference(String)
    case emptyReference(String)
    case invalidStringMatch(mode: String)
    case unsupportedHeistActionCommand(String)
    case parameterArgumentMismatch(parameter: HeistParameterKind, argument: HeistParameterKind)

    public var description: String {
        switch self {
        case .unresolvedTargetReference(let reference):
            return "unresolved target reference \"\(reference)\""
        case .unresolvedStringReference(let reference):
            return "unresolved string reference \"\(reference)\""
        case .emptyReference(let type):
            return "\(type) reference must not be empty"
        case .invalidStringMatch(let mode):
            return "\(mode) string match value must not be empty"
        case .unsupportedHeistActionCommand(let command):
            return "unsupported heist action command \"\(command)\""
        case .parameterArgumentMismatch(let parameter, let argument):
            return "heist argument type \(argument.rawValue) does not match parameter type \(parameter.rawValue)"
        }
    }
}

public extension HeistExecutionEnvironment {
    func binding(argument: HeistArgument, to parameter: HeistParameter) throws -> HeistExecutionEnvironment {
        guard argument.kind == parameter.kind else {
            throw HeistExpressionError.parameterArgumentMismatch(parameter: parameter.kind, argument: argument.kind)
        }
        switch (parameter, argument) {
        case (.none, .none):
            return self
        case (.string(let name), .string(let value)):
            return binding(string: try value.resolve(in: self), to: name)
        case (.elementTarget(let name), .elementTarget(let target)):
            return binding(target: try target.resolve(in: self), to: name)
        default:
            throw HeistExpressionError.parameterArgumentMismatch(parameter: parameter.kind, argument: argument.kind)
        }
    }
}
