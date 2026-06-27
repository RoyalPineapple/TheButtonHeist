#if canImport(UIKit)
#if DEBUG
@_exported import ButtonHeistDSL
import TheInsideJob

struct HeistRunRequest: Equatable {
    let plan: HeistPlan
    let argument: HeistArgument
}

@MainActor
@discardableResult
public func runHeist<Content: HeistContent>(
    _ name: String,
    @HeistBuilder _ content: @escaping () throws -> Content
) async throws -> Heist {
    let request = try makeRunHeistRequest(name, content)
    return try await Heist(request.plan, argument: request.argument)
}

func makeRunHeistRequest<Content: HeistContent>(
    _ name: String,
    @HeistBuilder _ content: @escaping () throws -> Content
) throws -> HeistRunRequest {
    guard shouldWrapDottedCapability(name) else {
        return HeistRunRequest(
            plan: try HeistPlan(name, content),
            argument: .none
        )
    }
    let definition = HeistDef<Void>(name, content)
    return HeistRunRequest(
        plan: try HeistPlan {
            try definition()
        },
        argument: .none
    )
}

@MainActor
@discardableResult
public func runHeist<Content: HeistContent>(
    _ name: String,
    argument input: String,
    parameter: HeistReferenceName = "input",
    @HeistBuilder _ content: @escaping (StringExpr) throws -> Content
) async throws -> Heist {
    let request = try makeRunHeistRequest(
        name,
        argument: input,
        parameter: parameter,
        content
    )
    return try await Heist(request.plan, argument: request.argument)
}

func makeRunHeistRequest<Content: HeistContent>(
    _ name: String,
    argument input: String,
    parameter: HeistReferenceName = "input",
    @HeistBuilder _ content: @escaping (StringExpr) throws -> Content
) throws -> HeistRunRequest {
    guard shouldWrapDottedCapability(name) else {
        return HeistRunRequest(
            plan: try HeistPlan(name, parameter: parameter, content),
            argument: .string(.literal(input))
        )
    }
    let definition = HeistDef<String>(name, parameter: parameter, content)
    return HeistRunRequest(
        plan: try HeistPlan(parameter: parameter) { input in
            try definition(input)
        },
        argument: .string(.literal(input))
    )
}

@_disfavoredOverload
@MainActor
@discardableResult
public func runHeist<Content: HeistContent>(
    _ name: String,
    argument input: ElementTarget,
    parameter: HeistReferenceName = "input",
    @HeistBuilder _ content: @escaping (ElementTargetExpr) throws -> Content
) async throws -> Heist {
    try await runHeist(
        name,
        argument: .target(input),
        parameter: parameter,
        content
    )
}

@_disfavoredOverload
func makeRunHeistRequest<Content: HeistContent>(
    _ name: String,
    argument input: ElementTarget,
    parameter: HeistReferenceName = "input",
    @HeistBuilder _ content: @escaping (ElementTargetExpr) throws -> Content
) throws -> HeistRunRequest {
    try makeRunHeistRequest(
        name,
        argument: .target(input),
        parameter: parameter,
        content
    )
}

@MainActor
@discardableResult
public func runHeist<Content: HeistContent>(
    _ name: String,
    argument input: ElementTargetExpr,
    parameter: HeistReferenceName = "input",
    @HeistBuilder _ content: @escaping (ElementTargetExpr) throws -> Content
) async throws -> Heist {
    let request = try makeRunHeistRequest(
        name,
        argument: input,
        parameter: parameter,
        content
    )
    return try await Heist(request.plan, argument: request.argument)
}

func makeRunHeistRequest<Content: HeistContent>(
    _ name: String,
    argument input: ElementTargetExpr,
    parameter: HeistReferenceName = "input",
    @HeistBuilder _ content: @escaping (ElementTargetExpr) throws -> Content
) throws -> HeistRunRequest {
    let target = try input.resolve(in: .empty)
    guard shouldWrapDottedCapability(name) else {
        return HeistRunRequest(
            plan: try HeistPlan(name, targetParameter: parameter, content),
            argument: .elementTarget(.target(target))
        )
    }
    let definition = HeistDef<ElementTarget>(name, parameter: parameter, content)
    return HeistRunRequest(
        plan: try HeistPlan(targetParameter: parameter) { target in
            try definition(target)
        },
        argument: .elementTarget(.target(target))
    )
}

private func shouldWrapDottedCapability(_ name: String) -> Bool {
    name.split(separator: ".").count > 1
}
#endif // DEBUG
#endif // canImport(UIKit)
