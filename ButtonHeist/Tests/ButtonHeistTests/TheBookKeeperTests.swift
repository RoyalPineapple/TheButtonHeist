import XCTest
@testable import ButtonHeist

final class TheBookKeeperTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bookkeeper-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: - Session Phase Transitions

    @ButtonHeistActor
    func testInitialPhaseIsIdle() {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        if case .idle = bookKeeper.phase {
            // expected
        } else {
            XCTFail("Expected idle phase, got \(bookKeeper.phase)")
        }
    }

    @ButtonHeistActor
    func testManifestIsNilWhenIdle() {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        XCTAssertNil(bookKeeper.manifest)
    }

    @ButtonHeistActor
    func testBeginSessionTransitionsToActive() throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-session")
        if case .active(let session) = bookKeeper.phase {
            XCTAssertTrue(session.sessionId.hasPrefix("test-session-"))
        } else {
            XCTFail("Expected active phase")
        }
    }

    @ButtonHeistActor
    func testBeginSessionCreatesDirectory() throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-dir")
        guard case .active(let session) = bookKeeper.phase else {
            return XCTFail("Expected active phase")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.directory.path))
    }

    @ButtonHeistActor
    func testBeginSessionCreatesLogFile() throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-log")
        guard case .active(let session) = bookKeeper.phase else {
            return XCTFail("Expected active phase")
        }
        let logPath = session.directory.appendingPathComponent("session.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: logPath.path))
    }

    @ButtonHeistActor
    func testCloseSessionTransitionsToClosed() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-close")
        try await bookKeeper.closeSession()
        if case .closed(let session) = bookKeeper.phase {
            XCTAssertTrue(session.sessionId.hasPrefix("test-close-"))
            XCTAssertNotNil(session.manifest.endTime)
        } else {
            XCTFail("Expected closed phase")
        }
    }

    @ButtonHeistActor
    func testCloseSessionCompressesLog() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-compress")
        // Write something so the log isn't empty
        try bookKeeper.logCommand(requestId: "r1", command: .status, arguments: [:])
        try await bookKeeper.closeSession()
        guard case .closed(let session) = bookKeeper.phase else {
            return XCTFail("Expected closed phase")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.compressedLogPath.path))
        XCTAssertTrue(session.compressedLogPath.path.hasSuffix(".jsonl.gz"))
    }

    @ButtonHeistActor
    func testArchiveSessionTransitionsToArchived() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-archive")
        try bookKeeper.logCommand(requestId: "r1", command: .status, arguments: [:])
        try await bookKeeper.closeSession()
        let archivePath = try await bookKeeper.archiveSession(deleteSource: false)
        if case .archived(let session) = bookKeeper.phase {
            XCTAssertEqual(session.archivePath, archivePath)
            XCTAssertTrue(archivePath.path.hasSuffix(".tar.gz"))
        } else {
            XCTFail("Expected archived phase")
        }
        // Clean up archive
        try? FileManager.default.removeItem(at: archivePath)
    }

    @ButtonHeistActor
    func testCloseSessionFromIdleThrows() async {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        do {
            try await bookKeeper.closeSession()
            XCTFail("Expected error")
        } catch let error as BookKeeperError {
            if case .invalidPhase = error {
                // expected
            } else {
                XCTFail("Expected invalidPhase, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @ButtonHeistActor
    func testArchiveSessionFromActiveThrows() async {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        do {
            try bookKeeper.beginSession(identifier: "test")
            _ = try await bookKeeper.archiveSession()
            XCTFail("Expected error")
        } catch let error as BookKeeperError {
            if case .invalidPhase = error {
                // expected
            } else {
                XCTFail("Expected invalidPhase, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @ButtonHeistActor
    func testBeginSessionFromActiveThrows() throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "first")
        do {
            try bookKeeper.beginSession(identifier: "second")
            XCTFail("Expected error")
        } catch let error as BookKeeperError {
            if case .invalidPhase = error {
                // expected
            } else {
                XCTFail("Expected invalidPhase, got \(error)")
            }
        }
    }

    @ButtonHeistActor
    func testNewSessionFromClosedWorks() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "first")
        try await bookKeeper.closeSession()
        try bookKeeper.beginSession(identifier: "second")
        if case .active(let session) = bookKeeper.phase {
            XCTAssertTrue(session.sessionId.hasPrefix("second-"))
        } else {
            XCTFail("Expected active phase")
        }
    }

    // MARK: - Session Log

    @ButtonHeistActor
    func testLogCommandWritesJSONLLine() throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-log")
        try bookKeeper.logCommand(
            requestId: "req-1",
            command: .activate,
            arguments: ["command": "activate", "identifier": "loginButton"]
        )
        guard case .active(let session) = bookKeeper.phase else {
            return XCTFail("Expected active phase")
        }
        let logPath = session.directory.appendingPathComponent("session.jsonl")
        let content = try String(contentsOf: logPath, encoding: .utf8)
        let lines = content.split(separator: "\n")
        XCTAssertEqual(lines.count, 1)
        let json = try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any]
        XCTAssertEqual(json?["type"] as? String, "command")
        XCTAssertEqual(json?["requestId"] as? String, "req-1")
        XCTAssertEqual(json?["command"] as? String, "activate")
        XCTAssertNotNil(json?["t"])
    }

    @ButtonHeistActor
    func testLogResponseWritesJSONLLine() throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-log-resp")
        try bookKeeper.logResponse(
            requestId: "req-1",
            status: .ok,
            durationMilliseconds: 42
        )
        guard case .active(let session) = bookKeeper.phase else {
            return XCTFail("Expected active phase")
        }
        let logPath = session.directory.appendingPathComponent("session.jsonl")
        let content = try String(contentsOf: logPath, encoding: .utf8)
        let lines = content.split(separator: "\n")
        XCTAssertEqual(lines.count, 1)
        let json = try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any]
        XCTAssertEqual(json?["type"] as? String, "response")
        XCTAssertEqual(json?["requestId"] as? String, "req-1")
        XCTAssertEqual(json?["status"] as? String, "ok")
        XCTAssertEqual(json?["duration_ms"] as? Int, 42)
    }

    @ButtonHeistActor
    func testLogResponseWithErrorIncrementsErrorCount() throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-errors")
        try bookKeeper.logResponse(requestId: "r1", status: .error, durationMilliseconds: 10, error: "boom")
        try bookKeeper.logResponse(requestId: "r2", status: .ok, durationMilliseconds: 5)
        try bookKeeper.logResponse(requestId: "r3", status: .error, durationMilliseconds: 8, error: "bang")
        XCTAssertEqual(bookKeeper.manifest?.errorCount, 2)
    }

    @ButtonHeistActor
    func testLogCommandIncrementsCommandCount() throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-count")
        try bookKeeper.logCommand(requestId: "r1", command: .status, arguments: [:])
        try bookKeeper.logCommand(requestId: "r2", command: .activate, arguments: [:])
        try bookKeeper.logCommand(requestId: "r3", command: .scroll, arguments: [:])
        XCTAssertEqual(bookKeeper.manifest?.commandCount, 3)
    }

    @ButtonHeistActor
    func testBinaryDataExcludedFromLog() throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-binary")
        let fakePngData = String(repeating: "A", count: 5000)
        try bookKeeper.logCommand(
            requestId: "r1",
            command: .getScreen,
            arguments: ["command": "get_screen", "pngData": fakePngData]
        )
        guard case .active(let session) = bookKeeper.phase else {
            return XCTFail("Expected active phase")
        }
        let logPath = session.directory.appendingPathComponent("session.jsonl")
        let content = try String(contentsOf: logPath, encoding: .utf8)
        XCTAssertFalse(content.contains(fakePngData), "Binary data should not appear in log")
    }

    @ButtonHeistActor
    func testLogCommandSilentWhenIdle() throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        // Should not throw — just silently does nothing
        try bookKeeper.logCommand(requestId: "r1", command: .status, arguments: [:])
    }

    // MARK: - Manifest

    @ButtonHeistActor
    func testManifestStartsEmpty() throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-manifest")
        let manifest = bookKeeper.manifest
        XCTAssertNotNil(manifest)
        XCTAssertEqual(manifest?.artifacts.count, 0)
        XCTAssertEqual(manifest?.commandCount, 0)
        XCTAssertEqual(manifest?.errorCount, 0)
    }

    @ButtonHeistActor
    func testManifestRoundTripsAsJSON() throws {
        let manifest = SessionManifest(
            sessionId: "test-roundtrip",
            startTime: Date(timeIntervalSince1970: 1_000_000),
            endTime: Date(timeIntervalSince1970: 1_000_100),
            artifacts: [
                ArtifactEntry(
                    type: .screenshot,
                    path: "screenshots/001-get_screen.png",
                    size: 1024,
                    timestamp: Date(timeIntervalSince1970: 1_000_050),
                    requestId: "r1",
                    command: "get_screen",
                    metadata: ["width": 390.0, "height": 844.0]
                ),
            ],
            commandCount: 5,
            errorCount: 1
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionManifest.self, from: data)
        XCTAssertEqual(manifest, decoded)
    }

    // MARK: - Path Validation

    @ButtonHeistActor
    func testRejectsDoubleDotComponents() {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        XCTAssertNil(bookKeeper.validateOutputPath("../etc/passwd"))
    }

    @ButtonHeistActor
    func testRejectsEmbeddedDoubleDot() {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        XCTAssertNil(bookKeeper.validateOutputPath("foo/../../../etc/passwd"))
    }

    @ButtonHeistActor
    func testAcceptsSimpleRelativePath() {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        let result = bookKeeper.validateOutputPath("screenshot.png")
        XCTAssertNotNil(result)
    }

    @ButtonHeistActor
    func testAcceptsAbsolutePath() {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        let result = bookKeeper.validateOutputPath("/tmp/shot.png")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.path, "/tmp/shot.png")
    }

    @ButtonHeistActor
    func testRejectsEmptyPath() {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        XCTAssertNil(bookKeeper.validateOutputPath(""))
    }

    // MARK: - Artifact Storage

    @ButtonHeistActor
    func testWriteScreenshotCreatesFile() throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-screenshot")
        let testData = Data([0x89, 0x50, 0x4E, 0x47]) // PNG magic bytes
        let base64 = testData.base64EncodedString()
        let fileURL = try bookKeeper.writeScreenshot(
            base64Data: base64,
            requestId: "r1",
            command: .getScreen,
            metadata: ScreenshotMetadata(width: 390, height: 844)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(fileURL.path.contains("screenshots/"))
        XCTAssertTrue(fileURL.lastPathComponent.hasSuffix(".png"))
    }

    @ButtonHeistActor
    func testWriteScreenshotUpdatesManifest() throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-manifest-update")
        let testData = Data([0x89, 0x50, 0x4E, 0x47])
        let base64 = testData.base64EncodedString()
        _ = try bookKeeper.writeScreenshot(
            base64Data: base64,
            requestId: "r1",
            command: .getScreen,
            metadata: ScreenshotMetadata(width: 390, height: 844)
        )
        XCTAssertEqual(bookKeeper.manifest?.artifacts.count, 1)
        XCTAssertEqual(bookKeeper.manifest?.artifacts.first?.type, .screenshot)
        XCTAssertEqual(bookKeeper.manifest?.artifacts.first?.path, "screenshots/001-get_screen.png")
    }

    @ButtonHeistActor
    func testWriteRecordingCreatesFile() throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-recording")
        let testData = Data([0x00, 0x00, 0x00, 0x1C]) // MP4 header bytes
        let base64 = testData.base64EncodedString()
        let fileURL = try bookKeeper.writeRecording(
            base64Data: base64,
            requestId: "r1",
            command: .stopRecording,
            metadata: RecordingMetadata(width: 390, height: 844, duration: 5.0, fps: 8, frameCount: 40)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(fileURL.path.contains("recordings/"))
        XCTAssertTrue(fileURL.lastPathComponent.hasSuffix(".mp4"))
    }

    @ButtonHeistActor
    func testSequenceNumberIncrements() throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-sequence")
        let testData = Data([0x89, 0x50, 0x4E, 0x47])
        let base64 = testData.base64EncodedString()
        let first = try bookKeeper.writeScreenshot(
            base64Data: base64, requestId: "r1", command: .getScreen,
            metadata: ScreenshotMetadata(width: 390, height: 844)
        )
        let second = try bookKeeper.writeScreenshot(
            base64Data: base64, requestId: "r2", command: .getScreen,
            metadata: ScreenshotMetadata(width: 390, height: 844)
        )
        XCTAssertTrue(first.lastPathComponent.hasPrefix("001-"))
        XCTAssertTrue(second.lastPathComponent.hasPrefix("002-"))
    }

    @ButtonHeistActor
    func testWriteToPathValidatesTraversal() {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        let data = Data("test".utf8)
        XCTAssertThrowsError(try bookKeeper.writeToPath(data, outputPath: "../evil.txt")) { error in
            guard case BookKeeperError.unsafePath = error else {
                XCTFail("Expected unsafePath error, got \(error)")
                return
            }
        }
    }

    @ButtonHeistActor
    func testWriteToPathSucceeds() throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        let data = Data("hello".utf8)
        let outputPath = tempDirectory.appendingPathComponent("output.txt").path
        let resultURL = try bookKeeper.writeToPath(data, outputPath: outputPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resultURL.path))
        let readBack = try Data(contentsOf: resultURL)
        XCTAssertEqual(readBack, data)
    }

    @ButtonHeistActor
    func testBase64DecodingFailureThrows() throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-bad-b64")
        XCTAssertThrowsError(
            try bookKeeper.writeScreenshot(
                base64Data: "not-valid-base64!!!",
                requestId: "r1",
                command: .getScreen,
                metadata: ScreenshotMetadata(width: 390, height: 844)
            )
        ) { error in
            guard case BookKeeperError.base64DecodingFailed = error else {
                XCTFail("Expected base64DecodingFailed, got \(error)")
                return
            }
        }
    }
}
