import Foundation

// ThePlans ownership map:
// - HeistPlan.swift owns the root runtime-validated HeistPlan type and this ownership map.
// - HeistPlanParameters.swift owns plan parameters and invocation arguments.
// - HeistStep.swift owns the step discriminator enum and step-level wire shape.
// - ActionStep.swift owns action step payloads.
// - WaitStep.swift owns wait step payloads and resolved wait helpers.
// - ControlSteps.swift owns conditional and predicate-case step payloads.
// - LoopSteps.swift owns collection loop step payloads.
// - HeistInvocationStep.swift owns named heist invocation payloads.
// - WarnFailSteps.swift owns warning and failure step payloads.
// - HeistPlanHelpers.swift owns plan model errors and helper APIs.
// - *Expressions.swift files own scoped expression/reference types.
// - Runtime safety extensions own the bounded executable-plan boundary.
// - HeistPlan+Validation.swift owns linting and composition-quality checks only.
// - HeistSourceCompilation/Lexer/Parser.swift owns canonical ButtonHeist source compilation.
// - HeistSwiftFileCompilation.swift owns authored Swift-file compilation.
// - HeistPlan+CanonicalSwiftDSL.swift owns canonical Swift DSL rendering.
// - HeistArtifact.swift owns .heist package read/write.
// - HeistPlan+Discovery.swift and HeistPlan+Description.swift own discovery and description.

// MARK: - Heist Plan

/// Canonical ordered automation contract.
///
/// Swift DSL source, runtime ButtonHeist source, generated artifact payloads,
/// and run-heist all converge on this value. DSL syntax is source authoring;
/// `HeistPlan` is the product contract executed by the runtime. The plan stores
/// semantic structure; it does not observe UI state, settle, report, compose
/// live interactions, or dispatch actions.
public struct HeistPlan: Codable, Sendable, Equatable {
    public static let currentVersion = 2

    public let version: Int
    public let name: HeistPlanName?
    public let parameter: HeistParameter
    public let definitions: [HeistPlan]
    public let body: [HeistStep]

    public init(
        version: Int = HeistPlan.currentVersion,
        name: HeistPlanName? = nil,
        parameter: HeistParameter = .none,
        definitions: [HeistPlan] = [],
        body: [HeistStep]
    ) throws {
        self = try HeistPlanAdmissionCandidate(
            version: version,
            name: name,
            parameter: parameter,
            definitions: definitions.map(HeistPlanAdmissionCandidate.init),
            body: body.map(HeistStepAdmissionCandidate.init)
        ).validatedSemantics()
    }

    public init(from decoder: Decoder) throws {
        self = try HeistPlanAdmissionCandidate(from: decoder).validatedSemantics()
    }

    public func encode(to encoder: Encoder) throws {
        try HeistPlanAdmissionCandidate(self).encode(to: encoder)
    }
}
