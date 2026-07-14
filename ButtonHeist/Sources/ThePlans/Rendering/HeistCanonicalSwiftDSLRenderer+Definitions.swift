import Foundation

extension HeistCanonicalSwiftDSLRenderer {
    func renderDefinitionHeader(
        _ definition: HeistPlan,
        type: String,
        path: [String]
    ) throws -> String {
        let pathArgument = quote(path.joined(separator: "."))
        switch definition.parameter {
        case .none:
            return "\(type)(\(pathArgument)) {"
        case .string(let parameter):
            try validateParameter(parameter)
            return "\(type)(\(pathArgument), parameter: \(quote(parameter))) { \(parameter) in"
        case .accessibilityTarget(let parameter):
            try validateParameter(parameter)
            return "\(type)(\(pathArgument), parameter: \(quote(parameter))) { \(parameter) in"
        }
    }

    func renderDefinitionType(_ parameter: HeistParameter) throws -> String {
        switch parameter {
        case .string:
            return "HeistDef<String>"
        case .accessibilityTarget:
            return "HeistDef<AccessibilityTarget>"
        case .none:
            return "HeistDef<Void>"
        }
    }
}
