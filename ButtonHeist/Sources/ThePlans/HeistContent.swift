import Foundation

public protocol HeistContent {
    var heistSteps: [HeistStep] { get }
    var heistDefinitions: [HeistPlan] { get }
    var heistBuildDiagnostics: [String] { get }
}

public extension HeistContent {
    var heistDefinitions: [HeistPlan] { [] }
    var heistBuildDiagnostics: [String] { [] }
}

public extension HeistPlan {
    init(@HeistBuilder _ content: () throws -> some HeistContent) throws {
        try self.init(dslName: nil, content)
    }

    init(
        _ name: String,
        @HeistBuilder _ content: () throws -> some HeistContent
    ) throws {
        try self.init(dslName: name, content)
    }

    init(
        parameter: String,
        @HeistBuilder _ content: (StringExpr) throws -> some HeistContent
    ) throws {
        try self.init(dslName: nil, rootParameter: .string(name: parameter)) {
            try content(try StringExpr(ref: parameter))
        }
    }

    init(
        _ name: String,
        parameter: String,
        @HeistBuilder _ content: (StringExpr) throws -> some HeistContent
    ) throws {
        try self.init(dslName: name, rootParameter: .string(name: parameter)) {
            try content(try StringExpr(ref: parameter))
        }
    }

    init(
        targetParameter: String,
        @HeistBuilder _ content: (ElementTargetExpr) throws -> some HeistContent
    ) throws {
        try self.init(dslName: nil, rootParameter: .elementTarget(name: targetParameter)) {
            try content(try ElementTargetExpr(ref: targetParameter))
        }
    }

    init(
        _ name: String,
        targetParameter: String,
        @HeistBuilder _ content: (ElementTargetExpr) throws -> some HeistContent
    ) throws {
        try self.init(dslName: name, rootParameter: .elementTarget(name: targetParameter)) {
            try content(try ElementTargetExpr(ref: targetParameter))
        }
    }
}

private extension HeistPlan {
    init(
        dslName name: String?,
        _ content: () throws -> some HeistContent
    ) throws {
        let content = try content()
        try Self.throwIfBuildDiagnostics(content.heistBuildDiagnostics)
        self = try Self.validatedDSLPlan(
            name: name,
            definitions: content.heistDefinitions,
            body: content.heistSteps
        )
    }

    init(
        dslName name: String?,
        rootParameter parameter: HeistParameter,
        _ content: () throws -> some HeistContent
    ) throws {
        let content = try content()
        try Self.throwIfBuildDiagnostics(content.heistBuildDiagnostics)
        guard !content.heistSteps.isEmpty || !content.heistDefinitions.isEmpty else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [HeistPlanCodingKey("body")],
                debugDescription: "HeistPlan requires a non-empty body or definitions"
            ))
        }
        try self.init(name: name, parameter: parameter, definitions: content.heistDefinitions, body: content.heistSteps)
    }

    static func validatedDSLPlan(
        name: String? = nil,
        definitions: [HeistPlan] = [],
        body: [HeistStep]
    ) throws -> HeistPlan {
        guard !body.isEmpty || !definitions.isEmpty else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [HeistPlanCodingKey("body")],
                debugDescription: "HeistPlan requires a non-empty body or definitions"
            ))
        }
        return try HeistPlan(name: name, definitions: definitions, body: body)
    }

    static func throwIfBuildDiagnostics(_ diagnostics: [String]) throws {
        guard !diagnostics.isEmpty else { return }
        throw HeistPlanBuildError(diagnostics: diagnostics)
    }
}

public struct HeistPlanBuildError: Error, Sendable, Equatable, CustomStringConvertible {
    public let diagnostics: [String]

    public var description: String {
        "ButtonHeist plan build failed: \(diagnostics.joined(separator: "; "))"
    }
}

private struct HeistPlanCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        return nil
    }
}

extension HeistStep: HeistContent {
    public var heistSteps: [HeistStep] { [self] }
}

extension HeistPlan: HeistContent {
    public var heistSteps: [HeistStep] { body }
    public var heistDefinitions: [HeistPlan] { definitions }
}

public struct EmptyHeistContent: HeistContent {
    public let heistSteps: [HeistStep] = []
    public let heistDefinitions: [HeistPlan] = []
    public let heistBuildDiagnostics: [String] = []

    public init() {}
}

@resultBuilder
public enum HeistBuilder {
    public static func buildExpression(_ expression: some HeistContent) -> some HeistContent {
        expression
    }

    public static func buildExpression(_ expression: HeistStep) -> some HeistContent {
        expression
    }

    public static func buildExpression(_ expression: HeistPlan) -> some HeistContent {
        expression
    }

    public static func buildBlock(_ components: any HeistContent...) -> some HeistContent {
        HeistStepList(
            components.flatMap(\.heistSteps),
            definitions: mergeDefinitions(components.flatMap(\.heistDefinitions)),
            diagnostics: components.flatMap(\.heistBuildDiagnostics)
        )
    }

