import Foundation

// ThePlans ownership map:
// - HeistPlan.swift owns recursive plan structure, Codable, definition merging, and root admission.
// - HeistPlanParameters.swift owns plan parameters and invocation arguments.
// - HeistStep.swift owns the step discriminator enum and step-level wire shape.
// - ActionStep.swift owns action step payloads.
// - WaitStep.swift owns wait step payloads and resolved wait helpers.
// - ControlSteps.swift owns conditional and predicate-case step payloads.
// - LoopSteps.swift owns collection loop step payloads.
// - HeistInvocationStep.swift owns named heist invocation payloads.
// - WarnFailSteps.swift owns warning and failure step payloads.
// - Runtime safety extensions own the bounded executable-plan boundary.
// - HeistPlan+Validation.swift owns linting and composition-quality checks only.
// - HeistSourceCompilation/Lexer/Parser.swift owns canonical ButtonHeist source compilation.
// - HeistSwiftFileCompilation.swift owns authored Swift-file compilation.
// - HeistPlan+CanonicalSwiftDSL.swift owns canonical Swift DSL rendering.
// - HeistArtifact.swift owns .heist package read/write.
// - HeistPlan+Discovery.swift and HeistPlan+Description.swift own discovery and description.

/// Canonical ordered automation contract.
///
/// Swift DSL source, runtime ButtonHeist source, generated artifact payloads,
/// and run-heist all converge on this value.
public struct HeistPlan: Codable, Sendable, Equatable {
    public static let currentVersion = 2

    public let version: Int
    public let name: HeistPlanName?
    public let parameter: HeistParameter
    public let definitions: [HeistPlan]
    public let body: [HeistStep]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, name, parameter, definitions, body
    }

    public init(
        version: Int = HeistPlan.currentVersion,
        name: HeistPlanName? = nil,
        parameter: HeistParameter = .none,
        definitions: [HeistPlan] = [],
        body: [HeistStep]
    ) throws {
        let plan = try HeistPlan(
            stackVersion: version,
            name: name,
            parameter: parameter,
            definitions: definitions,
            body: body
        )
        do {
            var validator = HeistPlanRuntimeSafetyValidator(limits: .standard)
            try validator.validate(plan)
            self = plan
        } catch let error as HeistPlanRuntimeSafetyError {
            throw HeistPlanBuildError(diagnostics: error.diagnostics)
        }
    }

    public init(from decoder: Decoder) throws {
        let decoded = try DecodedHeistPlan(from: decoder)
        let plan = try decoded.admitStructure()
        do {
            var validator = HeistPlanRuntimeSafetyValidator(limits: .standard)
            try validator.validate(plan)
            self = plan
        } catch let error as HeistPlanRuntimeSafetyError {
            throw HeistPlanBuildError(diagnostics: error.diagnostics)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(name, forKey: .name)
        if parameter != .none {
            try container.encode(parameter, forKey: .parameter)
        }
        if !definitions.isEmpty {
            try container.encode(definitions, forKey: .definitions)
        }
        try container.encode(body, forKey: .body)
    }

    fileprivate init(
        stackVersion version: Int,
        name: HeistPlanName? = nil,
        parameter: HeistParameter = .none,
        definitions: [HeistPlan] = [],
        body: [HeistStep]
    ) throws {
        guard version == Self.currentVersion else {
            throw HeistPlanVersionAdmissionError(observed: version)
        }
        guard !body.isEmpty || !definitions.isEmpty else {
            throw HeistPlanBuildError.planStructure(
                path: "$.body",
                message: "heist plan must contain a body or nested definitions",
                hint: "Add body steps, or use this plan only as a namespace with nested definitions."
            )
        }
        self.version = version
        self.name = name
        self.parameter = parameter
        self.definitions = definitions
        self.body = body
    }
}

extension HeistPlan {
    enum DefinitionDuplicatePolicy: Equatable {
        case preserve
        case discardIdentical
    }

    static func mergeDefinitions(
        _ definitions: [HeistPlan],
        duplicatePolicy: DefinitionDuplicatePolicy
    ) throws -> [HeistPlan] {
        try definitions.reduce(into: []) { merged, definition in
            guard let definitionName = definition.name,
                  let existingIndex = merged.firstIndex(where: { $0.name == definitionName })
            else {
                merged.append(definition)
                return
            }

            let existing = merged[existingIndex]
            if duplicatePolicy == .discardIdentical, existing == definition {
                return
            }
            guard existing.isNamespaceFragment, definition.isNamespaceFragment else {
                merged.append(definition)
                return
            }
            do {
                merged[existingIndex] = try HeistPlan(
                    version: existing.version,
                    name: existing.name,
                    parameter: existing.parameter,
                    definitions: try mergeDefinitions(
                        existing.definitions + definition.definitions,
                        duplicatePolicy: duplicatePolicy
                    ),
                    body: existing.body
                )
            } catch let error as HeistPlanBuildError {
                let prefix = "$.definitions[\(existingIndex)]"
                throw HeistPlanBuildError(diagnostics: error.diagnostics.map { diagnostic in
                    guard let path = diagnostic.path, path.hasPrefix("$") else {
                        return diagnostic
                    }
                    return diagnostic.withPath(prefix + String(path.dropFirst()))
                })
            }
        }
    }

