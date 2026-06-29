import ArgumentParser
@_spi(ButtonHeistTooling) import ButtonHeist
import Foundation

@main
struct ButtonHeistDocGen: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "buttonheist-docgen",
        abstract: "Generate The Button Heist descriptor-backed reference docs.",
        discussion: """
            Generates docs/reference/commands.md and docs/reference/mcp-tools.md
            from TheFence.Command descriptors.

            Examples:
              swift run --package-path ButtonHeist buttonheist-docgen --output-dir docs/reference
              swift run --package-path ButtonHeist buttonheist-docgen --output-dir docs/reference --check
            """
    )

    @Option(name: .long, help: "Directory that contains commands.md and mcp-tools.md.")
    var outputDir: String = "docs/reference"

    @Flag(name: .long, help: "Validate committed docs are current without writing files.")
    var check = false

    func run() throws {
        let outputURL = URL(
            fileURLWithPath: (outputDir as NSString).expandingTildeInPath,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        ).standardizedFileURL
        let outputs = [
            ("commands.md", FenceCommandReference.commandMarkdown()),
            ("mcp-tools.md", FenceCommandReference.mcpMarkdown()),
        ]

        if check {
            try validate(outputs, in: outputURL)
            return
        }

        try FileManager.default.createDirectory(
            at: outputURL,
            withIntermediateDirectories: true
        )
        for (filename, contents) in outputs {
            try contents.write(
                to: outputURL.appendingPathComponent(filename),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    private func validate(
        _ outputs: [(filename: String, contents: String)],
        in outputURL: URL
    ) throws {
        var failures: [String] = []
        for (filename, contents) in outputs {
            let url = outputURL.appendingPathComponent(filename)
            guard let data = FileManager.default.contents(atPath: url.path),
                  let committed = String(data: data, encoding: .utf8)
            else {
                failures.append("\(url.path) is missing or unreadable")
                continue
            }
            if committed != contents {
                failures.append("\(url.path) is out of date")
            }
        }
        guard failures.isEmpty else {
            throw ValidationError(
                (failures + [
                    "Run: swift run --package-path ButtonHeist buttonheist-docgen --output-dir \(outputDir)",
                ]).joined(separator: "\n")
            )
        }
    }
}