    private static func mergeDefinitions(_ definitions: [HeistPlan]) -> [HeistPlan] {
        var merged: [HeistPlan] = []
        for definition in definitions {
            guard let name = definition.name,
                  let existingIndex = merged.firstIndex(where: { $0.name == name }) else {
                merged.append(definition)
                continue
            }
            let existing = merged[existingIndex]
            if existing == definition {
                continue
            }
            if existing.isNamespaceDefinition, definition.isNamespaceDefinition {
                merged[existingIndex] = HeistPlan(
                    runtimeValidatedVersion: existing.version,
                    name: existing.name,
                    parameter: existing.parameter,
                    definitions: mergeDefinitions(existing.definitions + definition.definitions),
                    body: []
                )
            } else {
                merged.append(definition)
            }
        }
        return merged
    }
}

private extension HeistPlan {
    var isNamespaceDefinition: Bool {
        parameter == .none && body.isEmpty
    }
}

private struct HeistStepList: HeistContent {
    let heistSteps: [HeistStep]
    let heistDefinitions: [HeistPlan]
    let heistBuildDiagnostics: [String]

    init(
        _ heistSteps: [HeistStep],
        definitions: [HeistPlan] = [],
        diagnostics: [String] = []
    ) {
        self.heistSteps = heistSteps
        self.heistDefinitions = definitions
        self.heistBuildDiagnostics = diagnostics
    }
}

public struct HeistDef<Input>: Sendable {
    public let path: [String]
    public let parameter: HeistParameter
    private let definitionResult: HeistDefinitionBuildResult

    public init<Content: HeistContent>(
        _ path: String,
        @HeistBuilder _ content: @escaping () throws -> Content
    ) where Input == Void {
        let components = Self.pathComponents(path)
        self.path = components
        self.parameter = .none
        self.definitionResult = Self.buildDefinition(path: components, parameter: self.parameter) {
            try content()
        }
    }

    public init<Content: HeistContent>(
        _ path: String,
        parameter: String = "input",
        @HeistBuilder _ content: @escaping (StringExpr) throws -> Content
    ) where Input == String {
        let components = Self.pathComponents(path)
        self.path = components
        self.parameter = .string(name: parameter)
        self.definitionResult = Self.buildDefinition(path: components, parameter: self.parameter) {
            try content(try StringExpr(ref: parameter))
        }
    }

    public init<Content: HeistContent>(
        _ path: String,
        parameter: String = "input",
        @HeistBuilder _ content: @escaping (ElementTargetExpr) throws -> Content
    ) where Input == ElementTarget {
        let components = Self.pathComponents(path)
        self.path = components
        self.parameter = .elementTarget(name: parameter)
        self.definitionResult = Self.buildDefinition(path: components, parameter: self.parameter) {
            try content(try ElementTargetExpr(ref: parameter))
        }
    }

    private static func buildDefinition(
        path: [String],
        parameter: HeistParameter,
        _ content: () throws -> any HeistContent
    ) -> HeistDefinitionBuildResult {
        do {
            let content = try content()
            guard content.heistBuildDiagnostics.isEmpty else {
                return .failure(content.heistBuildDiagnostics.joined(separator: "; "))
            }
            return .success(makeDefinition(
                path: path,
                parameter: parameter,
                definitions: content.heistDefinitions,
                body: content.heistSteps
            ))
        } catch {
            return .failure(String(describing: error))
        }
    }

    private static func makeDefinition(
        path: [String],
        parameter: HeistParameter,
        definitions: [HeistPlan],
        body: [HeistStep]
    ) -> HeistPlan {
        guard let first = path.first else {
            return HeistPlan(
                runtimeValidatedVersion: HeistPlan.currentVersion,
                name: nil,
                parameter: parameter,
                definitions: definitions,
                body: body
            )
        }
        guard path.count > 1 else {
            return HeistPlan(
                runtimeValidatedVersion: HeistPlan.currentVersion,
                name: first,
                parameter: parameter,
                definitions: definitions,
                body: body
            )
        }
        let child = Self.makeDefinition(
            path: Array(path.dropFirst()),
            parameter: parameter,
            definitions: definitions,
            body: body
        )
        return HeistPlan(
            runtimeValidatedVersion: HeistPlan.currentVersion,
            name: first,
            definitions: [child],
            body: []
        )
    }

    private static func pathComponents(_ path: String) -> [String] {
        path.split(separator: ".").map(String.init)
    }

    fileprivate func invocation(argument: HeistArgument) throws -> HeistInvocationContent {
        switch definitionResult {
        case .success(let definition):
            return HeistInvocationContent(
                invocation: HeistInvocationStep(path: path, argument: argument),
                heistDefinitions: [definition]
            )
        case .failure(let message):
            throw HeistDefinitionBuildError(message: message)
        }
    }
}

private struct HeistInvocationContent: HeistContent {
    let invocation: HeistInvocationStep
    let heistDefinitions: [HeistPlan]

    var heistSteps: [HeistStep] { [.invoke(invocation)] }
}

private enum HeistDefinitionBuildResult: Sendable {
    case success(HeistPlan)
    case failure(String)
}

