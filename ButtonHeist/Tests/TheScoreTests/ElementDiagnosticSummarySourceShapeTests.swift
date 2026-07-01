import ButtonHeistTestSupport
import Foundation
import Testing

@Suite struct ElementDiagnosticSummarySourceShapeTests {
    private let repository = SourceShapeRepository(filePath: #filePath)

    @Test func `element diagnostics render from one typed summary value`() throws {
        let summary = try repository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheScore/ElementDiagnosticSummary.swift"
        )
        let actionCapability = try repository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/TheBrains/ActionCapabilityDiagnostic.swift"
        )
        let stashDiagnostics = try repository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/TheStash/Diagnostics.swift"
        )
        let targetResolution = try repository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheInsideJob/TheStash/TheStash+TargetResolutionDiagnostics.swift"
        )
        let failureDiagnostics = try repository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheScore/HeistFailureDiagnostics.swift"
        )

        try summary.requireDeclarations([
            .structure("ElementDiagnosticSummary", conformingTo: ["Equatable", "Sendable"]),
            .structure("RenderProfile", conformingTo: ["Equatable", "Sendable"]),
        ])

        #expect(summary.contents.contains("package let label: String?"))
        #expect(summary.contents.contains("package let identifier: String?"))
        #expect(summary.contents.contains("package let value: String?"))
        #expect(summary.contents.contains("package let traits: [HeistTrait]"))
        #expect(summary.contents.contains("package let availability: Availability?"))
        #expect(summary.contents.contains("package let liveObjectState: String?"))
        #expect(summary.contents.contains("fileprivate let includesGeometry: Bool"))
        #expect(summary.contents.contains("fileprivate let includesAvailability: Bool"))
        #expect(summary.contents.contains("fileprivate let includesLiveObjectState: Bool"))

        #expect(actionCapability.contents.contains("ElementDiagnosticSummary("))
        #expect(stashDiagnostics.contents.contains("ElementDiagnosticSummary("))
        #expect(targetResolution.contents.contains("ElementDiagnosticSummary("))
        #expect(failureDiagnostics.contents.contains("ElementDiagnosticSummary("))
    }

    @Test func `diagnostic files do not reintroduce local quote or list helpers`() throws {
        let files = try [
            "ButtonHeist/Sources/TheInsideJob/TheBrains/ActionCapabilityDiagnostic.swift",
            "ButtonHeist/Sources/TheInsideJob/TheStash/Diagnostics.swift",
            "ButtonHeist/Sources/TheInsideJob/TheStash/TheStash+TargetResolutionDiagnostics.swift",
            "ButtonHeist/Sources/TheScore/HeistFailureDiagnostics.swift",
        ].map { try repository.requiredFile(relativePath: $0) }

        let helperDeclarationPattern = #"\b(?:static\s+)?func\s+(?:quote|quotedString|formatList|formatQuotedList)\s*\("#
        for file in files {
            let helperDeclarations = try file.lines(matching: helperDeclarationPattern)
            #expect(
                helperDeclarations.isEmpty,
                """
                \(file.relativePath) should use ElementDiagnosticSummary.RenderProfile \
                instead of local quote/list helpers:
                \(helperDeclarations.joined(separator: "\n"))
                """
            )
        }
    }
}
