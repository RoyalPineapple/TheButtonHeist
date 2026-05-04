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

        let staleProtocolPhrases = [
            "Protocol v6",
            "Protocol v7",
            "\"protocolVersion\":\"6",
            "\"protocolVersion\":\"7",
            "protocolVersion\":\"6",
            "protocolVersion\":\"7",
        ]

        for (path, content) in docs {
            for phrase in staleProtocolPhrases {
                XCTAssertFalse(
                    content.contains(phrase),
                    "\(path) contains stale protocol phrase '\(phrase)'; current protocol is \(protocolVersion)"
                )
            }
        }
    }

    func testObserverDocsMatchRestrictedDefault() throws {
        let docs = try readDocs(named: [
            "docs/API.md",
            "docs/AUTH.md",
            "docs/WIRE-PROTOCOL.md",
        ])

        let staleObserverPhrases = [
            "Does not require a token by default",
            "only needed if server requires INSIDEJOB_RESTRICT_WATCHERS",
            "Empty string for default open access",
            "Required when `INSIDEJOB_RESTRICT_WATCHERS=1`",
        ]

        for (path, content) in docs {
            for phrase in staleObserverPhrases {
                XCTAssertFalse(
                    content.contains(phrase),
                    "\(path) contains stale observer auth phrase '\(phrase)'"
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

    private func readDocs(named paths: [String]) throws -> [String: String] {
        let root = repositoryRoot()
        return try Dictionary(uniqueKeysWithValues: paths.map { path in
            let url = root.appendingPathComponent(path)
            let content = try String(contentsOf: url, encoding: .utf8)
            return (path, content)
        })
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
