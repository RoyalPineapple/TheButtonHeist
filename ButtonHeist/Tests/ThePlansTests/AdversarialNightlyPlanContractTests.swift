import Foundation
import Testing

import ThePlans

private struct AdversarialNightlyPlan: Decodable {
    let name: String
    let expectation: String
    let plan: String
}

@Test func `every adversarial nightly plan compiles through the canonical source compilation`() throws {
    let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let script = repository.appendingPathComponent("scripts/e2e-adversarial-lab.py")
    let process = Process()
    let standardOutput = Pipe()
    let standardError = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", script.path, "--print-plan-catalog"]
    process.standardOutput = standardOutput
    process.standardError = standardError

    try process.run()
    process.waitUntilExit()
    let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
    let errorOutput = standardError.fileHandleForReading.readDataToEndOfFile()
    let errorMessage = String(bytes: errorOutput, encoding: .utf8) ?? "<non-UTF-8 stderr>"
    #expect(
        process.terminationStatus == 0,
        "nightly catalog failed: \(errorMessage)"
    )

    let plans = try JSONDecoder().decode([AdversarialNightlyPlan].self, from: output)
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
