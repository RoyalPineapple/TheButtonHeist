import Foundation

public struct HeistContent: Sendable {
    let steps: [HeistStep]
    let definitions: [HeistPlanAdmissionCandidate]
    let diagnostics: [HeistBuildDiagnostic]

    init(
        _ steps: [HeistStep] = [],
        definitions: [HeistPlanAdmissionCandidate] = [],
        diagnostics: [HeistBuildDiagnostic] = []
    ) {
        self.steps = steps
        self.definitions = definitions
        self.diagnostics = diagnostics
    }
}

public extension HeistPlan {
    init(@HeistBuilder _ content: () throws -> HeistContent) throws {
        try self.init(dslName: nil, content)
    }

    init(
        _ name: HeistPlanName,
        @HeistBuilder _ content: () throws -> HeistContent
    ) throws {
        try self.init(dslName: name, content)
    }

    init(
        parameter: HeistReferenceName,
        @HeistBuilder _ content: (HeistReferenceName) throws -> HeistContent
    ) throws {
        let reference = parameter
        try self.init(dslName: nil, rootParameter: .string(name: reference)) {
            try content(reference)
        }
    }

    init(
        _ name: HeistPlanName,
        parameter: HeistReferenceName,
        @HeistBuilder _ content: (HeistReferenceName) throws -> HeistContent
    ) throws {
        let reference = parameter
        try self.init(dslName: name, rootParameter: .string(name: reference)) {
            try content(reference)
        }
    }

    init(
        targetParameter: HeistReferenceName,
        @HeistBuilder _ content: (AccessibilityTarget) throws -> HeistContent
    ) throws {
        let reference = targetParameter
        try self.init(dslName: nil, rootParameter: .accessibilityTarget(name: reference)) {
            try content(AccessibilityTarget(ref: reference))
        }
    }

    init(
        _ name: HeistPlanName,
        targetParameter: HeistReferenceName,
        @HeistBuilder _ content: (AccessibilityTarget) throws -> HeistContent
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
        _ content: () throws -> HeistContent
    ) throws {
        let content = try content()
        try Self.throwIfBuildDiagnostics(content.diagnostics)
        self = try Self.validatedDSLPlan(
            name: name,
            definitions: content.definitions,
            body: content.steps
        )
    }

