import Foundation

extension HeistCanonicalSwiftDSLRenderer {
    func renderDefinitions(
        _ definitions: [HeistPlan],
        path: [String],
        indent: Int
    ) throws -> String {
        try definitions.map { definition in
            try renderDefinition(definition, path: path, indent: indent)
        }.joined(separator: "\n\n")
    }

    func renderDefinition(
        _ definition: HeistPlan,
        path: [String],
        indent: Int
    ) throws -> String {
        guard let name = definition.name else {
            throw HeistCanonicalSwiftDSLError.invalidParameter("<anonymous>")
        }
        try validateParameter(name)
        let fullPath = path + [name]
        if definition.body.isEmpty, !definition.definitions.isEmpty, definition.parameter == .none {
            return try renderDefinitions(definition.definitions, path: fullPath, indent: indent)
        }
        let nestedDefinitions = try renderDefinitions(definition.definitions, path: [], indent: indent + 1)
        let definitionType = try renderDefinitionType(definition.parameter)
        let header = try renderDefinitionHeader(definition, type: definitionType, path: fullPath)

        switch definition.parameter {
        case .none:
            let body = try render(steps: definition.body, indent: indent + 1, environment: .empty)
            let content = [nestedDefinitions, body].filter { !$0.isEmpty }.joined(separator: "\n\n")
            return """
            \(line(header, indent))
            \(content)
            \(line("}", indent))
            """
        case .string, .elementTarget:
            let childEnvironment = try RenderEnvironment.empty.binding(parameter: definition.parameter)
            let body = try render(steps: definition.body, indent: indent + 1, environment: childEnvironment)
            let content = [nestedDefinitions, body].filter { !$0.isEmpty }.joined(separator: "\n\n")
            return """
            \(line(header, indent))
            \(content)
            \(line("}", indent))
            """
        }
    }

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
        case .elementTarget(let parameter):
            try validateParameter(parameter)
            return "\(type)(\(pathArgument), parameter: \(quote(parameter))) { \(parameter) in"
        }
    }

    func renderDefinitionType(_ parameter: HeistParameter) throws -> String {
        switch parameter {
        case .string:
            return "HeistDef<String>"
        case .elementTarget:
            return "HeistDef<ElementTarget>"
        case .none:
            return "HeistDef<Void>"
        }
    }
}
