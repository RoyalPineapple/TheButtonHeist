import XCTest
 import TheScore

final class AuthMessageTests: XCTestCase {

    // MARK: - authRequired

    func testAuthRequiredEncodeDecode() throws {
        let message = ServerMessage.authRequired
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .authRequired = decoded {
        } else {
            XCTFail("Expected authRequired, got \(decoded)")
        }
    }

    func testAuthRequiredJSON() throws {
        let message = ServerMessage.authRequired
        let data = try JSONEncoder().encode(message)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("authRequired"))
    }

    // MARK: - error(ServerError) — authFailure

    func testAuthFailedEncodeDecode() throws {
        let message = ServerMessage.error(ServerError(kind: .authFailure, message: "Invalid token"))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .error(let serverError) = decoded {
            XCTAssertEqual(serverError.kind, .authFailure)
            XCTAssertEqual(serverError.message, "Invalid token")
        } else {
            XCTFail("Expected error, got \(decoded)")
        }
    }

    func testAuthFailedEmptyReason() throws {
        let message = ServerMessage.error(ServerError(kind: .authFailure, message: ""))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .error(let serverError) = decoded {
            XCTAssertEqual(serverError.kind, .authFailure)
            XCTAssertEqual(serverError.message, "")
        } else {
            XCTFail("Expected error, got \(decoded)")
        }
    }

    // MARK: - authApproved

    func testAuthApprovedEncodeDecode() throws {
        let payload = AuthApprovedPayload(token: "auto-generated-uuid")
        let message = ServerMessage.authApproved(payload)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .authApproved(let decodedPayload) = decoded {
            XCTAssertEqual(decodedPayload.token, "auto-generated-uuid")
        } else {
            XCTFail("Expected authApproved, got \(decoded)")
        }
    }

    func testAuthApprovedFromRawJSON() throws {
        let json = """
        {"type":"authApproved","payload":{"token":"abc-123"}}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)
        if case .authApproved(let payload) = decoded {
            XCTAssertEqual(payload.token, "abc-123")
        } else {
            XCTFail("Expected authApproved from raw JSON")
        }
    }

    // MARK: - authenticate (ClientMessage)

    func testAuthenticateEncodeDecode() throws {
        let payload = AuthenticatePayload(token: "secret-token-123")
        let message = ClientMessage.authenticate(payload)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .authenticate(let decodedPayload) = decoded {
            XCTAssertEqual(decodedPayload.token, "secret-token-123")
        } else {
            XCTFail("Expected authenticate, got \(decoded)")
        }
    }

    func testAuthenticateEmptyToken() throws {
        let payload = AuthenticatePayload(token: "")
        let message = ClientMessage.authenticate(payload)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .authenticate(let decodedPayload) = decoded {
            XCTAssertEqual(decodedPayload.token, "")
        } else {
            XCTFail("Expected authenticate, got \(decoded)")
        }
    }

    func testAuthenticateJSON() throws {
        let payload = AuthenticatePayload(token: "my-token")
        let message = ClientMessage.authenticate(payload)
        let data = try JSONEncoder().encode(message)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("authenticate"))
        XCTAssertTrue(json.contains("my-token"))
    }

    // MARK: - ServerInfo with instanceIdentifier

    func testServerInfoWithInstanceIdentifier() throws {
        let info = ServerInfo(
            appName: "TestApp",
            bundleIdentifier: "com.test.app",
            deviceName: "iPhone",
            systemVersion: "18.0",
            screenWidth: 393,
            screenHeight: 852,
            instanceIdentifier: "my-instance"
        )

        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(ServerInfo.self, from: data)

        XCTAssertEqual(decoded.instanceIdentifier, "my-instance")
    }

    func testServerInfoWithoutInstanceIdentifier() throws {
        let json = """
        {
            "appName": "TestApp",
            "bundleIdentifier": "com.test",
            "deviceName": "iPhone",
            "systemVersion": "18.0",
            "screenWidth": 393,
            "screenHeight": 852
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ServerInfo.self, from: data)

        XCTAssertNil(decoded.instanceIdentifier)
    }

    // MARK: - Auth handshake simulation (JSON round-trip)

    func testFullAuthHandshakeMessages() throws {
        // Step 1: Server sends authRequired
        let authReq = ServerMessage.authRequired
        let authReqData = try JSONEncoder().encode(authReq)
        let decodedAuthReq = try JSONDecoder().decode(ServerMessage.self, from: authReqData)
        if case .authRequired = decodedAuthReq {} else {
            XCTFail("Step 1 failed: expected authRequired")
            return
        }

        // Step 2: Client sends authenticate
        let authMsg = ClientMessage.authenticate(AuthenticatePayload(token: "valid-token"))
        let authMsgData = try JSONEncoder().encode(authMsg)
        let decodedAuth = try JSONDecoder().decode(ClientMessage.self, from: authMsgData)
        if case .authenticate(let payload) = decodedAuth {
            XCTAssertEqual(payload.token, "valid-token")
        } else {
            XCTFail("Step 2 failed: expected authenticate")
            return
        }

        // Step 3a: Server sends info on success
        let serverInfo = ServerInfo(
            appName: "MyApp",
            bundleIdentifier: "com.test.myapp",
            deviceName: "iPhone 16",
            systemVersion: "18.0",
            screenWidth: 393,
            screenHeight: 852,
            instanceIdentifier: "test-1"
        )
        let infoMsg = ServerMessage.info(serverInfo)
        let infoData = try JSONEncoder().encode(infoMsg)
        let decodedInfo = try JSONDecoder().decode(ServerMessage.self, from: infoData)
        if case .info(let info) = decodedInfo {
            XCTAssertEqual(info.instanceIdentifier, "test-1")
        } else {
            XCTFail("Step 3a failed: expected info")
        }

        // Step 3b: Or server sends an authFailure error
        let failMsg = ServerMessage.error(ServerError(kind: .authFailure, message: "Token mismatch"))
        let failData = try JSONEncoder().encode(failMsg)
        let decodedFail = try JSONDecoder().decode(ServerMessage.self, from: failData)
        if case .error(let serverError) = decodedFail {
            XCTAssertEqual(serverError.kind, .authFailure)
            XCTAssertEqual(serverError.message, "Token mismatch")
        } else {
            XCTFail("Step 3b failed: expected error(authFailure)")
        }
    }

    // MARK: - Wire format compatibility

    func testAuthRequiredFromRawJSON() throws {
        let json = """
        {"type":"authRequired"}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)
        if case .authRequired = decoded {} else {
            XCTFail("Expected authRequired from raw JSON")
        }
    }

    func testAuthFailedFromRawJSON() throws {
        let json = """
        {"type":"error","payload":{"kind":"authFailure","message":"Bad token"}}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)
        if case .error(let serverError) = decoded {
            XCTAssertEqual(serverError.kind, .authFailure)
            XCTAssertEqual(serverError.message, "Bad token")
        } else {
            XCTFail("Expected error(authFailure) from raw JSON")
        }
    }

    func testAuthenticateFromRawJSON() throws {
        let json = """
        {"type":"authenticate","payload":{"token":"abc123"}}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)
        if case .authenticate(let payload) = decoded {
            XCTAssertEqual(payload.token, "abc123")
        } else {
            XCTFail("Expected authenticate from raw JSON")
        }
    }

    // MARK: - Session Locking

    func testSessionLockedEncodeDecode() throws {
        let payload = SessionLockedPayload(message: "Session is locked", activeConnections: 2)
        let message = ServerMessage.sessionLocked(payload)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .sessionLocked(let decodedPayload) = decoded {
            XCTAssertEqual(decodedPayload.message, "Session is locked")
            XCTAssertEqual(decodedPayload.activeConnections, 2)
        } else {
            XCTFail("Expected sessionLocked, got \(decoded)")
        }
    }

    func testSessionLockedFromRawJSON() throws {
        let json = """
        {"type":"sessionLocked","payload":{"message":"Locked by driver","activeConnections":1}}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)
        if case .sessionLocked(let payload) = decoded {
            XCTAssertEqual(payload.message, "Locked by driver")
            XCTAssertEqual(payload.activeConnections, 1)
        } else {
            XCTFail("Expected sessionLocked from raw JSON")
        }
    }

    // MARK: - Driver ID

    func testAuthenticateWithDriverId() throws {
        let payload = AuthenticatePayload(token: "my-token", driverId: "agent-1")
        let message = ClientMessage.authenticate(payload)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .authenticate(let decodedPayload) = decoded {
            XCTAssertEqual(decodedPayload.token, "my-token")
            XCTAssertEqual(decodedPayload.driverId, "agent-1")
        } else {
            XCTFail("Expected authenticate with driverId")
        }
    }

    func testAuthenticateWithoutDriverIdFromExplicitJSON() throws {
        let json = """
        {"type":"authenticate","payload":{"token":"old-client"}}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)
        if case .authenticate(let payload) = decoded {
            XCTAssertEqual(payload.token, "old-client")
            XCTAssertNil(payload.driverId)
        } else {
            XCTFail("Expected authenticate from old-style JSON")
        }
    }

    func testAuthenticateNilDriverIdOmittedFromJSON() throws {
        let payload = AuthenticatePayload(token: "test")
        let data = try JSONEncoder().encode(payload)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertFalse(json.contains("driverId"))
    }
}