    static func nestedDefinition(
        path: HeistDefinitionPath,
        parameter: HeistParameter,
        definitions: [HeistPlan],
        body: [HeistStep]
    ) throws -> HeistPlan {
        try nestedDefinition(
            components: path.components[...],
            parameter: parameter,
            definitions: definitions,
            body: body
        )
    }

    private static func nestedDefinition(
        components: ArraySlice<HeistPlanName>,
        parameter: HeistParameter,
        definitions: [HeistPlan],
        body: [HeistStep]
    ) throws -> HeistPlan {
        guard let first = components.first else {
            preconditionFailure("validated heist definition path must not be empty")
        }
        guard components.count > 1 else {
            return try HeistPlan(
                version: currentVersion,
                name: first,
                parameter: parameter,
                definitions: definitions,
                body: body
            )
        }
        return try HeistPlan(
            version: currentVersion,
            name: first,
            definitions: [
                nestedDefinition(
                    components: components.dropFirst(),
                    parameter: parameter,
                    definitions: definitions,
                    body: body
                ),
            ],
            body: []
        )
    }

    private var isNamespaceFragment: Bool {
        parameter == .none && body.isEmpty && !definitions.isEmpty
    }
}

package struct HeistPlanVersionAdmissionError: Error, Sendable, Equatable, CustomStringConvertible {
    package let observed: Int

    package var description: String {
        "unsupported heist plan version \(observed); this build supports version \(HeistPlan.currentVersion)"
    }
}

private struct DecodedHeistPlan: Decodable {
    let version: Int
    let name: HeistPlanName?
    let parameter: HeistParameter
    let definitions: [DecodedHeistPlan]
    let body: [DecodedHeistStep]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, name, parameter, definitions, body
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist plan")
        name = try container.decodeIfPresent(HeistPlanName.self, forKey: .name)
        parameter = try container.decodeIfPresent(HeistParameter.self, forKey: .parameter) ?? .none
        definitions = try container.decodeIfPresent([DecodedHeistPlan].self, forKey: .definitions) ?? []
        body = try container.decode([DecodedHeistStep].self, forKey: .body)
        guard !body.isEmpty || !definitions.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .body,
                in: container,
                debugDescription: "HeistPlan requires a non-empty body or definitions"
            )
        }
    }

    func admitStructure() throws -> HeistPlan {
        try HeistPlan(
            stackVersion: version,
            name: name,
            parameter: parameter,
            definitions: definitions.map { try $0.admitStructure() },
            body: body.map { try $0.admitStructure() }
        )
    }
}

