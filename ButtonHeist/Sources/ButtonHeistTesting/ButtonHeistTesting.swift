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
}

@MainActor
@discardableResult
public func runHeist(
    _ path: HeistDefinitionPath,
    @HeistBuilder _ content: @escaping () throws -> HeistContent
) async throws -> Heist {
    let request = try makeRunHeistRequest(path, content)
    return try await Heist(request.plan, argument: request.argument)
}

/// Runs a prebuilt in-process heist plan through the app-hosted test runtime.
@MainActor
@discardableResult
public func runHeist(
    _ plan: HeistPlan,
    argument: HeistArgument = .none
) async throws -> Heist {
    try await Heist(plan, argument: argument)
}

func makeRunHeistRequest(
    _ path: HeistDefinitionPath,
    @HeistBuilder _ content: @escaping () throws -> HeistContent
) throws -> HeistRunRequest {
    let definition = HeistDef<Void>(path, content)
    return HeistRunRequest(
        plan: try HeistPlan { try definition() },
        argument: .none
    )
}

@MainActor
@discardableResult
public func runHeist(
    _ path: HeistDefinitionPath,
    argument input: String,
    parameter: HeistReferenceName = "input",
    @HeistBuilder _ content: @escaping (HeistReferenceName) throws -> HeistContent
) async throws -> Heist {
    let request = try makeRunHeistRequest(
        path,
        argument: input,
        parameter: parameter,
        content
    )
    return try await Heist(request.plan, argument: request.argument)
}

func makeRunHeistRequest(
    _ path: HeistDefinitionPath,
    argument input: String,
    parameter: HeistReferenceName = "input",
    @HeistBuilder _ content: @escaping (HeistReferenceName) throws -> HeistContent
) throws -> HeistRunRequest {
    HeistRunRequest(
        plan: try makeRunHeistPlan(path, parameter: parameter, content: content),
        argument: .string(input)
    )
}

@_disfavoredOverload
@MainActor
@discardableResult
public func runHeist(
    _ path: HeistDefinitionPath,
    argument input: AccessibilityTarget,
    parameter: HeistReferenceName = "input",
    @HeistBuilder _ content: @escaping (AccessibilityTarget) throws -> HeistContent
) async throws -> Heist {
    let request = try makeRunHeistRequest(
        path,
        argument: input,
        parameter: parameter,
        content
    )
    return try await Heist(request.plan, argument: request.argument)
}

@_disfavoredOverload
func makeRunHeistRequest(
    _ path: HeistDefinitionPath,
    argument input: AccessibilityTarget,
    parameter: HeistReferenceName = "input",
    @HeistBuilder _ content: @escaping (AccessibilityTarget) throws -> HeistContent
) throws -> HeistRunRequest {
    let plan = try makeRunHeistPlan(path, targetParameter: parameter, content: content)
    return HeistRunRequest(
        plan: plan,
        argument: .accessibilityTarget(input)
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
