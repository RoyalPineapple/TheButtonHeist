#if canImport(UIKit)
#if DEBUG
// Package contract: app-hosted tests import ButtonHeistTesting and author
// heists directly. Re-exporting ThePlans here is intentional and allowlisted by
// scripts/check-buttonheist-import-contract.sh.
@_exported import ThePlans
import TheInsideJob

/// Prepared in-process heist execution command used by the testing facade.
///
/// `runHeist` lowers Swift test code to the same validated `HeistPlan` shape as
/// external heist execution, then executes it directly through `TheInsideJob`
/// in the app process. It does not cross the `TheFence`/network boundary.
struct HeistRunCommand: Equatable, Sendable {
    let plan: HeistPlan
    let argument: HeistArgument

    private init(plan: HeistPlan, argument: HeistArgument) {
        self.plan = plan
        self.argument = argument
    }

    init(
        _ path: HeistDefinitionPath,
        @HeistBuilder _ content: @escaping () throws -> HeistContent
    ) throws {
        let definition = HeistDef<Void>(path, content)
        self.init(
            plan: try HeistPlan { try definition() },
            argument: .none
        )
    }

    init(
        _ path: HeistDefinitionPath,
        argument input: String,
        parameter: HeistReferenceName = "input",
        @HeistBuilder _ content: @escaping (HeistReferenceName) throws -> HeistContent
    ) throws {
        let definition = HeistDef<String>(path, parameter: parameter, content)
        self.init(
            plan: try HeistPlan(parameter: parameter) { input in
                try definition(input)
            },
            argument: .string(input)
        )
    }

    @_disfavoredOverload
    init(
        _ path: HeistDefinitionPath,
        argument input: AccessibilityTarget,
        parameter: HeistReferenceName = "input",
        @HeistBuilder _ content: @escaping (AccessibilityTarget) throws -> HeistContent
    ) throws {
        let definition = HeistDef<AccessibilityTarget>(path, parameter: parameter, content)
        self.init(
            plan: try HeistPlan(targetParameter: parameter) { target in
                try definition(target)
            },
            argument: .accessibilityTarget(input)
        )
    }
}

@MainActor
@discardableResult
public func runHeist(
    _ path: HeistDefinitionPath,
    @HeistBuilder _ content: @escaping () throws -> HeistContent
) async throws -> Heist {
    let command = try HeistRunCommand(path, content)
    return try await Heist(command.plan, argument: command.argument)
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

@MainActor
@discardableResult
public func runHeist(
    _ path: HeistDefinitionPath,
    argument input: String,
    parameter: HeistReferenceName = "input",
    @HeistBuilder _ content: @escaping (HeistReferenceName) throws -> HeistContent
) async throws -> Heist {
    let command = try HeistRunCommand(
        path,
        argument: input,
        parameter: parameter,
        content
    )
    return try await Heist(command.plan, argument: command.argument)
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
    let command = try HeistRunCommand(
        path,
        argument: input,
        parameter: parameter,
        content
    )
    return try await Heist(command.plan, argument: command.argument)
}
#endif // DEBUG
#endif // canImport(UIKit)
