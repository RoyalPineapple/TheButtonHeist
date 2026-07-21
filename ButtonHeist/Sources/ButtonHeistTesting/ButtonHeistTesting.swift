#if canImport(UIKit)
#if DEBUG
// Package contract: app-hosted tests import ButtonHeistTesting and author
// heists directly. Re-exporting ThePlans here is intentional and allowlisted by
// scripts/check-buttonheist-import-contract.sh.
@_exported import ThePlans
import TheInsideJob

/// Prepared in-process heist execution request used by the testing facade.
///
/// `runHeist` lowers Swift test code to the same validated `HeistPlan` shape as
/// external heist execution, then executes it directly through `TheInsideJob`
/// in the app process. It does not cross the `TheFence`/network boundary.
struct HeistRunRequest: Equatable, Sendable {
    let plan: HeistPlan
    let argument: HeistArgument
    let continuity: EvidenceContinuity.Reference?
}

@MainActor
@discardableResult
public func runHeist(
    _ path: HeistDefinitionPath,
    continuity: EvidenceContinuity.Reference? = nil,
    @HeistBuilder _ content: @escaping () throws -> HeistContent
) async throws -> Heist {
    let request = try makeRunHeistRequest(path, continuity: continuity, content)
    return try await Heist(
        request.plan,
        argument: request.argument,
        continuity: request.continuity
    )
}

/// Runs a prebuilt in-process heist plan through the app-hosted test runtime.
@MainActor
@discardableResult
public func runHeist(
    _ plan: HeistPlan,
    argument: HeistArgument = .none,
    continuity: EvidenceContinuity.Reference? = nil
) async throws -> Heist {
    try await Heist(plan, argument: argument, continuity: continuity)
}

func makeRunHeistRequest(
    _ path: HeistDefinitionPath,
    continuity: EvidenceContinuity.Reference? = nil,
    @HeistBuilder _ content: @escaping () throws -> HeistContent
) throws -> HeistRunRequest {
    let definition = HeistDef<Void>(path, content)
    return HeistRunRequest(
        plan: try HeistPlan { try definition() },
        argument: .none,
        continuity: continuity
    )
}

@MainActor
@discardableResult
public func runHeist(
    _ path: HeistDefinitionPath,
    argument input: String,
    parameter: HeistReferenceName = "input",
    continuity: EvidenceContinuity.Reference? = nil,
    @HeistBuilder _ content: @escaping (HeistReferenceName) throws -> HeistContent
) async throws -> Heist {
    let request = try makeRunHeistRequest(
        path,
        argument: input,
        parameter: parameter,
        continuity: continuity,
        content
    )
    return try await Heist(
        request.plan,
        argument: request.argument,
        continuity: request.continuity
    )
}

func makeRunHeistRequest(
    _ path: HeistDefinitionPath,
    argument input: String,
    parameter: HeistReferenceName = "input",
    continuity: EvidenceContinuity.Reference? = nil,
    @HeistBuilder _ content: @escaping (HeistReferenceName) throws -> HeistContent
) throws -> HeistRunRequest {
    HeistRunRequest(
        plan: try makeRunHeistPlan(path, parameter: parameter, content: content),
        argument: .string(input),
        continuity: continuity
    )
}

@_disfavoredOverload
@MainActor
@discardableResult
public func runHeist(
    _ path: HeistDefinitionPath,
    argument input: AccessibilityTarget,
    parameter: HeistReferenceName = "input",
    continuity: EvidenceContinuity.Reference? = nil,
    @HeistBuilder _ content: @escaping (AccessibilityTarget) throws -> HeistContent
) async throws -> Heist {
    let request = try makeRunHeistRequest(
        path,
        argument: input,
        parameter: parameter,
        continuity: continuity,
        content
    )
    return try await Heist(
        request.plan,
        argument: request.argument,
        continuity: request.continuity
    )
}

@_disfavoredOverload
func makeRunHeistRequest(
    _ path: HeistDefinitionPath,
    argument input: AccessibilityTarget,
    parameter: HeistReferenceName = "input",
    continuity: EvidenceContinuity.Reference? = nil,
    @HeistBuilder _ content: @escaping (AccessibilityTarget) throws -> HeistContent
) throws -> HeistRunRequest {
    let plan = try makeRunHeistPlan(path, targetParameter: parameter, content: content)
    return HeistRunRequest(
        plan: plan,
        argument: .accessibilityTarget(input),
        continuity: continuity
    )
}

private func makeRunHeistPlan(
    _ path: HeistDefinitionPath,
    parameter: HeistReferenceName,
    content: @escaping (HeistReferenceName) throws -> HeistContent
) throws -> HeistPlan {
    let definition = HeistDef<String>(path, parameter: parameter, content)
    return try HeistPlan(parameter: parameter) { input in
        try definition(input)
    }
}

private func makeRunHeistPlan(
    _ path: HeistDefinitionPath,
    targetParameter parameter: HeistReferenceName,
    content: @escaping (AccessibilityTarget) throws -> HeistContent
) throws -> HeistPlan {
    let definition = HeistDef<AccessibilityTarget>(path, parameter: parameter, content)
    return try HeistPlan(targetParameter: parameter) { target in
        try definition(target)
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