    init(
        dslName name: HeistPlanName?,
        rootParameter parameter: HeistParameter,
        _ content: () throws -> HeistContent
    ) throws {
        let content = try content()
        try Self.throwIfBuildDiagnostics(content.diagnostics)
        guard !content.steps.isEmpty || !content.definitions.isEmpty else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [HeistPlanCodingKey("body")],
                debugDescription: "HeistPlan requires a non-empty body or definitions"
            ))
        }
        self = try HeistPlanAdmissionCandidate(
            name: name,
            parameter: parameter,
            definitions: content.definitions,
            body: content.steps.map(HeistStepAdmissionCandidate.init)
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

@resultBuilder
public enum HeistBuilder {
    public static func buildExpression(_ expression: HeistContent) -> HeistContent {
        expression
    }

    public static func buildExpression(_ expression: HeistStep) -> HeistContent {
        HeistContent([expression])
    }

    public static func buildExpression(_ expression: HeistPlan) -> HeistContent {
        HeistContent(
            expression.body,
            definitions: expression.definitions.map(HeistPlanAdmissionCandidate.init)
        )
    }

    public static func buildExpression(_ expression: Action) -> HeistContent {
        expression.heistContent
    }

    public static func buildExpression(_ expression: Action.Repeated) -> HeistContent {
        expression.heistContent
    }

    public static func buildExpression(_ expression: WaitFor) -> HeistContent {
        expression.heistContent
    }

    public static func buildExpression(_ expression: RepeatUntil) -> HeistContent {
        expression.heistContent
    }

    public static func buildExpression(_ expression: IfContent) -> HeistContent {
        expression.heistContent
    }

    public static func buildExpression(_ expression: Warn) -> HeistContent {
        expression.heistContent
    }

    public static func buildExpression(_ expression: Fail) -> HeistContent {
        expression.heistContent
    }

    public static func buildExpression(_ expression: HeistInvocationContent) -> HeistContent {
        expression.heistContent
    }

    public static func buildExpression<Input>(_ expression: HeistDef<Input>) -> HeistContent {
        expression.heistContent
    }

    public static func buildExpression(_ expression: ForEach) -> HeistContent {
        expression.heistContent
    }

    public static func buildBlock(_ components: HeistContent...) -> HeistContent {
        HeistContent(
            components.flatMap(\.steps),
            definitions: mergeDefinitions(components.flatMap(\.definitions)),
            diagnostics: components.flatMap(\.diagnostics)
        )
    }

    private static func mergeDefinitions(
        _ definitions: [HeistPlanAdmissionCandidate]
    ) -> [HeistPlanAdmissionCandidate] {
        mergeHeistDefinitions(definitions, duplicatePolicy: .discardIdentical)
    }
}

public struct HeistDef<Input>: Sendable {
    let path: HeistDefinitionPath
    let parameter: HeistParameter
    private let content: HeistContent

    public init(
        _ path: HeistDefinitionPath,
        @HeistBuilder _ content: @escaping () throws -> HeistContent
    ) where Input == Void {
        self.parameter = .none
        self.path = path
        self.content = Self.definitionContent(path: path, parameter: self.parameter) {
            try content()
        }
    }

    public init(
        _ path: HeistDefinitionPath,
        parameter: HeistReferenceName = "input",
        @HeistBuilder _ content: @escaping (HeistReferenceName) throws -> HeistContent
    ) where Input == String {
        let reference = parameter
        self.parameter = .string(name: reference)
        self.path = path
        self.content = Self.definitionContent(path: path, parameter: self.parameter) {
            try content(reference)
        }
    }

    public init(
        _ path: HeistDefinitionPath,
        parameter: HeistReferenceName = "input",
        @HeistBuilder _ content: @escaping (AccessibilityTarget) throws -> HeistContent
    ) where Input == AccessibilityTarget {
        let reference = parameter
        self.parameter = .accessibilityTarget(name: reference)
        self.path = path
        self.content = Self.definitionContent(path: path, parameter: self.parameter) {
            try content(AccessibilityTarget(ref: reference))
        }
    }

    private static func definitionContent(
        path: HeistDefinitionPath,
        parameter: HeistParameter,
        _ content: () throws -> HeistContent
    ) -> HeistContent {
        let renderedPath = path.description
        do {
            let content = try content()
            guard content.diagnostics.isEmpty else {
                return HeistContent(diagnostics: content.diagnostics.map { $0.withPath(renderedPath) })
            }
            return HeistContent(definitions: [
                nestedHeistDefinition(
                    path: path,
                    parameter: parameter,
                    definitions: content.definitions,
                    body: content.steps.map(HeistStepAdmissionCandidate.init)
                ),
            ])
        } catch {
            return HeistContent(diagnostics: [.dslBuild(
                code: .dslInvalidDefinition,
                path: renderedPath,
                message: String(describing: error)
            )])
        }
    }

    fileprivate func invocation(argument: HeistArgument) throws -> HeistInvocationContent {
        try HeistPlan.throwIfBuildDiagnostics(content.diagnostics)
        return HeistInvocationContent(
            path: HeistInvocationPath(definitionPath: path),
            argument: argument,
            definitions: content.definitions
        )
    }
}

public struct HeistInvocationContent {
    let path: HeistInvocationPath
    let argument: HeistArgument
    let definitions: [HeistPlanAdmissionCandidate]
    let expectation: AuthoredActionExpectation

    var heistContent: HeistContent {
        HeistContent(
            [.invoke(HeistInvocationStep(
                path: path,
                argument: argument,
                expectation: expectation.waitStep
            ))],
            definitions: definitions,
            diagnostics: expectation.diagnostics.map {
                HeistBuildDiagnostic.dslBuild(
                    code: .dslInvalidInvocationExpectation,
                    path: path.description,
                    message: $0.message,
                    hint: $0.hint
                )
            }
        )
    }

    init(
        path: HeistInvocationPath,
        argument: HeistArgument,
        definitions: [HeistPlanAdmissionCandidate],
        expectation: AuthoredActionExpectation = .default
    ) {
        self.path = path
        self.argument = argument
        self.definitions = definitions
        self.expectation = expectation
    }
}

public extension HeistInvocationContent {
    func expect(
        _ predicate: AccessibilityPredicate,
        timeout: WaitTimeout? = nil
    ) -> HeistInvocationContent {
        return HeistInvocationContent(
            path: path,
            argument: argument,
            definitions: definitions,
            expectation: expectation.appending(predicate, timeout: timeout)
        )
    }
}

public extension HeistDef where Input == Void {
    func callAsFunction() throws -> HeistInvocationContent {
        try invocation(argument: .none)
    }
}

extension HeistDef {
    var heistContent: HeistContent {
        content
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
        path: path,
        argument: argument,
        definitions: []
    )
}
public struct ForEach {
    let heistContent: HeistContent

    private init(
        values: [String],
        parameter: HeistReferenceName = "item",
        @HeistBuilder content: (HeistReferenceName) throws -> HeistContent
    ) {
        do {
            let content = try content(parameter)
            let step = try ForEachStringStep(
                values: values,
                parameter: parameter,
                body: content.steps
            )
            heistContent = HeistContent(
                [.forEachString(step)],
                definitions: content.definitions,
                diagnostics: content.diagnostics
            )
        } catch {
            heistContent = HeistContent(diagnostics: [.dslBuild(
                code: .dslInvalidForEachString,
                message: "ForEach string loop is invalid: \(String(describing: error))"
            )])
        }
    }

    public init(
        _ first: String,
        _ rest: String...,
        parameter: HeistReferenceName = "item",
        @HeistBuilder content: (HeistReferenceName) throws -> HeistContent
    ) {
        self.init(values: [first] + rest, parameter: parameter, content: content)
    }

    public init(
        _ predicate: ElementPredicate,
        limit: Int = 20,
        parameter: HeistReferenceName = "target",
        @HeistBuilder _ content: (AccessibilityTarget) throws -> HeistContent
    ) {
        do {
            let target = AccessibilityTarget(ref: parameter)
            let content = try content(target)
            let step = try ForEachElementStep(
                matching: predicate,
                limit: limit,
                parameter: parameter,
                body: content.steps
            )
            heistContent = HeistContent(
                [.forEachElement(step)],
                definitions: content.definitions,
                diagnostics: content.diagnostics
            )
        } catch {
            heistContent = HeistContent(diagnostics: [.dslBuild(
                code: .dslInvalidForEachElement,
                message: "ForEach element loop is invalid: \(String(describing: error))"
            )])
        }
    }
}
