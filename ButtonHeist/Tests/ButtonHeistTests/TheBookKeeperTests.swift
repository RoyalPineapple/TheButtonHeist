import XCTest
@testable import ButtonHeist

final class TheBookKeeperTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = TempDirectoryFixture.make(prefix: "bookkeeper-tests")
    }

    override func tearDown() {
        TempDirectoryFixture.remove(tempDirectory)
        super.tearDown()
    }

    // MARK: - Session Phase Transitions

    @ButtonHeistActor
    func testInitialPhaseIsIdle() async {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        if case .idle = bookKeeper.phase {
            // expected
        } else {
            XCTFail("Expected idle phase, got \(bookKeeper.phase)")
        }
    }

    @ButtonHeistActor
    func testManifestIsNilWhenIdle() async {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        XCTAssertNil(bookKeeper.manifest)
    }

    @ButtonHeistActor
    func testBeginSessionTransitionsToActive() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-session")
        if case .active(let session) = bookKeeper.phase {
            XCTAssertTrue(session.sessionId.hasPrefix("test-session-"))
        } else {
            XCTFail("Expected active phase")
        }
    }

    @ButtonHeistActor
    func testActiveSessionTimingDerivesFromManifest() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-active-timing")
        guard case .active(let session) = bookKeeper.phase else {
            return XCTFail("Expected active phase")
        }

        XCTAssertEqual(session.startTime, session.manifest.startTime)
        XCTAssertNil(session.manifest.endTime)
        XCTAssertHasNoStoredPhaseTimingMirrors(session)
        XCTAssertHasNoStoredPhaseIdentityMirrors(session)
    }

    @ButtonHeistActor
    func testBeginSessionCreatesDirectory() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-dir")
        guard case .active(let session) = bookKeeper.phase else {
            return XCTFail("Expected active phase")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.directory.path))
    }

    @ButtonHeistActor
    func testBeginSessionCreatesLogFile() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-log")
        guard case .active(let session) = bookKeeper.phase else {
            return XCTFail("Expected active phase")
        }
        let logPath = session.directory.appendingPathComponent("session.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: logPath.path))
    }

    @ButtonHeistActor
    func testSessionCoordinationFilesUseRestrictivePermissions() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-private-files")
        guard case .active(let activeSession) = bookKeeper.phase else {
            return XCTFail("Expected active phase")
        }

        let logPath = activeSession.directory.appendingPathComponent("session.jsonl")
        XCTAssertEqual(try posixPermissions(at: activeSession.directory), 0o700)
        XCTAssertEqual(try posixPermissions(at: logPath), 0o600)

        try bookKeeper.startHeistRecording(app: "com.test.app")
        let heistPath = activeSession.directory.appendingPathComponent("heist.jsonl")
        XCTAssertEqual(try posixPermissions(at: heistPath), 0o600)

        try await bookKeeper.closeSession()
        guard case .closed(let closedSession) = bookKeeper.phase else {
            return XCTFail("Expected closed phase")
        }
        let manifestPath = closedSession.directory.appendingPathComponent("manifest.json")
        XCTAssertEqual(try posixPermissions(at: manifestPath), 0o600)
        XCTAssertEqual(try posixPermissions(at: closedSession.compressedLogPath), 0o600)

        let (archivePath, _) = try await bookKeeper.archiveSession(deleteSource: false)
        defer { try? FileManager.default.removeItem(at: archivePath) }
        XCTAssertEqual(try posixPermissions(at: archivePath), 0o600)
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
    func testClosedSessionTimingDerivesFromManifest() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-closed-timing")
        let activeManifest = try XCTUnwrap(bookKeeper.manifest)

        try await bookKeeper.closeSession()

        guard case .closed(let session) = bookKeeper.phase else {
            return XCTFail("Expected closed phase")
        }
        let manifestEndTime = try XCTUnwrap(session.manifest.endTime)
        let manifestPath = session.directory.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestPath)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let writtenManifest = try decoder.decode(SessionManifest.self, from: manifestData)
        let snapshot = try XCTUnwrap(bookKeeper.sessionLogSnapshot())

        XCTAssertEqual(session.manifest.startTime, activeManifest.startTime)
        XCTAssertEqual(session.startTime, session.manifest.startTime)
        XCTAssertEqual(session.endTime, manifestEndTime)
        XCTAssertEqual(writtenManifest.formatVersion, session.manifest.formatVersion)
        XCTAssertEqual(writtenManifest.sessionId, session.manifest.sessionId)
        XCTAssertEqual(
            writtenManifest.startTime.timeIntervalSince1970,
            session.manifest.startTime.timeIntervalSince1970,
            accuracy: 1
        )
        XCTAssertEqual(
            try XCTUnwrap(writtenManifest.endTime).timeIntervalSince1970,
            manifestEndTime.timeIntervalSince1970,
            accuracy: 1
        )
        XCTAssertEqual(snapshot.manifest, session.manifest)
        XCTAssertHasNoStoredPhaseTimingMirrors(session)
        XCTAssertHasNoStoredPhaseIdentityMirrors(session)
    }

    func testTerminalSessionEndTimeFallsBackToStartTimeWhenManifestIsMalformed() {
        let startTime = Date(timeIntervalSince1970: 1_000_000)
        let manifest = SessionManifest(
            sessionId: "malformed",
            startTime: startTime,
            endTime: nil
        )

        let closing = ClosingSession(
            directory: tempDirectory,
            manifest: manifest
        )
        let compressedLogPath = tempDirectory.appendingPathComponent("session.jsonl.gz")
        let compressing = CompressingSession(
            closingSession: closing,
            compressionTask: Task<URL, Error> {
                compressedLogPath
            }
        )
        let closed = ClosedSession(
            directory: tempDirectory,
            compressedLogPath: compressedLogPath,
            manifest: manifest
        )
        let archived = ArchivedSession(
            archivePath: tempDirectory.appendingPathComponent("session.tar.gz"),
            manifest: manifest
        )

        XCTAssertEqual(closing.endTime, startTime)
        XCTAssertEqual(compressing.endTime, startTime)
        XCTAssertEqual(closed.endTime, startTime)
        XCTAssertEqual(archived.endTime, startTime)
    }

    func testCompressingSessionCarriesRequiredCompressionTask() async throws {
        let manifest = SessionManifest(
            sessionId: "compressing",
            startTime: Date(timeIntervalSince1970: 1_000_000),
            endTime: Date(timeIntervalSince1970: 1_000_001)
        )
        let closing = ClosingSession(
            directory: tempDirectory,
            manifest: manifest
        )
        let compressedPath = tempDirectory.appendingPathComponent("session.jsonl.gz")
        let task = Task<URL, Error> { compressedPath }

        let compressing = CompressingSession(closingSession: closing, compressionTask: task)
        let retryable = compressing.retryableSession
        let taskValue = try await compressing.compressionTask.value

        XCTAssertEqual(compressing.sessionId, closing.sessionId)
        XCTAssertHasNoStoredPhaseIdentityMirrors(closing)
        XCTAssertHasNoStoredPhaseIdentityMirrors(compressing)
        XCTAssertEqual(taskValue, compressedPath)
        XCTAssertEqual(retryable.sessionId, closing.sessionId)
        XCTAssertEqual(retryable.directory, closing.directory)
        XCTAssertEqual(retryable.manifest, closing.manifest)
    }

    @ButtonHeistActor
    func testCloseSessionCompressesLog() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-compress")
        // Write something so the log isn't empty
        try logCommand(bookKeeper, requestId: "r1", command: .status, arguments: [:])
        try await bookKeeper.closeSession()
        guard case .closed(let session) = bookKeeper.phase else {
            return XCTFail("Expected closed phase")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.compressedLogPath.path))
        XCTAssertTrue(session.compressedLogPath.path.hasSuffix(".jsonl.gz"))
    }

    @ButtonHeistActor
    func testCloseSessionCompressionFailureLeavesClosingRetryable() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-compress-retry")
        try logCommand(bookKeeper, requestId: "r1", command: .status, arguments: [:])
        guard case .active(let activeSession) = bookKeeper.phase else {
            return XCTFail("Expected active phase")
        }

        let compressedLogPath = activeSession.directory.appendingPathComponent("session.jsonl.gz")
        try Data("existing compressed log".utf8).write(to: compressedLogPath)

        do {
            try await bookKeeper.closeSession()
            XCTFail("Expected compression failure")
        } catch let error as BookKeeperError {
            guard case .compressionFailed = error else {
                return XCTFail("Expected compressionFailed, got \(error)")
            }
        }

        guard case .closing(let failedClosingSession) = bookKeeper.phase else {
            return XCTFail("Expected closing phase after failed compression")
        }
        XCTAssertEqual(failedClosingSession.sessionId, activeSession.sessionId)

        XCTAssertThrowsError(try bookKeeper.beginSession(identifier: "replacement")) { error in
            guard case BookKeeperError.invalidPhase(_, "closing") = error else {
                XCTFail("Expected invalidPhase while closing, got \(error)")
                return
            }
        }

        try FileManager.default.removeItem(at: compressedLogPath)
        try await bookKeeper.closeSession()

        guard case .closed(let closedSession) = bookKeeper.phase else {
            return XCTFail("Expected closed phase after retry")
        }
        XCTAssertEqual(closedSession.sessionId, activeSession.sessionId)
        XCTAssertEqual(closedSession.manifest, failedClosingSession.manifest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: closedSession.compressedLogPath.path))
    }

    @ButtonHeistActor
    func testArchiveSessionTransitionsToArchived() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-archive")
        try logCommand(bookKeeper, requestId: "r1", command: .status, arguments: [:])
        try await bookKeeper.closeSession()
        let (archivePath, snapshot) = try await bookKeeper.archiveSession(deleteSource: false)
        if case .archived(let session) = bookKeeper.phase {
            let manifestEndTime = try XCTUnwrap(session.manifest.endTime)
            XCTAssertEqual(session.archivePath, archivePath)
            XCTAssertEqual(session.manifest, snapshot.manifest)
            XCTAssertEqual(session.startTime, session.manifest.startTime)
            XCTAssertEqual(session.endTime, manifestEndTime)
            XCTAssertHasNoStoredPhaseTimingMirrors(session)
            XCTAssertTrue(archivePath.path.hasSuffix(".tar.gz"))
            XCTAssertEqual(snapshot.counts.commandCount, 1)
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
            // archiveSession() returns session details, but we only care about the error here.
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
    func testBeginSessionRejectsPathTraversalIdentifier() async {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        XCTAssertThrowsError(try bookKeeper.beginSession(identifier: "../../tmp/evil")) { error in
            guard case BookKeeperError.unsafePath = error else {
                XCTFail("Expected unsafePath error, got \(error)")
                return
            }
        }
    }

    @ButtonHeistActor
    func testBeginSessionRejectsEmbeddedDoubleDotIdentifier() async {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        XCTAssertThrowsError(try bookKeeper.beginSession(identifier: "session..name")) { error in
            guard case BookKeeperError.unsafePath = error else {
                XCTFail("Expected unsafePath error, got \(error)")
                return
            }
        }
    }

    @ButtonHeistActor
    func testBeginSessionRejectsSlashInIdentifier() async {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        XCTAssertThrowsError(try bookKeeper.beginSession(identifier: "foo/bar")) { error in
            guard case BookKeeperError.unsafePath = error else {
                XCTFail("Expected unsafePath error, got \(error)")
                return
            }
        }
    }

    @ButtonHeistActor
    func testBeginSessionRejectsEmptyIdentifier() async {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        XCTAssertThrowsError(try bookKeeper.beginSession(identifier: "")) { error in
            guard case BookKeeperError.unsafePath = error else {
                XCTFail("Expected unsafePath error, got \(error)")
                return
            }
        }
    }

    @ButtonHeistActor
    func testBeginSessionRejectsOptionLikeIdentifier() async {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        XCTAssertThrowsError(try bookKeeper.beginSession(identifier: "--unsafe-option=exec=echo")) { error in
            guard case BookKeeperError.unsafePath = error else {
                XCTFail("Expected unsafePath error, got \(error)")
                return
            }
        }
    }

    @ButtonHeistActor
    func testBeginSessionRejectsControlCharactersInIdentifier() async {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        XCTAssertThrowsError(try bookKeeper.beginSession(identifier: "session\nname")) { error in
            guard case BookKeeperError.unsafePath = error else {
                XCTFail("Expected unsafePath error, got \(error)")
                return
            }
        }
    }

    @ButtonHeistActor
    func testBeginSessionFromActiveThrows() async throws {
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
    func testLogCommandWritesJSONLLine() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-log")
        try logCommand(
            bookKeeper,
            requestId: "req-1",
            command: .activate,
            arguments: ["identifier": "loginButton"]
        )
        guard case .active(let session) = bookKeeper.phase else {
            return XCTFail("Expected active phase")
        }
        let lines = try sessionLogLines(for: session)
        XCTAssertEqual(lines.count, 2) // header + command
        let header = try decodeSessionLogLine(DecodedHeaderLogEntry.self, from: lines[0])
        let command = try decodeSessionLogLine(DecodedCommandLogEntry.self, from: lines[1])

        XCTAssertEqual(header.type, "header")
        XCTAssertEqual(header.formatVersion, SessionFormatVersion.current)
        XCTAssertEqual(command.type, "command")
        XCTAssertEqual(command.requestId, "req-1")
        XCTAssertEqual(command.command, "activate")
        XCTAssertFalse(command.t.isEmpty)
        XCTAssertNil(command.args)
    }

    @ButtonHeistActor
    func testLogResponseWritesJSONLLine() async throws {
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
        let lines = try sessionLogLines(for: session)
        XCTAssertEqual(lines.count, 2) // header + response
        let response = try decodeSessionLogLine(DecodedResponseLogEntry.self, from: lines[1])

        XCTAssertEqual(response.type, "response")
        XCTAssertEqual(response.requestId, "req-1")
        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(response.durationMilliseconds, 42)
    }

    @ButtonHeistActor
    func testSessionLogCountsDeriveErrorsFromResponseEvents() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-errors")
        try bookKeeper.logResponse(requestId: "r1", status: .error, durationMilliseconds: 10, error: "boom")
        try bookKeeper.logResponse(requestId: "r2", status: .ok, durationMilliseconds: 5)
        try bookKeeper.logResponse(requestId: "r3", status: .error, durationMilliseconds: 8, error: "bang")
        let snapshot = try XCTUnwrap(bookKeeper.sessionLogSnapshot())
        XCTAssertEqual(snapshot.counts.errorCount, 2)
    }

    @ButtonHeistActor
    func testSessionLogCountsDeriveCommandsFromCommandEvents() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-count")
        try logCommand(bookKeeper, requestId: "r1", command: .status, arguments: [:])
        try logCommand(bookKeeper, requestId: "r2", command: .listDevices, arguments: [:])
        try logCommand(bookKeeper, requestId: "r3", command: .getSessionState, arguments: [:])
        let snapshot = try XCTUnwrap(bookKeeper.sessionLogSnapshot())
        XCTAssertEqual(snapshot.counts.commandCount, 3)
    }

    @ButtonHeistActor
    func testSessionLogSnapshotReportsMalformedJSONLLine() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-malformed-line")
        try logCommand(bookKeeper, requestId: "r1", command: .status, arguments: [:])
        guard case .active(let session) = bookKeeper.phase else {
            return XCTFail("Expected active phase")
        }
        session.logHandle.write(Data("{not-json\n".utf8))
        try bookKeeper.logResponse(requestId: "r2", status: .error, durationMilliseconds: 5, error: "boom")

        let snapshot = try XCTUnwrap(bookKeeper.sessionLogSnapshot())
        XCTAssertEqual(snapshot.counts.commandCount, 1)
        XCTAssertEqual(snapshot.counts.errorCount, 1)
        XCTAssertTrue(snapshot.projectionStatus.isDegraded)
        XCTAssertEqual(snapshot.projectionStatus.malformedLineCount, 1)
        XCTAssertEqual(snapshot.projectionStatus.firstMalformedLineNumber, 3)
        XCTAssertNotNil(snapshot.projectionStatus.firstMalformedLineCause)
        XCTAssertEqual(snapshot.projectionStatus.malformedArtifactCount, 0)

        let json = publicJSONObject(FenceResponse.sessionLog(snapshot: snapshot))
        let projectionStatus = try XCTUnwrap(json["projectionStatus"] as? [String: Any])
        XCTAssertEqual(projectionStatus["degraded"] as? Bool, true)
        XCTAssertEqual(projectionStatus["malformedLineCount"] as? Int, 1)
        XCTAssertEqual(projectionStatus["firstMalformedLineNumber"] as? Int, 3)
        XCTAssertEqual(projectionStatus["malformedArtifactCount"] as? Int, 0)
    }

    @ButtonHeistActor
    func testLogCommandOmitsRequestArguments() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-typed-args")
        try logCommand(bookKeeper,
            requestId: "r1",
            command: .getScreen,
            arguments: ["output": "screen.png"]
        )
        guard case .active(let session) = bookKeeper.phase else {
            return XCTFail("Expected active phase")
        }
        let lines = try sessionLogLines(for: session)
        let command = try decodeSessionLogLine(DecodedCommandLogEntry.self, from: lines[1])

        XCTAssertEqual(command.command, "get_screen")
        XCTAssertNil(command.args)
    }

    @ButtonHeistActor
    func testParsedRequestExposesHeistEvidenceFields() async throws {
        let activate = try parsedRequest(
            requestId: "r1",
            command: .activate,
            arguments: ["heistId": "login_button"]
        )

        XCTAssertEqual(activate.command, .activate)
        XCTAssertEqual(activate.payload.bookKeeperElementTarget, .heistId("login_button"))
        XCTAssertNil(activate.heistEvidenceArguments["heistId"])
    }

    @ButtonHeistActor
    func testTypedTapCoordinatesUseHeistReplayKeys() async throws {
        let tap = try parsedRequest(
            requestId: "r1",
            command: .oneFingerTap,
            arguments: ["x": 10.5, "y": 20.25]
        )
        let arguments = tap.heistEvidenceArguments

        XCTAssertEqual(arguments["x"], .double(10.5))
        XCTAssertEqual(arguments["y"], .double(20.25))
        XCTAssertNil(arguments["pointX"])
        XCTAssertNil(arguments["pointY"])
    }

    @ButtonHeistActor
    func testCustomActionUsesHeistReplayActionKey() async throws {
        let action = try parsedRequest(
            requestId: "r1",
            command: .performCustomAction,
            arguments: ["label": "Row", "action": "Archive"]
        )
        let arguments = action.heistEvidenceArguments

        XCTAssertEqual(Set(arguments.keys), Set(["action"]))
        XCTAssertEqual(arguments["action"], .string("Archive"))
        XCTAssertNil(arguments["actionName"])
        XCTAssertNil(arguments["label"])
    }

    @ButtonHeistActor
    func testRotorTextRangeUsesHeistReplayKeys() async throws {
        let rotor = try parsedRequest(
            requestId: "r1",
            command: .rotor,
            arguments: [
                "heistId": "field",
                "rotor": "Words",
                "currentHeistId": "word_1",
                "currentTextStartOffset": 4,
                "currentTextEndOffset": 9,
            ]
        )
        let arguments = rotor.heistEvidenceArguments

        XCTAssertEqual(arguments["rotor"], .string("Words"))
        XCTAssertEqual(arguments["currentHeistId"], .string("word_1"))
        XCTAssertEqual(arguments["currentTextStartOffset"], .int(4))
        XCTAssertEqual(arguments["currentTextEndOffset"], .int(9))
        XCTAssertNil(arguments["currentTextRange"])
        XCTAssertNil(arguments["heistId"])
    }

    @ButtonHeistActor
    func testConnectTokenIsRedactedInSessionLog() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-connect-redaction")

        try logCommand(bookKeeper,
            requestId: "r1",
            command: .connect,
            arguments: [
                "device": "127.0.0.1:1455",
                "token": "user-specified-token",
            ]
        )

        guard case .active(let session) = bookKeeper.phase else {
            return XCTFail("Expected active phase")
        }
        let content = try sessionLogContent(for: session)
        let lines = content.split(separator: "\n")
        let command = try decodeSessionLogLine(DecodedCommandLogEntry.self, from: lines[1])

        XCTAssertNil(command.args)
        XCTAssertFalse(content.contains("user-specified-token"))
    }

    @ButtonHeistActor
    func testRunBatchConnectTokenIsRedactedInSessionLog() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-batch-connect-redaction")

        try logCommand(bookKeeper,
            requestId: "r1",
            command: .runBatch,
            arguments: [
                "steps": [
                    [
                        "command": "connect",
                        "device": "127.0.0.1:1455",
                        "token": "nested-user-token",
                    ],
                ],
            ]
        )

        guard case .active(let session) = bookKeeper.phase else {
            return XCTFail("Expected active phase")
        }
        let content = try sessionLogContent(for: session)
        let lines = content.split(separator: "\n")
        let command = try decodeSessionLogLine(DecodedCommandLogEntry.self, from: lines[1])

        XCTAssertNil(command.args)
        XCTAssertFalse(content.contains("nested-user-token"))
    }

    @ButtonHeistActor
    func testUnexpectedLogArgumentIsRejectedByFenceSchema() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-schema-reject")

        XCTAssertThrowsError(try logCommand(
            bookKeeper,
            requestId: "r1",
            command: .activate,
            arguments: ["label": "Submit", "metadata": Data([0x01])]
        )) { error in
            let validation = error as? SchemaValidationError
            XCTAssertEqual(validation?.field, "metadata")
        }
    }

    @ButtonHeistActor
    func testNestedTypedValuesRemainStructuredInHeistEvidenceArguments() async throws {
        let request = try parsedRequest(
            requestId: "r1",
            command: .waitForChange,
            arguments: [
                "timeout": 2.5,
                "expect": [
                    "type": "element_appeared",
                    "matcher": [
                        "label": "Submit",
                        "traits": ["button"],
                    ],
                    "required": true,
                ],
            ]
        )

        let arguments = request.heistEvidenceArguments

        XCTAssertEqual(arguments["expect"], .object([
            "type": .string("element_appeared"),
            "matcher": .object([
                "label": .string("Submit"),
                "traits": .array([.string("button")]),
            ]),
        ]))
        XCTAssertEqual(arguments["timeout"], .double(2.5))
    }

    @ButtonHeistActor
    func testUnsupportedLogArgumentIsRejectedByFenceSchema() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-unsupported-log")

        XCTAssertThrowsError(try logCommand(
            bookKeeper,
            requestId: "r1",
            command: .typeText,
            arguments: ["metadata": Data([0x01, 0x02])]
        )) { error in
            let validation = error as? SchemaValidationError
            XCTAssertEqual(validation?.field, "metadata")
        }
    }

    @ButtonHeistActor
    func testLogCommandSilentWhenIdle() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        // Should not throw — just silently does nothing
        try logCommand(bookKeeper, requestId: "r1", command: .status, arguments: [:])
    }

    // MARK: - Manifest

    @ButtonHeistActor
    func testManifestStartsEmpty() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-manifest")
        let manifest = bookKeeper.manifest
        XCTAssertNotNil(manifest)
        XCTAssertEqual(manifest?.formatVersion, SessionFormatVersion.current)
        let snapshot = try XCTUnwrap(bookKeeper.sessionLogSnapshot())
        XCTAssertEqual(snapshot.artifacts, [])
    }

    @ButtonHeistActor
    func testManifestRoundTripsAsJSON() async throws {
        let manifest = SessionManifest(
            sessionId: "test-roundtrip",
            startTime: Date(timeIntervalSince1970: 1_000_000),
            endTime: Date(timeIntervalSince1970: 1_000_100)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(encoded.contains("commandCount"))
        XCTAssertFalse(encoded.contains("errorCount"))
        XCTAssertFalse(encoded.contains("artifacts"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionManifest.self, from: data)
        XCTAssertEqual(manifest, decoded)
    }

    // MARK: - Path Validation

    @ButtonHeistActor
    func testRejectsDoubleDotComponents() async {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        XCTAssertNil(bookKeeper.validateOutputPath("../etc/passwd"))
    }

    @ButtonHeistActor
    func testRejectsEmbeddedDoubleDot() async {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        XCTAssertNil(bookKeeper.validateOutputPath("foo/../../../etc/passwd"))
    }

    @ButtonHeistActor
    func testRejectsControlCharactersInOutputPath() async {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        XCTAssertNil(bookKeeper.validateOutputPath("screenshots/bad\nname.png"))
    }

    @ButtonHeistActor
    func testAcceptsSimpleRelativePath() async {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        let result = bookKeeper.validateOutputPath("screenshot.png")
        XCTAssertNotNil(result)
    }

    @ButtonHeistActor
    func testAcceptsAbsolutePath() async {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        let result = bookKeeper.validateOutputPath("/tmp/shot.png")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.path, "/tmp/shot.png")
    }

    @ButtonHeistActor
    func testRejectsEmptyPath() async {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        XCTAssertNil(bookKeeper.validateOutputPath(""))
    }

    // MARK: - Artifact Storage

    @ButtonHeistActor
    func testWriteScreenshotCreatesFile() async throws {
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
    func testWriteScreenshotIndexesArtifactInSessionLog() async throws {
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
        let snapshot = try XCTUnwrap(bookKeeper.sessionLogSnapshot())
        let artifact = try XCTUnwrap(snapshot.artifacts.first)
        XCTAssertEqual(snapshot.artifacts.count, 1)
        XCTAssertEqual(artifact.type, .screenshot)
        XCTAssertEqual(artifact.path, "screenshots/001-get_screen.png")
    }

    @ButtonHeistActor
    func testWriteRecordingCreatesFile() async throws {
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
    func testSequenceNumberIncrements() async throws {
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
    func testWriteToPathValidatesTraversal() async {
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
    func testWriteToPathSucceeds() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        let data = Data("hello".utf8)
        let outputPath = tempDirectory.appendingPathComponent("output.txt").path
        let resultURL = try bookKeeper.writeToPath(data, outputPath: outputPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resultURL.path))
        let readBack = try Data(contentsOf: resultURL)
        XCTAssertEqual(readBack, data)
    }

    @ButtonHeistActor
    func testBase64DecodingFailureThrows() async throws {
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

    // MARK: - Session Log Integration

    @ButtonHeistActor
    func testLogCommandAndResponseProduceCorrelatedEntries() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-correlation")
        try logCommand(bookKeeper, requestId: "req-42", command: .getScreen, arguments: ["command": "get_screen"])
        try bookKeeper.logResponse(
            requestId: "req-42",
            status: .ok,
            durationMilliseconds: 120
        )
        guard case .active(let session) = bookKeeper.phase else {
            return XCTFail("Expected active phase")
        }
        let lines = try sessionLogLines(for: session)
        XCTAssertEqual(lines.count, 3) // header + command + response

        let commandEntry = try decodeSessionLogLine(DecodedCommandLogEntry.self, from: lines[1])
        let responseEntry = try decodeSessionLogLine(DecodedResponseLogEntry.self, from: lines[2])

        XCTAssertEqual(commandEntry.requestId, "req-42")
        XCTAssertEqual(commandEntry.type, "command")
        XCTAssertEqual(responseEntry.requestId, "req-42")
        XCTAssertEqual(responseEntry.type, "response")
        XCTAssertNil(responseEntry.artifact)
        XCTAssertEqual(responseEntry.durationMilliseconds, 120)
    }

    @ButtonHeistActor
    func testLogResponseDoesNotTrackArtifactPath() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-response-artifact-log")
        try bookKeeper.logResponse(
            requestId: "r1",
            status: .ok,
            durationMilliseconds: 50
        )
        guard case .active(let session) = bookKeeper.phase else {
            return XCTFail("Expected active phase")
        }
        let lines = try sessionLogLines(for: session)
        XCTAssertEqual(lines.count, 2) // header + response
        let response = try decodeSessionLogLine(DecodedResponseLogEntry.self, from: lines[1])
        XCTAssertNil(response.artifact)
        XCTAssertFalse(lines[1].contains("artifact"))
    }

    @ButtonHeistActor
    func testWriteRecordingIndexesArtifactMetadataInSessionLog() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-rec-manifest")
        let testData = Data([0x00, 0x00, 0x00, 0x1C])
        let base64 = testData.base64EncodedString()
        _ = try bookKeeper.writeRecording(
            base64Data: base64,
            requestId: "r1",
            command: .stopRecording,
            metadata: RecordingMetadata(width: 393, height: 852, duration: 12.5, fps: 8, frameCount: 100)
        )
        let snapshot = try XCTUnwrap(bookKeeper.sessionLogSnapshot())
        let artifact = try XCTUnwrap(snapshot.artifacts.first)
        XCTAssertEqual(artifact.type, .recording)
        XCTAssertEqual(artifact.path, "recordings/001-stop_recording.mp4")
        XCTAssertEqual(artifact.metadata["width"], 393.0)
        XCTAssertEqual(artifact.metadata["height"], 852.0)
        XCTAssertEqual(artifact.metadata["duration"], 12.5)
        XCTAssertEqual(artifact.metadata["fps"], 8.0)
        XCTAssertEqual(artifact.metadata["frameCount"], 100.0)
    }

    @ButtonHeistActor
    func testMixedArtifactsShareSequenceCounter() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-mixed-seq")
        let pngData = Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString()
        let mp4Data = Data([0x00, 0x00, 0x00, 0x1C]).base64EncodedString()

        let screenshot = try bookKeeper.writeScreenshot(
            base64Data: pngData, requestId: "r1", command: .getScreen,
            metadata: ScreenshotMetadata(width: 390, height: 844)
        )
        let recording = try bookKeeper.writeRecording(
            base64Data: mp4Data, requestId: "r2", command: .stopRecording,
            metadata: RecordingMetadata(width: 390, height: 844, duration: 5.0, fps: 8, frameCount: 40)
        )
        let screenshot2 = try bookKeeper.writeScreenshot(
            base64Data: pngData, requestId: "r3", command: .getScreen,
            metadata: ScreenshotMetadata(width: 390, height: 844)
        )

        XCTAssertTrue(screenshot.lastPathComponent.hasPrefix("001-"))
        XCTAssertTrue(recording.lastPathComponent.hasPrefix("002-"))
        XCTAssertTrue(screenshot2.lastPathComponent.hasPrefix("003-"))
        let snapshot = try XCTUnwrap(bookKeeper.sessionLogSnapshot())
        XCTAssertEqual(snapshot.artifacts.count, 3)
    }

    // MARK: - Archive Deletion

    @ButtonHeistActor
    func testArchiveSessionDeleteSourceRemovesDirectory() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-archive-delete")
        try logCommand(bookKeeper, requestId: "r1", command: .status, arguments: [:])
        guard case .active(let activeSession) = bookKeeper.phase else {
            return XCTFail("Expected active phase")
        }
        let sessionDirectory = activeSession.directory
        try await bookKeeper.closeSession()
        let (archivePath, archiveSnapshot) = try await bookKeeper.archiveSession(deleteSource: true)

        XCTAssertTrue(FileManager.default.fileExists(atPath: archivePath.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: sessionDirectory.path),
            "Source directory should be removed when deleteSource is true"
        )
        XCTAssertEqual(archiveSnapshot.counts.commandCount, 1)
        let snapshot = try XCTUnwrap(bookKeeper.sessionLogSnapshot())
        XCTAssertEqual(snapshot.counts.commandCount, 1)
        try? FileManager.default.removeItem(at: archivePath)
    }

    @ButtonHeistActor
    func testArchiveSnapshotReportsMalformedArtifactEntry() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "test-bad-artifact")
        let testData = Data([0x89, 0x50, 0x4E, 0x47])
        _ = try bookKeeper.writeScreenshot(
            base64Data: testData.base64EncodedString(),
            requestId: "r1",
            command: .getScreen,
            metadata: ScreenshotMetadata(width: 390, height: 844)
        )
        guard case .active(let session) = bookKeeper.phase else {
            return XCTFail("Expected active phase")
        }
        let malformedArtifact: [String: Any] = [
            "type": "artifact",
            "artifactType": "screenshot",
            "size": 4,
            "t": "2026-01-01T00:00:00.000Z",
            "requestId": "bad",
            "command": "get_screen",
        ]
        var malformedArtifactData = try JSONSerialization.data(withJSONObject: malformedArtifact, options: [.sortedKeys])
        malformedArtifactData.append(contentsOf: [0x0A])
        session.logHandle.write(malformedArtifactData)

        try await bookKeeper.closeSession()
        let (archivePath, archiveSnapshot) = try await bookKeeper.archiveSession(deleteSource: false)
        defer { try? FileManager.default.removeItem(at: archivePath) }

        XCTAssertEqual(archiveSnapshot.artifacts.count, 1)
        XCTAssertEqual(archiveSnapshot.artifacts.first?.path, "screenshots/001-get_screen.png")
        XCTAssertTrue(archiveSnapshot.projectionStatus.isDegraded)
        XCTAssertEqual(archiveSnapshot.projectionStatus.malformedLineCount, 0)
        XCTAssertEqual(archiveSnapshot.projectionStatus.malformedArtifactCount, 1)

        let json = publicJSONObject(FenceResponse.archiveResult(path: archivePath.path, snapshot: archiveSnapshot))
        XCTAssertEqual(json["artifactCount"] as? Int, 1)
        let projectionStatus = try XCTUnwrap(json["projectionStatus"] as? [String: Any])
        XCTAssertEqual(projectionStatus["degraded"] as? Bool, true)
        XCTAssertEqual(projectionStatus["malformedLineCount"] as? Int, 0)
        XCTAssertEqual(projectionStatus["malformedArtifactCount"] as? Int, 1)

        let human = FenceResponse.archiveResult(path: archivePath.path, snapshot: archiveSnapshot).humanFormatted()
        XCTAssertTrue(human.contains("Projection: degraded"))
        XCTAssertTrue(human.contains("malformed artifact"))
    }

    // MARK: - Artifact Orchestration

    @ButtonHeistActor
    func testWriteScreenshotIfSinkAvailableExplicitPath() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        let pngData = Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString()
        let outputPath = tempDirectory.appendingPathComponent("explicit.png").path

        let result = try bookKeeper.writeScreenshotIfSinkAvailable(
            base64Data: pngData,
            outputPath: outputPath,
            requestId: "r1",
            command: .getScreen,
            metadata: ScreenshotMetadata(width: 390, height: 844)
        )

        XCTAssertEqual(result?.path, outputPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
        XCTAssertNil(bookKeeper.manifest, "Explicit path should not create a session")
    }

    @ButtonHeistActor
    func testWriteScreenshotIfSinkAvailableActiveSession() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "orchestrate-session")
        let pngData = Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString()

        let result = try bookKeeper.writeScreenshotIfSinkAvailable(
            base64Data: pngData,
            outputPath: nil,
            requestId: "r1",
            command: .getScreen,
            metadata: ScreenshotMetadata(width: 390, height: 844)
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.lastPathComponent.hasPrefix("001-") == true)
        let snapshot = try XCTUnwrap(bookKeeper.sessionLogSnapshot())
        XCTAssertEqual(snapshot.artifacts.count, 1)
    }

    @ButtonHeistActor
    func testWriteScreenshotIfSinkAvailableNoSinkReturnsNil() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        let pngData = Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString()

        let result = try bookKeeper.writeScreenshotIfSinkAvailable(
            base64Data: pngData,
            outputPath: nil,
            requestId: "r1",
            command: .getScreen,
            metadata: ScreenshotMetadata(width: 390, height: 844)
        )

        XCTAssertNil(result, "With no session and no output path, should return nil")
    }

    @ButtonHeistActor
    func testWriteRecordingIfSinkAvailableRoutesRecording() async throws {
        let bookKeeper = TheBookKeeper(baseDirectory: tempDirectory)
        try bookKeeper.beginSession(identifier: "orchestrate-recording")
        let mp4Data = Data([0x00, 0x00, 0x00, 0x1C]).base64EncodedString()

        let result = try bookKeeper.writeRecordingIfSinkAvailable(
            base64Data: mp4Data,
            outputPath: nil,
            requestId: "r1",
            command: .stopRecording,
            metadata: RecordingMetadata(width: 390, height: 844, duration: 5.0, fps: 8, frameCount: 40)
        )

        XCTAssertTrue(result?.lastPathComponent.hasSuffix(".mp4") == true)
        XCTAssertTrue(result?.path.contains("recordings/") == true)
        let snapshot = try XCTUnwrap(bookKeeper.sessionLogSnapshot())
        XCTAssertEqual(snapshot.artifacts.first?.type, .recording)
    }
}

