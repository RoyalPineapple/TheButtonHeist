import Foundation
import XCTest
import TheScore

final class DocumentationDriftTests: XCTestCase {

    func testProtocolDocsDoNotMentionStaleProtocolVersions() throws {
        let docs = try readDocs(named: [
            "docs/API.md",
            "docs/AUTH.md",
            "docs/REVIEWERS-GUIDE.md",
            "docs/USB_DEVICE_CONNECTIVITY.md",
            "docs/WIRE-PROTOCOL.md",
            "ButtonHeist/Sources/TheScore/README.md",
        ])

        // The wire envelope no longer carries a separate `protocolVersion` field —
        // only `buttonHeistVersion`. Any reference to `protocolVersion` (or to the
        // legacy SemVer wire-protocol versions v6–v9) is stale.
        let staleProtocolPhrases = [
            "Protocol v6",
            "Protocol v7",
            "Protocol v8",
            "Protocol v9",
            "\"protocolVersion\"",
            "protocolVersion\":",
        ]

        for (path, content) in docs {
            for phrase in staleProtocolPhrases {
                XCTAssertFalse(
                    content.contains(phrase),
                    "\(path) contains stale protocol phrase '\(phrase)'; current product version is \(buttonHeistVersion)"
                )
            }
        }
    }

    func testProtocolDocsDoNotMentionRemovedClientMessages() throws {
        let docs = try readDocs(named: [
            "docs/API.md",
            "docs/AUTH.md",
            "docs/WIRE-PROTOCOL.md",
            "ButtonHeist/Sources/TheScore/README.md",
        ])

        let removedClientMessagePhrases = [
            "### subscribe",
            "### unsubscribe",
            "### watch",
            "\"type\":\"subscribe\"",
            "\"type\":\"unsubscribe\"",
            "\"type\":\"watch\"",
            "WatchPayload",
            "INSIDEJOB_RESTRICT_WATCHERS",
        ]

        for (path, content) in docs {
            for phrase in removedClientMessagePhrases {
                XCTAssertFalse(
                    content.contains(phrase),
                    "\(path) documents removed client protocol phrase '\(phrase)'"
                )
            }
        }
    }

    func testWaitForDocsUseFlatElementTargetShape() throws {
        let docs = try readDocs(named: [
            "docs/API.md",
            "docs/WIRE-PROTOCOL.md",
        ])

        for (path, content) in docs {
            XCTAssertFalse(
                content.contains("| `match` | `ElementMatcher` | Predicate describing the element to wait for |"),
                "\(path) still documents the old nested wait_for match shape"
            )
            XCTAssertTrue(
                content.contains("heistId") && content.contains("label` / `identifier` / `value`"),
                "\(path) should document wait_for's flat heistId or matcher-field shape"
            )
        }
    }

    func testReleaseVersionSurfacesDoNotDuplicateManualBumps() throws {
        let releaseVersion = try readText(named: "RELEASE_VERSION").trimmingCharacters(in: .whitespacesAndNewlines)
        let apiDocs = try readText(named: "docs/API.md")
        let demoSource = try readText(named: "TestApp/Sources/DisclosureGroupingDemo.swift")

        XCTAssertEqual(
            releaseVersion,
            buttonHeistVersion,
            "RELEASE_VERSION must match TheScore.buttonHeistVersion"
        )

        XCTAssertFalse(
            apiDocs.contains(releaseVersion),
            "docs/API.md must not duplicate the current release version"
        )
        XCTAssertNil(
            apiDocs.range(
                of: #"(?m)^\*\*Version\*\*:\s*\d+\.\d+\.\d+\s*$"#,
                options: .regularExpression
            ),
            "docs/API.md CLI Reference must not carry a manually bumped release version"
        )
        XCTAssertNil(
            apiDocs.range(of: #"\b\d+\.\d+\.\d+\b"#, options: .regularExpression),
            "docs/API.md must use <semver> placeholders instead of concrete release versions"
        )

        XCTAssertFalse(
            demoSource.contains(releaseVersion),
            "DisclosureGroupingDemo must source the release version from TheScore.buttonHeistVersion"
        )
        XCTAssertNil(
            demoSource.range(
                of: #"LabeledContent\(\s*"Version"\s*,\s*value:\s*"\d+\.\d+\.\d+"\s*\)"#,
                options: .regularExpression
            ),
            "DisclosureGroupingDemo must not hardcode a release version"
        )

        if demoSource.range(of: #"LabeledContent\(\s*"Version""#, options: .regularExpression) != nil {
            XCTAssertNotNil(
                demoSource.range(
                    of: #"LabeledContent\(\s*"Version"\s*,\s*value:\s*(?:TheScore\.)?buttonHeistVersion\s*\)"#,
                    options: .regularExpression
                ),
                "DisclosureGroupingDemo Version row must use TheScore.buttonHeistVersion or be removed"
            )
        }
    }

    private func readDocs(named paths: [String]) throws -> [String: String] {
        return try Dictionary(uniqueKeysWithValues: paths.map { path in
            try (path, readText(named: path))
        })
    }

    private func readText(named path: String) throws -> String {
        let url = repositoryRoot().appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
