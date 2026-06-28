import Foundation
import Testing

@Suite struct TheFenceRequestPayloadSourceTests {

    @Test func `get interface matcher fields are typed at the request boundary`() throws {
        let source = try sourceFile(
            relativePath: "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+RequestPayload+Observation.swift"
        )

        #expect(source.contains("private enum InterfaceElementMatcherField: CaseIterable"))

        for forbidden in [
            #"argumentValues["checks"]"#,
            #"argumentValues["label"]"#,
            #"argumentValues["identifier"]"#,
            #"argumentValues["value"]"#,
            #"argumentValues["traits"]"#,
            #"argumentValues["excludeTraits"]"#,
            #"schemaStringMatches("label")"#,
            #"schemaStringMatches("identifier")"#,
            #"schemaStringMatches("value")"#,
            #"schemaStringArray("traits")"#,
            #"schemaStringArray("excludeTraits")"#,
        ] {
            #expect(
                !source.contains(forbidden),
                "get_interface matcher parsing should use InterfaceElementMatcherField instead of \(forbidden)"
            )
        }
    }
}

private func sourceFile(relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
