import Foundation

public protocol HeistContent {
    var heistSteps: [HeistStep] { get }
    var heistDefinitions: [HeistPlanAdmissionCandidate] { get }
    var heistBuildDiagnostics: [HeistBuildDiagnostic] { get }
}

public extension HeistContent {
    var heistDefinitions: [HeistPlanAdmissionCandidate] { [] }
    var heistBuildDiagnostics: [HeistBuildDiagnostic] { [] }
}

public extension HeistPlan {
    init(@HeistBuilder _ content: () throws -> some HeistContent) throws {
        try self.init(dslName: nil, content)
    }

    init(
        _ name: HeistPlanName,
        @HeistBuilder _ content: () throws -> some HeistContent
    ) throws {
        try self.init(dslName: name, content)
    }

    init(
        parameter: HeistReferenceName,
        @HeistBuilder _ content: (HeistReferenceName) throws -> some HeistContent
    ) throws {
        let reference = parameter
        try self.init(dslName: nil, rootParameter: .string(name: reference)) {
            try content(reference)
        }
    }

    init(
        _ name: HeistPlanName,
        parameter: HeistReferenceName,
        @HeistBuilder _ content: (HeistReferenceName) throws -> some HeistContent
    ) throws {
        let reference = parameter
        try self.init(dslName: name, rootParameter: .string(name: reference)) {
            try content(reference)
        }
    }

    init(
        targetParameter: HeistReferenceName,
        @HeistBuilder _ content: (AccessibilityTarget) throws -> some HeistContent
    ) throws {
        let reference = targetParameter
        try self.init(dslName: nil, rootParameter: .accessibilityTarget(name: reference)) {
            try content(AccessibilityTarget(ref: reference))
        }
    }

    init(
        _ name: HeistPlanName,
        targetParameter: HeistReferenceName,
        @HeistBuilder _ content: (AccessibilityTarget) throws -> some HeistContent
    ) throws {
        let reference = targetParameter
        try self.init(dslName: name, rootParameter: .accessibilityTarget(name: reference)) {
            try content(AccessibilityTarget(ref: reference))
        }
    }
}

private extension HeistPlan {
    init(
        dslName name: HeistPlanName?,
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
        dslName name: HeistPlanName?,
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
        self = try HeistPlanAdmissionCandidate(
            name: name,
            parameter: parameter,
            definitions: content.heistDefinitions,
            body: content.heistSteps.map(HeistStepAdmissionCandidate.init)
        ).validatedSemantics()
    }

    static func validatedDSLPlan(
        name: HeistPlanName? = nil,
        definitions: [HeistPlanAdmissionCandidate] = [],
        body: [HeistStep]
    ) throws -> HeistPlan {
        guard !body.isEmpty || !definitions.isEmpty else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [HeistPlanCodingKey("body")],
                debugDescription: "HeistPlan requires a non-empty body or definitions"
            ))
        }
        return try HeistPlanAdmissionCandidate(
            name: name,
            definitions: definitions,
            body: body.map(HeistStepAdmissionCandidate.init)
        ).validatedSemantics()
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
    public var heistDefinitions: [HeistPlanAdmissionCandidate] {
        definitions.map(HeistPlanAdmissionCandidate.init)
    }
}

public struct EmptyHeistContent: HeistContent {
    public let heistSteps: [HeistStep] = []
    public let heistDefinitions: [HeistPlanAdmissionCandidate] = []
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

    private static func mergeDefinitions(
        _ definitions: [HeistPlanAdmissionCandidate]
    ) -> [HeistPlanAdmissionCandidate] {
        HeistDefinitionMerger.merge(definitions, duplicatePolicy: .discardIdentical)
    }
}

struct HeistStepList: HeistContent {
    let heistSteps: [HeistStep]
    let heistDefinitions: [HeistPlanAdmissionCandidate]
    let heistBuildDiagnostics: [HeistBuildDiagnostic]

    init(
        _ heistSteps: [HeistStep],
        definitions: [HeistPlanAdmissionCandidate] = [],
        diagnostics: [HeistBuildDiagnostic] = []
    ) {
        self.heistSteps = heistSteps
        self.heistDefinitions = definitions
        self.heistBuildDiagnostics = diagnostics
    }
}

public struct HeistDef<Input>: Sendable {
    public let path: HeistDefinitionPath
    public let parameter: HeistParameter
    private let definitionResult: ValidationResult<HeistPlanAdmissionCandidate, HeistBuildDiagnostic>

