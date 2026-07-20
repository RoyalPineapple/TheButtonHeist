import Foundation
import Testing

@testable import ThePlans

private struct AdversarialNightlyPlan: Decodable {
    let name: String
    let expectation: String
    let plan: String
}

@Test func `every adversarial nightly plan compiles through the canonical source compilation`() async throws {
    let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let script = repository.appendingPathComponent("scripts/e2e-adversarial-lab.py")
    let outcome = try await HeistCompilerProcess.Runner.shared.execute(
        HeistCompilerProcess.Command(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["python3", script.path, "--print-plan-catalog"]
        ),
        purpose: .execution
    )
    guard case .succeeded(let output) = outcome else {
        Issue.record("nightly catalog failed: \(outcome)")
        return
    }

    let plans = try JSONDecoder().decode([AdversarialNightlyPlan].self, from: output.stdout)
    #expect(plans.count == 17)
    for plan in plans {
        do {
            _ = try HeistSourceCompilation.compile(
                plan.plan,
                sourceName: "adversarial-nightly:\(plan.expectation):\(plan.name)"
            )
        } catch {
            Issue.record("\(plan.expectation) \(plan.name) failed to compile: \(error)")
        }
    }
}
