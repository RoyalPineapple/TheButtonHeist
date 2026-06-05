import ArgumentParser
import Foundation
import ThePlans

@main
struct HeistPlanTool: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "heist-plan",
        abstract: "Validate and convert Button Heist plans.",
        subcommands: [
            Validate.self,
            RenderSwift.self,
            Canonicalize.self,
            Compile.self,
        ]
    )
}

struct Validate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate a .heist JSON plan."
    )

    @Argument(help: "Path to the .heist JSON plan.")
    var plan: String

    func run() throws {
        _ = try HeistPlanIO.readValidatedPlan(from: plan)
    }
}

struct RenderSwift: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "render-swift",
        abstract: "Render a .heist JSON plan as canonical Swift DSL."
    )

    @Argument(help: "Path to the .heist JSON plan.")
    var plan: String

    func run() throws {
        let plan = try HeistPlanIO.readValidatedPlan(from: plan)
        print(try plan.canonicalSwiftDSL())
    }
}

struct Canonicalize: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "canonicalize",
        abstract: "Re-encode a .heist JSON plan as stable canonical JSON."
    )

    @Argument(help: "Path to the .heist JSON plan.")
    var plan: String

    @Option(name: .long, help: "Path to write canonical .heist JSON. Defaults to stdout.")
    var output: String?

    func run() throws {
        let plan = try HeistPlanIO.readValidatedPlan(from: plan)
        try HeistPlanIO.writeCanonicalJSON(for: plan, to: output)
    }
}

struct Compile: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compile",
        abstract: "Compile Swift DSL source into canonical .heist JSON."
    )

    @Argument(help: "Path to a Swift source file that imports ThePlans.")
    var source: String

    @Option(name: .long, help: "Zero-argument entry symbol returning HeistPlan.")
    var entry: String

    @Option(name: .long, help: "Path to write canonical .heist JSON.")
    var output: String

    func validate() throws {
        guard !entry.isEmpty else {
            throw ValidationError("--entry must not be empty")
        }
    }

    func run() throws {
        let plan = try HeistSourceCompiler().compileSwiftFile(
            URL(fileURLWithPath: source),
            entry: entry
        )
        try HeistPlanIO.writeCanonicalJSON(for: plan, to: output)
    }
}

enum HeistPlanIO {
    static func readValidatedPlan(from path: String) throws -> HeistPlan {
        let url = URL(fileURLWithPath: path)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ValidationError("failed to read \(path): \(error.localizedDescription)")
        }

        let plan: HeistPlan
        do {
            plan = try JSONDecoder().decode(HeistPlan.self, from: data)
        } catch {
            throw ValidationError("failed to decode \(path) as .heist JSON: \(error)")
        }
        try validate(plan)
        return plan
    }

    static func validate(_ plan: HeistPlan) throws {
        let failures = plan.runtimeAdmissionFailures()
        guard failures.isEmpty else {
            throw ValidationError("heist plan admission failed:\n\(diagnostics(for: failures))")
        }
    }

    static func canonicalJSONData(for plan: HeistPlan) throws -> Data {
        try plan.canonicalHeistJSONData()
    }

    static func writeCanonicalJSON(for plan: HeistPlan, to path: String?) throws {
        let data = try canonicalJSONData(for: plan)
        let output = data + Data([0x0A])
        if let path {
            try output.write(to: URL(fileURLWithPath: path), options: .atomic)
        } else {
            FileHandle.standardOutput.write(output)
        }
    }

    private static func diagnostics(for failures: [HeistPlanAdmissionFailure]) -> String {
        failures.map { failure in
            """
            - path: \(failure.path)
              contract: \(failure.contract)
              observed: \(failure.observed)
              correction: \(failure.correction)
            """
        }
        .joined(separator: "\n")
    }
}
