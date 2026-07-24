import ArgumentParser
import Foundation
import ThePlans

@main
struct HeistPlanTool: AsyncParsableCommand {
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

enum HeistPlanToolOutput {
    static func writeLine(_ line: String) {
        writeData(Data((line + "\n").utf8))
    }

    static func writeData(_ data: Data) {
        FileHandle.standardOutput.write(data)
    }
}

struct Validate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate a generated .heist package artifact."
    )

    @Argument(help: "Path to a generated .heist package artifact.")
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

    @Argument(help: "Path to a generated .heist package artifact.")
    var plan: String

    func run() throws {
        let plan = try HeistPlanIO.readValidatedPlan(from: plan)
        HeistPlanToolOutput.writeLine(try plan.canonicalSwiftDSL())
    }
}

struct Canonicalize: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "canonicalize",
        abstract: "Re-encode a .heist package artifact."
    )

    @Argument(help: "Path to a generated .heist package artifact.")
    var plan: String

    @Option(
        name: .long,
        help: "Path to write a generated .heist package."
    )
    var output: String

    func run() throws {
        let plan = try HeistPlanIO.readValidatedPlan(from: plan)
        try HeistPlanIO.writeCanonicalHeistPackage(for: plan, to: output)
    }
}

struct Compile: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compile",
        abstract: "Compile Swift DSL source into a generated .heist package."
    )

    @Argument(help: "Path to a Swift source file that imports ThePlans.")
    var source: String

    @Option(name: .long, help: "Zero-argument throwing function returning a HeistPlan.")
    var entry: String = "heist"

    @Option(name: .long, help: "Path to write a generated .heist package.")
    var output: String

    func run() async throws {
        let entrySymbol: HeistEntrySymbol
        do {
            entrySymbol = try HeistEntrySymbol(validating: entry)
        } catch {
            throw ValidationError(String(describing: error))
        }
        let plan: HeistPlan
        do {
            plan = try await HeistSwiftCompiler().compileFile(
                URL(fileURLWithPath: source),
                entry: entrySymbol
            )
        } catch let error {
            throw ValidationError(formatBuildDiagnostics(error.diagnostics))
        }
        try HeistPlanIO.writeCanonicalHeistPackage(for: plan, to: output)
    }
}

private func formatBuildDiagnostics(_ diagnostics: [HeistBuildDiagnostic]) -> String {
    diagnostics.map(\.description).joined(separator: "\n")
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

    static func writeCanonicalHeistPackage(for plan: HeistPlan, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        guard url.pathExtension.lowercased() == "heist" else {
            throw ValidationError(
                "heist-plan output must be a generated .heist package; raw .json HeistPlan IR is internal artifact content."
            )
        }
        do {
            try HeistArtifactCodec.writePlan(plan, to: url)
        } catch let error as HeistArtifactCodecError {
            throw ValidationError(error.description)
        }
    }

}
