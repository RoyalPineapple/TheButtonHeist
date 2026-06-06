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
        abstract: "Validate a .heist package artifact or .json HeistPlan IR."
    )

    @Argument(help: "Path to a .heist package artifact or .json HeistPlan IR.")
    var plan: String

    func run() throws {
        _ = try HeistPlanIO.readValidatedPlan(from: plan)
    }
}

struct RenderSwift: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "render-swift",
        abstract: "Render a heist plan as canonical Swift DSL."
    )

    @Argument(help: "Path to a .heist package artifact or .json HeistPlan IR.")
    var plan: String

    func run() throws {
        let plan = try HeistPlanIO.readValidatedPlan(from: plan)
        print(try plan.canonicalSwiftDSL())
    }
}

struct Canonicalize: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "canonicalize",
        abstract: "Re-encode a heist plan as stable canonical JSON or a .heist package."
    )

    @Argument(help: "Path to a .heist package artifact or .json HeistPlan IR.")
    var plan: String

    @Option(name: .long, help: "Path to write .heist package or .json IR. Defaults to JSON stdout.")
    var output: String?

    func run() throws {
        let plan = try HeistPlanIO.readValidatedPlan(from: plan)
        try HeistPlanIO.writeCanonicalJSON(for: plan, to: output)
    }
}

struct Compile: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compile",
        abstract: "Compile Swift DSL source into a .heist package or .json HeistPlan IR."
    )

    @Argument(help: "Path to a Swift source file that imports ThePlans.")
    var source: String

    @Option(name: .long, help: "Zero-argument entry symbol returning HeistPlan.")
    var entry: String

    @Option(name: .long, help: "Path to write .heist package or .json HeistPlan IR.")
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
        do {
            return try HeistArtifactCodec.readPlan(from: url)
        } catch let error as HeistArtifactCodecError {
            throw ValidationError(error.description)
        } catch {
            throw ValidationError("failed to read \(path): \(error)")
        }
    }

    static func canonicalJSONData(for plan: HeistPlan) throws -> Data {
        try plan.canonicalHeistJSONData()
    }

    static func writeCanonicalJSON(for plan: HeistPlan, to path: String?) throws {
        if let path {
            let url = URL(fileURLWithPath: path)
            do {
                try HeistArtifactCodec.writePlan(plan, to: url)
            } catch let error as HeistArtifactCodecError {
                throw ValidationError(error.description)
            }
        } else {
            let output = try canonicalJSONData(for: plan) + Data([0x0A])
            FileHandle.standardOutput.write(output)
        }
    }

}
