import Foundation

public enum HeistPlanError: Error, Sendable, Equatable {
    case unsupportedActionCommand(String)
    case ambiguousExpectationContract
    case emptyExpectationWaiver
    case expectationElseBodyUnsupported
    case emptyPredicateCases(String)
    case negativeTimeout(Double)
    case emptyForEachPredicate
    case invalidForEachLimit(Int)
    case emptyForEachParameter
    case invalidForEachParameter(String)
    case emptyForEachSteps
    case emptyForEachValues
    case emptyRepeatUntilSteps
    case nestedForEachUnsupported
}

public extension HeistPlan {
    func heistDefinition(at path: [String]) -> HeistPlan? {
        HeistDefinitionScope(definitions: definitions).resolve(path: path)?.definition
    }
}

public enum HeistParameterName {
    public static func normalized(_ parameter: String) throws -> String {
        let trimmed = parameter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HeistPlanError.emptyForEachParameter
        }
        guard isValid(trimmed) else {
            throw HeistPlanError.invalidForEachParameter(trimmed)
        }
        return trimmed
    }

    public static func isValid(_ parameter: String) -> Bool {
        guard let first = parameter.unicodeScalars.first,
              CharacterSet.letters.union(CharacterSet(charactersIn: "_")).contains(first) else {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return parameter.unicodeScalars.allSatisfy { allowed.contains($0) } && !swiftKeywords.contains(parameter)
    }

    private static let swiftKeywords: Set<String> = [
        "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import",
        "init", "inout", "internal", "let", "open", "operator", "private", "precedencegroup", "protocol",
        "public", "rethrows", "static", "struct", "subscript", "typealias", "var", "break", "case",
        "catch", "continue", "default", "defer", "do", "else", "fallthrough", "for", "guard", "if",
        "in", "repeat", "return", "throw", "switch", "where", "while", "as", "Any", "catch", "false",
        "is", "nil", "super", "self", "Self", "throw", "throws", "true", "try",
    ]
}
