import XCTest
@testable import ButtonHeist

final class EnvironmentConfigTests: XCTestCase {

    func testDefaultsWithEmptyEnv() {
        let config = EnvironmentConfig.resolve(env: [:])
        XCTAssertNil(config.deviceFilter)
        XCTAssertNil(config.token)
        XCTAssertEqual(config.sessionTimeout, 60.0)
        XCTAssertEqual(config.connectionTimeout, 30.0)
        XCTAssertTrue(config.autoReconnect)
    }

    func testEnvVarDeviceAndToken() {
        let env = [
            "BUTTONHEIST_DEVICE": "127.0.0.1:1455",
            "BUTTONHEIST_TOKEN": "tok-123",
        ]
        let config = EnvironmentConfig.resolve(env: env)
        XCTAssertEqual(config.deviceFilter, "127.0.0.1:1455")
        XCTAssertEqual(config.token, "tok-123")
    }

    func testExplicitOverridesWinOverEnvVars() {
        let env = [
            "BUTTONHEIST_DEVICE": "env-device",
            "BUTTONHEIST_TOKEN": "env-token",
        ]
        let config = EnvironmentConfig.resolve(
            deviceFilter: "explicit-device",
            token: "explicit-token",
            env: env
        )
        XCTAssertEqual(config.deviceFilter, "explicit-device")
        XCTAssertEqual(config.token, "explicit-token")
    }

    func testSessionTimeoutFromEnvVar() {
        let env = ["BUTTONHEIST_SESSION_TIMEOUT": "120"]
        let config = EnvironmentConfig.resolve(env: env)
        XCTAssertEqual(config.sessionTimeout, 120.0)
    }

    func testExplicitSessionTimeoutOverridesEnv() {
        let env = ["BUTTONHEIST_SESSION_TIMEOUT": "120"]
        let config = EnvironmentConfig.resolve(sessionTimeout: 300, env: env)
        XCTAssertEqual(config.sessionTimeout, 300.0)
    }

    func testInvalidSessionTimeoutEnvFallsBackToDefault() {
        let env = ["BUTTONHEIST_SESSION_TIMEOUT": "abc"]
        let config = EnvironmentConfig.resolve(env: env)
        XCTAssertEqual(config.sessionTimeout, 60.0)
    }

    func testZeroSessionTimeoutEnvFallsBackToDefault() {
        let env = ["BUTTONHEIST_SESSION_TIMEOUT": "0"]
        let config = EnvironmentConfig.resolve(env: env)
        XCTAssertEqual(config.sessionTimeout, 60.0)
    }

    func testFenceConfigurationProducesMatchingValues() {
        let config = EnvironmentConfig.resolve(
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

    func testNegativeSessionTimeoutEnvFallsBackToDefault() {
        let env = ["BUTTONHEIST_SESSION_TIMEOUT": "-5"]
        let config = EnvironmentConfig.resolve(env: env)
        XCTAssertEqual(config.sessionTimeout, 60.0)
    }
}