    public init<Content: HeistContent>(
        _ path: HeistDefinitionPath,
        @HeistBuilder _ content: @escaping () throws -> Content
    ) where Input == Void {
        self.parameter = .none
        self.path = path
        self.definitionResult = Self.buildDefinition(path: path, parameter: self.parameter) {
            try content()
        }
    }

    public init<Content: HeistContent>(
        _ path: HeistDefinitionPath,
        parameter: HeistReferenceName = "input",
        @HeistBuilder _ content: @escaping (HeistReferenceName) throws -> Content
    ) where Input == String {
        let reference = parameter
        self.parameter = .string(name: reference)
        self.path = path
        self.definitionResult = Self.buildDefinition(path: path, parameter: self.parameter) {
            try content(reference)
        }
    }

    public init<Content: HeistContent>(
        _ path: HeistDefinitionPath,
        parameter: HeistReferenceName = "input",
        @HeistBuilder _ content: @escaping (AccessibilityTarget) throws -> Content
    ) where Input == AccessibilityTarget {
        let reference = parameter
        self.parameter = .accessibilityTarget(name: reference)
        self.path = path
        self.definitionResult = Self.buildDefinition(path: path, parameter: self.parameter) {
            try content(AccessibilityTarget(ref: reference))
        }
    }

    private static func buildDefinition(
        path: HeistDefinitionPath,
        parameter: HeistParameter,
        _ content: () throws -> any HeistContent
    ) -> ValidationResult<HeistPlanAdmissionCandidate, HeistBuildDiagnostic> {
        let renderedPath = path.description
        do {
            let content = try content()
            guard content.heistBuildDiagnostics.isEmpty else {
                return .failure(content.heistBuildDiagnostics.map { $0.withPath(renderedPath) })
            }
            return .success(makeDefinition(
                components: path.components[...],
                parameter: parameter,
                definitions: content.heistDefinitions,
                body: content.heistSteps.map(HeistStepAdmissionCandidate.init)
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
        components: ArraySlice<HeistPlanName>,
        parameter: HeistParameter,
        definitions: [HeistPlanAdmissionCandidate],
        body: [HeistStepAdmissionCandidate]
    ) -> HeistPlanAdmissionCandidate {
        guard let first = components.first else {
            preconditionFailure("validated heist definition path must not be empty")
        }
        guard components.count > 1 else {
            return HeistPlanAdmissionCandidate(
                name: first,
                parameter: parameter,
                definitions: definitions,
                body: body
            )
        }
        let child = Self.makeDefinition(
            components: components.dropFirst(),
            parameter: parameter,
            definitions: definitions,
            body: body
        )
        return HeistPlanAdmissionCandidate(
            name: first,
            definitions: [child],
            body: []
        )
    }

    fileprivate func invocation(argument: HeistArgument) throws -> HeistInvocationContent {
        let definition = try definitionResult.get(orThrow: HeistDefinitionBuildError.init(diagnostics:))
        return HeistInvocationContent(
            invocation: HeistInvocationStep(
                path: HeistInvocationPath(definitionPath: path),
                argument: argument
            ),
            heistDefinitions: [definition]
        )
    }
}

public struct HeistInvocationContent: HeistContent {
    public let invocation: HeistInvocationStep
    public let heistDefinitions: [HeistPlanAdmissionCandidate]
    let explicitExpectationTimeout: WaitTimeout?
    let expectationValidationDiagnostics: [HeistBuildDiagnostic]

    public var heistSteps: [HeistStep] {
        [.invoke(invocation)]
    }

    public var heistBuildDiagnostics: [HeistBuildDiagnostic] {
        expectationValidationDiagnostics.map {
            HeistBuildDiagnostic.dslBuild(
                code: .dslInvalidInvocationExpectation,
                path: invocation.path.description,
                message: $0.message,
                hint: $0.hint
            )
        }
    }

    init(
        invocation: HeistInvocationStep,
        heistDefinitions: [HeistPlanAdmissionCandidate],
        explicitExpectationTimeout: WaitTimeout? = nil,
        expectationValidationDiagnostics: [HeistBuildDiagnostic] = []
    ) {
        self.invocation = invocation
        self.heistDefinitions = heistDefinitions
        self.explicitExpectationTimeout = explicitExpectationTimeout
        self.expectationValidationDiagnostics = expectationValidationDiagnostics
    }
}

public extension HeistInvocationContent {
    func expect(
        _ predicate: AccessibilityPredicate,
        timeout: WaitTimeout? = nil
    ) -> HeistInvocationContent {
        let timeoutResult = composeExpectationTimeout(
            existing: invocation.expectation,
            existingExplicit: explicitExpectationTimeout,
            nextExplicit: timeout
        )
        let predicateResult = invocation.expectation.map {
            composeExpectationPredicates(existing: $0.predicate, next: predicate)
        } ?? ExpectationPredicateComposition(predicate: predicate, diagnostics: [])
        let validationDiagnostics = expectationValidationDiagnostics
            + predicateResult.diagnostics
            + timeoutResult.diagnostics

        return HeistInvocationContent(
            invocation: HeistInvocationStep(
                path: invocation.path,
                argument: invocation.argument,
                expectation: WaitStep(predicate: predicateResult.predicate, timeout: timeoutResult.timeout)
            ),
            heistDefinitions: heistDefinitions,
            explicitExpectationTimeout: timeoutResult.explicitTimeout,
            expectationValidationDiagnostics: validationDiagnostics
        )
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

    public var heistDefinitions: [HeistPlanAdmissionCandidate] {
        definitionResult.value.map { [$0] } ?? []
    }

    public var heistBuildDiagnostics: [HeistBuildDiagnostic] {
        definitionResult.failureDiagnostics ?? []
    }
}

public extension HeistDef where Input == String {
    func callAsFunction(_ input: String) throws -> HeistInvocationContent {
        try invocation(argument: .string(input))
    }

    @_disfavoredOverload
    func callAsFunction(_ reference: HeistReferenceName) throws -> HeistInvocationContent {
        try invocation(argument: .string(reference: reference))
    }
}

public extension HeistDef where Input == AccessibilityTarget {
    func callAsFunction(_ input: AccessibilityTarget) throws -> HeistInvocationContent {
        try invocation(argument: .accessibilityTarget(input))
    }
}

// MARK: - RunHeist

/// Run a named heist capability from inside a heist body.
///
/// `RunHeist` is the public Button Heist verb for composing capabilities. It
/// references a capability by name and lowers to the invocation IR; the named
/// capability must resolve within the closed plan — runtime safety enforces
/// resolution, arity, type, and non-recursion.
public func RunHeist(_ path: HeistInvocationPath) -> HeistInvocationContent {
    runHeistInvocation(path, argument: .none)
}

public func RunHeist(_ path: HeistInvocationPath, _ input: String) -> HeistInvocationContent {
    runHeistInvocation(path, argument: .string(input))
}

@_disfavoredOverload
public func RunHeist(_ path: HeistInvocationPath, _ reference: HeistReferenceName) -> HeistInvocationContent {
    runHeistInvocation(path, argument: .string(reference: reference))
}

public func RunHeist(_ path: HeistInvocationPath, _ input: AccessibilityTarget) -> HeistInvocationContent {
    runHeistInvocation(path, argument: .accessibilityTarget(input))
}

private func runHeistInvocation(_ path: HeistInvocationPath, argument: HeistArgument) -> HeistInvocationContent {
    HeistInvocationContent(
        invocation: HeistInvocationStep(
            path: path,
            argument: argument
        ),
        heistDefinitions: []
    )
}
public struct ForEach<Content: HeistContent>: HeistContent {
    public let heistSteps: [HeistStep]
    public let heistDefinitions: [HeistPlanAdmissionCandidate]
    public let heistBuildDiagnostics: [HeistBuildDiagnostic]

    private init(
        values: [String],
        parameter: HeistReferenceName = "item",
        @HeistBuilder content: (HeistReferenceName) throws -> Content
    ) {
        do {
            let content = try content(parameter)
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
        @HeistBuilder content: (HeistReferenceName) throws -> Content
    ) {
        self.init(values: [first] + rest, parameter: parameter, content: content)
    }

    public init(
        _ predicate: ElementPredicateTemplate,
        limit: Int = 20,
        parameter: HeistReferenceName = "target",
        @HeistBuilder _ content: (AccessibilityTarget) throws -> Content
    ) {
        do {
            let target = AccessibilityTarget(ref: parameter)
            let content = try content(target)
            let step = try ForEachElementStep(
                matching: predicate,
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
            self.heistBuildDiagnostics = [.dslBuild(
                code: .dslInvalidForEachElement,
                message: "ForEach element loop is invalid: \(String(describing: error))"
            )]
        }
    }
}

private extension Array where Element == HeistBuildDiagnostic {
    var renderedMessages: String {
        map(\.renderedMessage).joined(separator: "; ")
    }
}
