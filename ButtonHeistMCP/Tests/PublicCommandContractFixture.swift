import Foundation
@_spi(ButtonHeistTooling) import ButtonHeist

enum PublicCommandContractFixture {
    enum Mode: Equatable {
        case comparison
        case update
    }

    enum FixtureError: Error, CustomStringConvertible {
        case missing(URL)
        case empty(URL)

        var description: String {
            switch self {
            case .missing(let url):
                """
                Missing generated contract fixture at \(url.path). Run: \
                \(PublicCommandContractFixture.updateCommand)
                """
            case .empty(let url):
                """
                Generated contract fixture at \(url.path) is empty. Run: \
                \(PublicCommandContractFixture.updateCommand)
                """
            }
        }
    }

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
            .sorted { $0.command.rawValue < $1.command.rawValue }
            .map(Command.init)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        var data = try encoder.encode(Contract(commands: commands))
        data.append(0x0A)
        return data
    }

    static func mode(environment: [String: String]) -> Mode {
        guard environment["CI"] == nil,
              environment[updateEnvironmentKey] == "1" else {
            return .comparison
        }
        return .update
    }

    static func committedData(
        for renderedData: Data,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fixtureURL: URL = PublicCommandContractFixture.fileURL
    ) throws -> Data {
        switch mode(environment: environment) {
        case .comparison:
            guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
                throw FixtureError.missing(fixtureURL)
            }
            let data = try Data(contentsOf: fixtureURL)
            guard !data.isEmpty else {
                throw FixtureError.empty(fixtureURL)
            }
            return data

        case .update:
            try renderedData.write(to: fixtureURL, options: .atomic)
            return renderedData
        }
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
