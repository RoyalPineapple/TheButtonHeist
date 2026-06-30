import ButtonHeistTestSupport
import Testing

@Suite struct HandoffLifecycleSourceShapeTests {
    private let repository = SourceShapeRepository(filePath: #filePath)

    @Test func `reconnect controller stores only explicit phase`() throws {
        let source = try repository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheButtonHeist/TheHandoff/HandoffReconnectController.swift"
        )
        let controller = try #require(
            try source.firstBlock(matching: #"\bfinal\s+class\s+HandoffReconnectController\b"#),
            "HandoffReconnectController should exist"
        )

        #expect(
            try controller.containsMatch(#"\bprivate\s+var\s+phase\s*:\s*HandoffReconnectPhase\b"#),
            "Reconnect intent and active runner should be represented by one phase value"
        )
        let bannedStoredState = try controller.lines(
            matching: #"\bprivate\s+var\s+(isEnabled|filter|target|runnerTask)\b"#
        )
        #expect(
            bannedStoredState.isEmpty,
            "Reconnect sidecar fields must not return:\n\(bannedStoredState.joined(separator: "\n"))"
        )
    }

    @Test func `discovery lifecycle stores only explicit phase`() throws {
        let source = try repository.requiredFile(
            relativePath: "ButtonHeist/Sources/TheButtonHeist/TheHandoff/HandoffDiscoveryLifecycle.swift"
        )
        let lifecycle = try #require(
            try source.firstBlock(matching: #"\bfinal\s+class\s+HandoffDiscoveryLifecycle\b"#),
            "HandoffDiscoveryLifecycle should exist"
        )

        #expect(
            try lifecycle.containsMatch(#"\bprivate\s+var\s+phase\s*:\s*HandoffDiscoveryPhase\b"#),
            "Discovery session, readiness, and devices should be represented by one phase value"
        )
        let bannedStoredState = try lifecycle.lines(
            matching: #"\b(private\s+var\s+discoverySession|private\(set\)\s+var\s+(discoveredDevices|isDiscovering))\b"#
        )
        #expect(
            bannedStoredState.isEmpty,
            "Discovery sidecar fields must not return:\n\(bannedStoredState.joined(separator: "\n"))"
        )
    }
}
