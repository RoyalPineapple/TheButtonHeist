import Foundation

public protocol HeistContent {
    var heistSteps: [HeistStep] { get }
    var heistDefinitions: [HeistPlan] { get }
    var heistBuildDiagnostics: [HeistBuildDiagnostic] { get }
}

public extension HeistContent {
    var heistDefinitions: [HeistPlan] { [] }
    var heistBuildDiagnostics: [HeistBuildDiagnostic] { [] }
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
        parameter: HeistReferenceName,
        @HeistBuilder _ content: (StringExpr) throws -> some HeistContent
    ) throws {
        let reference = try parameter.validated(type: "parameter")
        try self.init(dslName: nil, rootParameter: .string(name: reference)) {
            try content(try StringExpr(ref: reference))
        }
    }

    init(
        _ name: String,
        parameter: HeistReferenceName,
        @HeistBuilder _ content: (StringExpr) throws -> some HeistContent
    ) throws {
        let reference = try parameter.validated(type: "parameter")
        try self.init(dslName: name, rootParameter: .string(name: reference)) {
            try content(try StringExpr(ref: reference))
        }
    }

    init(
        targetParameter: HeistReferenceName,
        @HeistBuilder _ content: (ElementTargetExpr) throws -> some HeistContent
    ) throws {
        let reference = try targetParameter.validated(type: "target")
        try self.init(dslName: nil, rootParameter: .elementTarget(name: reference)) {
            try content(try ElementTargetExpr(ref: reference))
        }
    }

    init(
        _ name: String,
        targetParameter: HeistReferenceName,
        @HeistBuilder _ content: (ElementTargetExpr) throws -> some HeistContent
    ) throws {
        let reference = try targetParameter.validated(type: "target")
        try self.init(dslName: name, rootParameter: .elementTarget(name: reference)) {
            try content(try ElementTargetExpr(ref: reference))
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

    static func throwIfBuildDiagnostics(_ diagnostics: [HeistBuildDiagnostic]) throws {
        guard !diagnostics.isEmpty else { return }
        throw HeistPlanBuildError(diagnostics: diagnostics)
    }
}

public struct HeistPlanBuildError: Error, Sendable, Equatable, CustomStringConvertible {
    public let diagnostics: [HeistBuildDiagnostic]

    public var description: String {
        "ButtonHeist plan build failed: \(diagnostics.renderedMessages)"
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
    public let heistBuildDiagnostics: [HeistBuildDiagnostic] = []

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
    let heistBuildDiagnostics: [HeistBuildDiagnostic]

    init(
        _ heistSteps: [HeistStep],
        definitions: [HeistPlan] = [],
        diagnostics: [HeistBuildDiagnostic] = []
    ) {
        self.heistSteps = heistSteps
        self.heistDefinitions = definitions
        self.heistBuildDiagnostics = diagnostics
    }
}

public struct HeistDef<Input>: Sendable {
    public let path: [String]
    public let parameter: HeistParameter
    private let definitionResult: ValidationResult<HeistPlan, HeistBuildDiagnostic>

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
        parameter: HeistReferenceName = "input",
        @HeistBuilder _ content: @escaping (StringExpr) throws -> Content
    ) where Input == String {
        let components = Self.pathComponents(path)
        let reference = parameter
        self.path = components
        self.parameter = .string(name: reference)
        self.definitionResult = Self.buildDefinition(path: components, parameter: self.parameter) {
            try content(try StringExpr(ref: reference))
        }
    }

    public init<Content: HeistContent>(
        _ path: String,
        parameter: HeistReferenceName = "input",
        @HeistBuilder _ content: @escaping (ElementTargetExpr) throws -> Content
    ) where Input == ElementTarget {
        let components = Self.pathComponents(path)
        let reference = parameter
        self.path = components
        self.parameter = .elementTarget(name: reference)
        self.definitionResult = Self.buildDefinition(path: components, parameter: self.parameter) {
            try content(try ElementTargetExpr(ref: reference))
        }
    }

    private static func buildDefinition(
        path: [String],
        parameter: HeistParameter,
        _ content: () throws -> any HeistContent
    ) -> ValidationResult<HeistPlan, HeistBuildDiagnostic> {
        let renderedPath = HeistInvocationPath.render(path)
        do {
            let content = try content()
            guard content.heistBuildDiagnostics.isEmpty else {
                return .failure(content.heistBuildDiagnostics.map { $0.withPath(renderedPath) })
            }
            return .success(makeDefinition(
                path: path,
                parameter: parameter,
                definitions: content.heistDefinitions,
                body: content.heistSteps
            ), diagnostics: [])
        } catch {
            return .failure([.dslBuild(
                code: .dslInvalidDefinition,
                path: renderedPath,
                message: String(describing: error)
            )])
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
        HeistInvocationPath.components(fromDottedName: path)
    }

    fileprivate func invocation(argument: HeistArgument) throws -> HeistInvocationContent {
        let definition = try definitionResult.get(orThrow: HeistDefinitionBuildError.init(diagnostics:))
        return HeistInvocationContent(
            invocation: HeistInvocationStep(path: path, argument: argument),
            heistDefinitions: [definition]
        )
    }
}

public struct HeistInvocationContent: HeistContent {
    private static let invalidInvocationPlaceholder: HeistInvocationStep = {
        guard let path = try? HeistInvocationPath(components: ["invalid"]) else {
            preconditionFailure("known-valid placeholder invocation path failed validation")
        }
        return HeistInvocationStep(invocationPath: path, argument: .none)
    }()

    fileprivate let invocationStep: HeistInvocationStep?
    public var invocation: HeistInvocationStep {
        invocationStep ?? Self.invalidInvocationPlaceholder
    }

    public let heistDefinitions: [HeistPlan]
    let explicitExpectationTimeout: Double?
    let expectationValidationDiagnostics: [HeistBuildDiagnostic]
    private let invocationValidationDiagnostics: [HeistBuildDiagnostic]

    public var heistSteps: [HeistStep] {
        invocationStep.map { [.invoke($0)] } ?? []
    }

    public var heistBuildDiagnostics: [HeistBuildDiagnostic] {
        invocationValidationDiagnostics + expectationValidationDiagnostics.map {
            HeistBuildDiagnostic.dslBuild(
                code: .dslInvalidInvocationExpectation,
                path: invocationStep?.capabilityName ?? invocationValidationDiagnostics.first?.path,
                message: $0.message,
                hint: $0.hint
            )
        }
    }

    init(
        invocation: HeistInvocationStep,
        heistDefinitions: [HeistPlan],
        explicitExpectationTimeout: Double? = nil,
        expectationValidationDiagnostics: [HeistBuildDiagnostic] = []
    ) {
        self.invocationStep = invocation
        self.heistDefinitions = heistDefinitions
        self.explicitExpectationTimeout = explicitExpectationTimeout
        self.expectationValidationDiagnostics = expectationValidationDiagnostics
        self.invocationValidationDiagnostics = []
    }

    init(invalidDiagnostics: [HeistBuildDiagnostic]) {
        self.invocationStep = nil
        self.heistDefinitions = []
        self.explicitExpectationTimeout = nil
        self.expectationValidationDiagnostics = []
        self.invocationValidationDiagnostics = invalidDiagnostics
    }
}

public extension HeistInvocationContent {
    func expect(
        _ predicate: AccessibilityPredicateExpr,
        timeout: Double? = nil
    ) -> HeistInvocationContent {
        guard let invocationStep else { return self }

        let timeoutResult = composeExpectationTimeout(
            existing: invocationStep.expectation,
            existingExplicit: explicitExpectationTimeout,
            nextExplicit: timeout
        )
        let predicateResult = invocationStep.expectation.map {
            composeExpectationPredicates(existing: $0.predicate, next: predicate)
        } ?? ExpectationPredicateComposition(predicate: predicate, diagnostics: [])
        let validationDiagnostics = expectationValidationDiagnostics
            + predicateResult.diagnostics
            + timeoutResult.diagnostics

        return HeistInvocationContent(
            invocation: HeistInvocationStep(
                invocationPath: invocationStep.invocationPath,
                argument: invocationStep.argument,
                expectation: WaitStep(predicate: predicateResult.predicate, timeout: timeoutResult.timeout)
            ),
            heistDefinitions: heistDefinitions,
            explicitExpectationTimeout: timeoutResult.explicitTimeout,
            expectationValidationDiagnostics: validationDiagnostics
        )
    }

    func expect(timeout: Double? = nil) -> HeistInvocationContent {
        expect(.change(.elements()), timeout: timeout)
    }

    @_disfavoredOverload
    func expect(
        _ predicate: AccessibilityPredicate,
        timeout: Double? = nil
    ) -> HeistInvocationContent {
        expect(.predicate(predicate), timeout: timeout)
    }
}

private struct HeistDefinitionBuildError: Error, Sendable, CustomStringConvertible {
    let diagnostics: [HeistBuildDiagnostic]

    var description: String {
        "heist definition build failed: \(diagnostics.renderedMessages)"
    }
}

public extension HeistDef where Input == Void {
    func callAsFunction() throws -> HeistInvocationContent {
        try invocation(argument: .none)
    }
}

extension HeistDef: HeistContent {
    public var heistSteps: [HeistStep] { [] }

    public var heistDefinitions: [HeistPlan] {
        definitionResult.value.map { [$0] } ?? []
    }

    public var heistBuildDiagnostics: [HeistBuildDiagnostic] {
        definitionResult.failureDiagnostics ?? []
    }
}

public extension HeistDef where Input == String {
    func callAsFunction(_ input: String) throws -> HeistInvocationContent {
        try invocation(argument: .string(.literal(input)))
    }

    func callAsFunction(_ input: StringExpr) throws -> HeistInvocationContent {
        try invocation(argument: .string(input))
    }
}

public extension HeistDef where Input == ElementTarget {
    func callAsFunction(_ input: ElementTarget) throws -> HeistInvocationContent {
        try invocation(argument: .elementTarget(.target(input)))
    }

    func callAsFunction(_ input: ElementTargetExpr) throws -> HeistInvocationContent {
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
public func RunHeist(_ name: String) -> HeistInvocationContent {
    runHeistInvocation(name, argument: .none)
}

public func RunHeist(_ name: String, _ input: String) -> HeistInvocationContent {
    runHeistInvocation(name, argument: .string(.literal(input)))
}

public func RunHeist(_ name: String, _ input: StringExpr) -> HeistInvocationContent {
    runHeistInvocation(name, argument: .string(input))
}

@_disfavoredOverload
public func RunHeist(_ name: String, _ input: ElementTarget) -> HeistInvocationContent {
    runHeistInvocation(name, argument: .elementTarget(.target(input)))
}

public func RunHeist(_ name: String, _ input: ElementTargetExpr) -> HeistInvocationContent {
    runHeistInvocation(name, argument: .elementTarget(input))
}

private func runHeistInvocation(_ name: String, argument: HeistArgument) -> HeistInvocationContent {
    do {
        return HeistInvocationContent(
            invocation: HeistInvocationStep(
                invocationPath: try HeistInvocationPath(dottedName: name),
                argument: argument
            ),
            heistDefinitions: []
        )
    } catch {
        return HeistInvocationContent(invalidDiagnostics: [.dslBuild(
            code: .dslInvalidInvocationPath,
            path: name.isEmpty ? nil : name,
            message: "RunHeist name is invalid: \(String(describing: error))",
            hint: "Use a non-empty dot-separated heist capability name with no empty components."
        )])
    }
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
    public let heistBuildDiagnostics: [HeistBuildDiagnostic]

    public init(
        _ values: [String],
        parameter: HeistReferenceName = "item",
        @HeistBuilder content: (StringExpr) throws -> Content
    ) {
        do {
            let parameter = try HeistParameterName.normalized(parameter.rawValue)
            let reference = HeistReferenceName(rawValue: parameter)
            let item = try StringExpr(ref: reference)
            let content = try content(item)
            let step = try ForEachStringStep(
                values: values,
                parameter: reference,
                body: content.heistSteps
            )
            self.heistSteps = [.forEachString(step)]
            self.heistDefinitions = content.heistDefinitions
            self.heistBuildDiagnostics = content.heistBuildDiagnostics
        } catch {
            self.heistSteps = []
            self.heistDefinitions = []
            self.heistBuildDiagnostics = [.dslBuild(
                code: .dslInvalidForEachString,
                message: "ForEach string loop is invalid: \(String(describing: error))"
            )]
        }
    }

    public init(
        _ first: String,
        _ rest: String...,
        parameter: HeistReferenceName = "item",
        @HeistBuilder content: (StringExpr) throws -> Content
    ) {
        self.init([first] + rest, parameter: parameter, content: content)
    }

    public init(
        _ matches: ElementMatches,
        limit: Int = 20,
        parameter: HeistReferenceName = "target",
        @HeistBuilder _ content: (ElementTargetExpr) throws -> Content
    ) {
        do {
            let parameter = try HeistParameterName.normalized(parameter.rawValue)
            let reference = HeistReferenceName(rawValue: parameter)
            let target = try ElementTargetExpr(ref: reference)
            let content = try content(target)
            let step = try ForEachElementStep(
                matching: matches.predicate,
                limit: limit,
                parameter: reference,
                body: content.heistSteps
            )
            self.heistSteps = [.forEachElement(step)]
            self.heistDefinitions = content.heistDefinitions
            self.heistBuildDiagnostics = content.heistBuildDiagnostics
        } catch {
            self.heistSteps = []
            self.heistDefinitions = []
            self.heistBuildDiagnostics = [.dslBuild(
                code: .dslInvalidForEachElement,
                message: "ForEach element loop is invalid: \(String(describing: error))"
            )]
        }
    }

    public init(
        _ predicate: ElementPredicate,
        limit: Int = 20,
        parameter: HeistReferenceName = "target",
        @HeistBuilder _ content: (ElementTargetExpr) throws -> Content
    ) {
        self.init(.matching(predicate), limit: limit, parameter: parameter, content)
    }
}

private extension Array where Element == HeistBuildDiagnostic {
    var renderedMessages: String {
        map(\.renderedMessage).joined(separator: "; ")
    }
}
