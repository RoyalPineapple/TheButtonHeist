import XCTest
@testable import ButtonHeist

final class EnvironmentConfigTests: XCTestCase {

    func testDefaultsWithEmptyEnv() throws {
        let config = resolve(env: [:])
        XCTAssertNil(config.deviceFilter)
        XCTAssertNil(config.token)
        XCTAssertEqual(config.sessionTimeout, 60.0)
        XCTAssertEqual(config.connectionTimeout, 30.0)
        XCTAssertTrue(config.autoReconnect)
    }

    func testEnvVarDeviceAndToken() throws {
        let env = [
            "BUTTONHEIST_DEVICE": "127.0.0.1:1455",
            "BUTTONHEIST_TOKEN": "tok-123",
        ]
        let config = resolve(env: env)
        XCTAssertEqual(config.deviceFilter, "127.0.0.1:1455")
        XCTAssertEqual(config.token, "tok-123")
    }

    func testExplicitOverridesWinOverEnvVars() throws {
        let env = [
            "BUTTONHEIST_DEVICE": "env-device",
            "BUTTONHEIST_TOKEN": "env-token",
        ]
        let config = resolve(
            deviceFilter: "explicit-device",
            token: "explicit-token",
            env: env
        )
        XCTAssertEqual(config.deviceFilter, "explicit-device")
        XCTAssertEqual(config.token, "explicit-token")
    }

    func testSessionTimeoutFromEnvVar() throws {
        let env = ["BUTTONHEIST_SESSION_TIMEOUT": "120"]
        let config = resolve(env: env)
        XCTAssertEqual(config.sessionTimeout, 120.0)
    }

    func testConnectionTimeoutFromEnvVar() throws {
        let env = ["BUTTONHEIST_CONNECTION_TIMEOUT": "7.5"]
        let config = resolve(env: env)
        XCTAssertEqual(config.connectionTimeout, 7.5)
    }

    func testExplicitSessionTimeoutOverridesEnv() throws {
        let env = ["BUTTONHEIST_SESSION_TIMEOUT": "120"]
        let config = resolve(sessionTimeout: 300, env: env)
        XCTAssertEqual(config.sessionTimeout, 300.0)
    }

    func testExplicitConnectionTimeoutOverridesEnv() throws {
        let env = ["BUTTONHEIST_CONNECTION_TIMEOUT": "7.5"]
        let config = resolve(connectionTimeout: 2.0, env: env)
        XCTAssertEqual(config.connectionTimeout, 2.0)
    }

    func testInvalidSessionTimeoutEnvFallsBackToDefault() throws {
        let env = ["BUTTONHEIST_SESSION_TIMEOUT": "abc"]
        let config = resolve(env: env)
        XCTAssertEqual(config.sessionTimeout, 60.0)
    }

    func testInvalidConnectionTimeoutEnvFallsBackToDefault() throws {
        let env = ["BUTTONHEIST_CONNECTION_TIMEOUT": "abc"]
        let config = resolve(env: env)
        XCTAssertEqual(config.connectionTimeout, 30.0)
    }

    func testZeroSessionTimeoutEnvFallsBackToDefault() throws {
        let env = ["BUTTONHEIST_SESSION_TIMEOUT": "0"]
        let config = resolve(env: env)
        XCTAssertEqual(config.sessionTimeout, 60.0)
    }

    func testFenceConfigurationProducesMatchingValues() throws {
        let config = resolve(
            deviceFilter: "127.0.0.1:1455",
            token: "tok",
            connectionTimeout: 15,
            autoReconnect: false,
            env: [:]
        )
        let fence = config.fenceConfiguration
        XCTAssertEqual(fence.deviceFilter, "127.0.0.1:1455")
        XCTAssertEqual(fence.token, "tok")
        XCTAssertEqual(fence.connectionTimeout, 15.0)
        XCTAssertEqual(fence.autoReconnect, false)
    }

    func testNegativeSessionTimeoutEnvFallsBackToDefault() throws {
        let env = ["BUTTONHEIST_SESSION_TIMEOUT": "-5"]
        let config = resolve(env: env)
        XCTAssertEqual(config.sessionTimeout, 60.0)
    }

    func testExplicitConfigPathFailurePropagatesDiagnosticError() {
        let path = "/nonexistent/path/.buttonheist.json"

        XCTAssertThrowsError(try EnvironmentConfig.resolve(configPath: path, env: [:])) { error in
            guard let error = error as? TargetConfigLoadError else {
                XCTFail("Expected TargetConfigLoadError, got \(type(of: error))")
                return
            }
            XCTAssertEqual(error.kind, .readFailed)
            XCTAssertEqual(error.path, path)
            XCTAssertEqual(error.failureDetails.errorCode, "config.read_failed")
        }
    }

    private func resolve(
        deviceFilter: String? = nil,
        token: String? = nil,
        sessionTimeout: TimeInterval? = nil,
        connectionTimeout: TimeInterval? = nil,
        autoReconnect: Bool = true,
        env: [String: String]
    ) -> EnvironmentConfig {
        EnvironmentConfig.resolve(
            deviceFilter: deviceFilter,
            token: token,
            sessionTimeout: sessionTimeout,
            connectionTimeout: connectionTimeout,
            autoReconnect: autoReconnect,
            fileConfig: nil,
            env: env
        )
    }
}
