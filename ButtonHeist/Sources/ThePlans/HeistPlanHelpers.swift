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
        return parameter.unicodeScalars.allSatisfy { allowed.contains($0) }
            && !SwiftIdentifier.isReserved(parameter)
    }
}

private enum SwiftIdentifier {
    static func isReserved(_ identifier: String) -> Bool {
        ReservedWord(rawValue: identifier) != nil
    }

    enum ReservedWord: String, CaseIterable {
        case associatedType = "associatedtype"
        case classDeclaration = "class"
        case deinitializer = "deinit"
        case enumeration = "enum"
        case extensionDeclaration = "extension"
        case fileprivateAccess = "fileprivate"
        case functionDeclaration = "func"
        case importDeclaration = "import"
        case initializer = "init"
        case inoutParameter = "inout"
        case internalAccess = "internal"
        case letDeclaration = "let"
        case openAccess = "open"
        case operatorDeclaration = "operator"
        case privateAccess = "private"
        case precedenceGroup = "precedencegroup"
        case protocolDeclaration = "protocol"
        case publicAccess = "public"
        case rethrowsEffect = "rethrows"
        case staticDeclaration = "static"
        case structDeclaration = "struct"
        case subscriptDeclaration = "subscript"
        case typeAlias = "typealias"
        case variableDeclaration = "var"

        case breakStatement = "break"
        case caseStatement = "case"
        case catchStatement = "catch"
        case continueStatement = "continue"
        case defaultStatement = "default"
        case deferStatement = "defer"
        case doStatement = "do"
        case elseBranch = "else"
        case fallthroughStatement = "fallthrough"
        case forStatement = "for"
        case guardStatement = "guard"
        case ifStatement = "if"
        case inKeyword = "in"
        case repeatStatement = "repeat"
        case returnStatement = "return"
        case throwStatement = "throw"
        case switchStatement = "switch"
        case whereClause = "where"
        case whileStatement = "while"

        case asCast = "as"
        case anyExistential = "Any"
        case falseLiteral = "false"
        case isTypeCheck = "is"
        case nilLiteral = "nil"
        case superReference = "super"
        case selfValue = "self"
        case selfType = "Self"
        case throwsEffect = "throws"
        case trueLiteral = "true"
        case tryExpression = "try"
    }
}