private struct DecodedHeaderLogEntry: Decodable {
    let type: String
    let formatVersion: String
    let sessionId: String
}

private struct DecodedCommandLogEntry: Decodable {
    let t: String
    let type: String
    let requestId: String
    let command: String
    let args: [String: HeistValue]?
}

private struct DecodedResponseLogEntry: Decodable {
    let t: String
    let type: String
    let requestId: String
    let status: ResponseStatus
    let durationMilliseconds: Int
    let artifact: String?
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case t
        case type
        case requestId
        case status
        case durationMilliseconds = "duration_ms"
        case artifact
        case error
    }
}

private func sessionLogContent(for session: ActiveSession) throws -> String {
    let logPath = session.directory.appendingPathComponent("session.jsonl")
    return try String(contentsOf: logPath, encoding: .utf8)
}

private func sessionLogLines(for session: ActiveSession) throws -> [Substring] {
    try sessionLogContent(for: session).split(separator: "\n")
}

private func decodeSessionLogLine<Entry: Decodable>(
    _ entryType: Entry.Type,
    from line: Substring
) throws -> Entry {
    try JSONDecoder().decode(entryType, from: Data(line.utf8))
}

@ButtonHeistActor
private func logCommand(
    _ bookKeeper: TheBookKeeper,
    requestId: String,
    command: TheFence.Command,
    arguments: [String: Any]
) throws {
    try bookKeeper.logCommand(parsedRequest(requestId: requestId, command: command, arguments: arguments))
}

@ButtonHeistActor
private func parsedRequest(
    requestId: String,
    command: TheFence.Command,
    arguments: [String: Any]
) throws -> TheFence.ParsedRequest {
    var request = arguments
    request["command"] = command.rawValue
    request["requestId"] = requestId
    return try TheFence(configuration: .init()).parseRequest(command: command, request: request)
}

private func XCTAssertHasNoStoredPhaseTimingMirrors<T>(
    _ value: T,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let storedLabels = Set(Mirror(reflecting: value).children.compactMap(\.label))
    XCTAssertFalse(storedLabels.contains("startTime"), file: file, line: line)
    XCTAssertFalse(storedLabels.contains("endTime"), file: file, line: line)
}

private func XCTAssertHasNoStoredPhaseIdentityMirrors<T>(
    _ value: T,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let storedLabels = Set(Mirror(reflecting: value).children.compactMap(\.label))
    XCTAssertFalse(storedLabels.contains("sessionId"), file: file, line: line)
}

private func posixPermissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
    return permissions.intValue & 0o777
}