private struct HeistDefinitionBuildError: Error, Sendable, CustomStringConvertible {
    let message: String

    var description: String {
        "heist definition build failed: \(message)"
    }
}

public extension HeistDef where Input == Void {
    func callAsFunction() throws -> some HeistContent {
        try invocation(argument: .none)
    }
}

extension HeistDef: HeistContent {
    public var heistSteps: [HeistStep] { [] }

    public var heistDefinitions: [HeistPlan] {
        switch definitionResult {
        case .success(let definition):
            return [definition]
        case .failure:
            return []
        }
    }

    public var heistBuildDiagnostics: [String] {
        switch definitionResult {
        case .success:
            return []
        case .failure(let message):
            return ["HeistDef \(path.joined(separator: ".")) is invalid: \(message)"]
        }
    }
}

public extension HeistDef where Input == String {
    func callAsFunction(_ input: String) throws -> some HeistContent {
        try invocation(argument: .string(.literal(input)))
    }

    func callAsFunction(_ input: StringExpr) throws -> some HeistContent {
        try invocation(argument: .string(input))
    }
}

public extension HeistDef where Input == ElementTarget {
    func callAsFunction(_ input: ElementTarget) throws -> some HeistContent {
        try invocation(argument: .elementTarget(.target(input)))
    }

    func callAsFunction(_ input: ElementTargetExpr) throws -> some HeistContent {
        try invocation(argument: .elementTarget(input))
    }
}

// MARK: - RunHeist

// swiftlint:disable identifier_name
/// Run a named heist capability from inside a heist body.
///
/// `RunHeist` is the public Button Heist verb for composing capabilities. It
/// references a capability by name and lowers to the invocation IR; the named
/// capability must resolve within the closed plan — runtime safety enforces
/// resolution, arity, type, and non-recursion.
public func RunHeist(_ name: String) -> some HeistContent {
    runHeistInvocation(name, argument: .none)
}

public func RunHeist(_ name: String, _ input: String) -> some HeistContent {
    runHeistInvocation(name, argument: .string(.literal(input)))
}

public func RunHeist(_ name: String, _ input: StringExpr) -> some HeistContent {
    runHeistInvocation(name, argument: .string(input))
}

@_disfavoredOverload
public func RunHeist(_ name: String, _ input: ElementTarget) -> some HeistContent {
    runHeistInvocation(name, argument: .elementTarget(.target(input)))
}

public func RunHeist(_ name: String, _ input: ElementTargetExpr) -> some HeistContent {
    runHeistInvocation(name, argument: .elementTarget(input))
}

private func runHeistInvocation(_ name: String, argument: HeistArgument) -> HeistInvocationContent {
    HeistInvocationContent(
        invocation: HeistInvocationStep(
            path: name.split(separator: ".").map(String.init),
            argument: argument
        ),
        heistDefinitions: []
    )
}
// swiftlint:enable identifier_name

public struct ElementMatches: Sendable, Equatable {
    public let predicate: ElementPredicate

    public init(predicate: ElementPredicate) {
        self.predicate = predicate
    }

    public static func matching(_ predicate: ElementPredicate) -> ElementMatches {
        ElementMatches(predicate: predicate)
    }
}

public struct ForEach<Content: HeistContent>: HeistContent {
    public let heistSteps: [HeistStep]
    public let heistDefinitions: [HeistPlan]
    public let heistBuildDiagnostics: [String]

    public init(
        _ values: [String],
        parameter: String = "item",
        @HeistBuilder content: (StringExpr) throws -> Content
    ) {
        do {
            let parameter = try HeistParameterName.normalized(parameter)
            let item = try StringExpr(ref: parameter)
            let content = try content(item)
            let step = try ForEachStringStep(
                values: values,
                parameter: parameter,
                body: content.heistSteps
            )
            self.heistSteps = [.forEachString(step)]
            self.heistDefinitions = content.heistDefinitions
            self.heistBuildDiagnostics = content.heistBuildDiagnostics
        } catch {
            self.heistSteps = []
            self.heistDefinitions = []
            self.heistBuildDiagnostics = ["ForEach string loop is invalid: \(String(describing: error))"]
        }
    }

    public init(
        _ matches: ElementMatches,
        limit: Int = 20,
        parameter: String = "target",
        @HeistBuilder _ content: (ElementTargetExpr) throws -> Content
    ) {
        do {
            let parameter = try HeistParameterName.normalized(parameter)
            let target = try ElementTargetExpr(ref: parameter)
            let content = try content(target)
            let step = try ForEachElementStep(
                matching: matches.predicate,
                limit: limit,
                parameter: parameter,
                body: content.heistSteps
            )
            self.heistSteps = [.forEachElement(step)]
            self.heistDefinitions = content.heistDefinitions
            self.heistBuildDiagnostics = content.heistBuildDiagnostics
        } catch {
            self.heistSteps = []
            self.heistDefinitions = []
            self.heistBuildDiagnostics = ["ForEach element loop is invalid: \(String(describing: error))"]
        }
    }
}
