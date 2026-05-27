import ButtonHeist
import XCTest

final class CommandReferenceTests: XCTestCase {

    func testCommandReferenceMarkdownMatchesFenceDescriptors() throws {
        let expected = FenceCommandReference.commandMarkdown()
        let actual = try readRepositoryFile("docs/reference/commands.md")

        XCTAssertEqual(
            actual,
            expected,
            "docs/reference/commands.md must be regenerated from FenceCommandReference.commandMarkdown()"
        )
    }

    func testMCPReferenceMarkdownMatchesToolContracts() throws {
        let expected = FenceCommandReference.mcpMarkdown()
        let actual = try readRepositoryFile("docs/reference/mcp-tools.md")

        XCTAssertEqual(
            actual,
            expected,
            "docs/reference/mcp-tools.md must be regenerated from FenceCommandReference.mcpMarkdown()"
        )
    }

    func testAPIReferenceDoesNotCarryHandWrittenCLICommandTables() throws {
        let api = try readRepositoryFile("docs/API.md")

        XCTAssertTrue(api.contains("[Command Reference](reference/commands.md)"))
        XCTAssertTrue(api.contains("[MCP Tool Reference](reference/mcp-tools.md)"))
        XCTAssertFalse(
            api.contains("### buttonheist "),
            "docs/API.md should point to generated command reference instead of hand-written CLI command tables"
        )
    }

    func testGeneratedReferenceDoesNotExposeDescriptionFallbacks() throws {
        let commandReference = FenceCommandReference.commandMarkdown()
        let mcpReference = FenceCommandReference.mcpMarkdown()
        let fallbackNeedle = "missing a public description"
        let prototypeNeedle = "Execute the "

        XCTAssertFalse(
            commandReference.contains(fallbackNeedle),
            "Command descriptors must provide product-language public descriptions"
        )
        XCTAssertFalse(
            commandReference.contains(prototypeNeedle),
            "Command descriptors must not expose prototype fallback prose"
        )
        XCTAssertFalse(
            mcpReference.contains(fallbackNeedle),
            "MCP tool descriptors must provide product-language public descriptions"
        )
        XCTAssertFalse(
            mcpReference.contains(prototypeNeedle),
            "MCP tool descriptors must not expose prototype fallback prose"
        )
    }

    private func readRepositoryFile(_ path: String) throws -> String {
        let url = try repositoryRoot().appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func repositoryRoot() throws -> URL {
        var current = URL(fileURLWithPath: #filePath)
        while current.path != "/" {
            let candidate = current.appendingPathComponent("docs/API.md")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return current
            }
            current.deleteLastPathComponent()
        }

        throw XCTSkip("repository root unavailable from \(#filePath)")
    }
}
