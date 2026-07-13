import Foundation
@_spi(ButtonHeistTooling) import ButtonHeist

enum PublicCommandContractFixture {
    static let updateEnvironmentKey = "BUTTONHEIST_UPDATE_PUBLIC_COMMAND_CONTRACT"
    static let updateCommand = """
        BUTTONHEIST_UPDATE_PUBLIC_COMMAND_CONTRACT=1 scripts/swift-test-gate.sh \
        ButtonHeistMCP --filter ToolSyncTests.publicCommandContractMatchesCommittedDescriptorSnapshot
        """

    static var fileURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "tests/fixtures/public-cli-mcp-command-contract.json")
    }

    static func renderedData() throws -> Data {
        let commands = TheFence.Command.descriptors
            .lazy
            .filter(\.isPublicRequestContract)
            .map(Command.init)
            .sorted { $0.name < $1.name }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        var data = try encoder.encode(Contract(commands: commands))
        data.append(0x0A)
        return data
    }

    static func updateIfRequested(with data: Data) throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CI"] == nil,
              environment[updateEnvironmentKey] == "1" else { return }
        try data.write(to: fileURL, options: .atomic)
    }
}

private extension PublicCommandContractFixture {
    struct Contract: Encodable {
        let commands: [Command]
    }

    struct Command: Encodable {
        let name: String
        let exposedByCLI: Bool
        let exposedByMCP: Bool
        let description: String
        let inputSchema: HeistValue
        let mcpAnnotations: MCPAnnotations?

        init(_ descriptor: FenceCommandDescriptor) {
            name = descriptor.command.rawValue
            exposedByCLI = descriptor.cliExposure == .directCommand
            exposedByMCP = descriptor.mcpExposure == .directTool
            description = descriptor.description
            inputSchema = descriptor.inputJSONSchema
            mcpAnnotations = descriptor.mcpAnnotations.map(MCPAnnotations.init)
        }
    }

    struct MCPAnnotations: Encodable {
        let readOnlyHint: Bool?
        let idempotentHint: Bool?

        init(_ annotations: MCPToolAnnotationSpec) {
            readOnlyHint = annotations.readOnlyHint
            idempotentHint = annotations.idempotentHint
        }
    }
}