private indirect enum DecodedHeistStep: Decodable {
    case action(ActionStep)
    case wait(
        predicate: AccessibilityPredicate,
        timeout: WaitTimeout,
        elseBody: [DecodedHeistStep]?
    )
    case conditional(
        cases: [DecodedPredicateCase],
        elseBody: [DecodedHeistStep]?
    )
    case forEachElement(
        matching: ElementPredicate,
        limit: Int,
        parameter: HeistReferenceName,
        body: [DecodedHeistStep]
    )
    case forEachString(
        values: [String],
        parameter: HeistReferenceName,
        body: [DecodedHeistStep]
    )
    case repeatUntil(
        predicate: AccessibilityPredicate,
        timeout: WaitTimeout,
        body: [DecodedHeistStep]
    )
    case warn(WarnStep)
    case fail(FailStep)
    case heist(DecodedHeistPlan)
    case invoke(HeistInvocationStep)

    private enum WaitCodingKeys: String, CodingKey, CaseIterable {
        case predicate, timeout
        case elseBody = "else_body"
    }

    private enum ConditionalCodingKeys: String, CodingKey, CaseIterable {
        case cases
        case elseBody = "else_body"
    }

    private enum ForEachElementCodingKeys: String, CodingKey, CaseIterable {
        case matching, limit, parameter, body
    }

    private enum ForEachStringCodingKeys: String, CodingKey, CaseIterable {
        case values, parameter, body
    }

    private enum RepeatUntilCodingKeys: String, CodingKey, CaseIterable {
        case predicate, timeout, body
    }

    init(from decoder: Decoder) throws {
        let envelope = try HeistStepTaggedEnvelope(from: decoder)
        switch envelope.type {
        case .action:
            self = .action(try envelope.decode(ActionStep.self))
        case .wait:
            self = try Self.decodeWait(from: envelope.payloadDecoder())
        case .conditional:
            self = try Self.decodeConditional(from: envelope.payloadDecoder())
        case .forEachElement:
            self = try Self.decodeForEachElement(from: envelope.payloadDecoder())
        case .forEachString:
            self = try Self.decodeForEachString(from: envelope.payloadDecoder())
        case .repeatUntil:
            self = try Self.decodeRepeatUntil(from: envelope.payloadDecoder())
        case .warn:
            self = .warn(try envelope.decode(WarnStep.self))
        case .fail:
            self = .fail(try envelope.decode(FailStep.self))
        case .heist:
            self = .heist(try envelope.decode(DecodedHeistPlan.self))
        case .invoke:
            self = .invoke(try envelope.decode(HeistInvocationStep.self))
        }
    }

    func admitStructure() throws -> HeistStep {
        switch self {
        case .action(let step):
            return .action(step)
        case .wait(let predicate, let timeout, let elseBody):
            return .wait(WaitStep(
                predicate: predicate,
                timeout: timeout,
                elseBody: try elseBody?.map { try $0.admitStructure() }
            ))
        case .conditional(let cases, let elseBody):
            return .conditional(try ConditionalStep(
                cases: try cases.map { try $0.admitStructure() },
                elseBody: try elseBody?.map { try $0.admitStructure() }
            ))
        case .forEachElement(let matching, let limit, let parameter, let body):
            return .forEachElement(try ForEachElementStep(
                matching: matching,
                limit: limit,
                parameter: parameter,
                body: body.map { try $0.admitStructure() }
            ))
        case .forEachString(let values, let parameter, let body):
            return .forEachString(try ForEachStringStep(
                values: values,
                parameter: parameter,
                body: body.map { try $0.admitStructure() }
            ))
        case .repeatUntil(let predicate, let timeout, let body):
            return .repeatUntil(try RepeatUntilStep(
                predicate: predicate,
                timeout: timeout,
                body: body.map { try $0.admitStructure() }
            ))
        case .warn(let step):
            return .warn(step)
        case .fail(let step):
            return .fail(step)
        case .heist(let plan):
            return .heist(try plan.admitStructure())
        case .invoke(let step):
            return .invoke(step)
        }
    }

    private static func decodeWait(from decoder: Decoder) throws -> Self {
        try decoder.rejectUnknownKeys(allowed: WaitCodingKeys.self, typeName: "wait step")
        let container = try decoder.container(keyedBy: WaitCodingKeys.self)
        return .wait(
            predicate: try container.decode(AccessibilityPredicate.self, forKey: .predicate),
            timeout: try container.decode(WaitTimeout.self, forKey: .timeout),
            elseBody: try container.decodeIfPresent([DecodedHeistStep].self, forKey: .elseBody)
        )
    }

    private static func decodeConditional(from decoder: Decoder) throws -> Self {
        try decoder.rejectUnknownKeys(allowed: ConditionalCodingKeys.self, typeName: "conditional step")
        let container = try decoder.container(keyedBy: ConditionalCodingKeys.self)
        return .conditional(
            cases: try container.decode([DecodedPredicateCase].self, forKey: .cases),
            elseBody: try container.decodeIfPresent([DecodedHeistStep].self, forKey: .elseBody)
        )
    }

    private static func decodeForEachElement(from decoder: Decoder) throws -> Self {
        try decoder.rejectUnknownKeys(allowed: ForEachElementCodingKeys.self, typeName: "for_each_element step")
        let container = try decoder.container(keyedBy: ForEachElementCodingKeys.self)
        return .forEachElement(
            matching: try container.decode(ElementPredicate.self, forKey: .matching),
            limit: try container.decode(Int.self, forKey: .limit),
            parameter: try HeistReferenceName.decode(
                from: container,
                forKey: .parameter,
                type: "for_each_element parameter"
            ),
            body: try container.decode([DecodedHeistStep].self, forKey: .body)
        )
    }

    private static func decodeForEachString(from decoder: Decoder) throws -> Self {
        try decoder.rejectUnknownKeys(allowed: ForEachStringCodingKeys.self, typeName: "for_each_string step")
        let container = try decoder.container(keyedBy: ForEachStringCodingKeys.self)
        return .forEachString(
            values: try container.decode([String].self, forKey: .values),
            parameter: try HeistReferenceName.decode(
                from: container,
                forKey: .parameter,
                type: "for_each_string parameter"
            ),
            body: try container.decode([DecodedHeistStep].self, forKey: .body)
        )
    }

    private static func decodeRepeatUntil(from decoder: Decoder) throws -> Self {
        try decoder.rejectUnknownKeys(allowed: RepeatUntilCodingKeys.self, typeName: "repeat_until step")
        let container = try decoder.container(keyedBy: RepeatUntilCodingKeys.self)
        return .repeatUntil(
            predicate: try container.decode(AccessibilityPredicate.self, forKey: .predicate),
            timeout: try container.decode(WaitTimeout.self, forKey: .timeout),
            body: try container.decode([DecodedHeistStep].self, forKey: .body)
        )
    }
}

private struct DecodedPredicateCase: Decodable {
    let predicate: ChangeDeclaration.ScreenAssertion
    let body: [DecodedHeistStep]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case predicate, body
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "predicate case")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        predicate = try container.decode(ChangeDeclaration.ScreenAssertion.self, forKey: .predicate)
        body = try container.decode([DecodedHeistStep].self, forKey: .body)
    }

    func admitStructure() throws -> PredicateCase {
        PredicateCase(
            predicate: predicate,
            body: try body.map { try $0.admitStructure() }
        )
    }
}
