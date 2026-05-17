#if canImport(UIKit)
import XCTest
import TheScore
@testable import TheInsideJob

final class StartupConfigurationTests: XCTestCase {

    func testEnvironmentOverridesInfoPlist() {
        let configuration = StartupConfiguration.resolve(
            env: [
                "INSIDEJOB_DISABLE": "false",
                "INSIDEJOB_TOKEN": "env-token",
                "INSIDEJOB_ID": "env-id",
                "INSIDEJOB_PORT": "4242",
                "INSIDEJOB_POLLING_INTERVAL": "2.25",
                "INSIDEJOB_SCOPE": "network",
                "INSIDEJOB_SESSION_TIMEOUT": "45"
            ],
            infoDictionary: [
                "InsideJobDisableAutoStart": true,
                "InsideJobToken": "plist-token",
                "InsideJobInstanceId": "plist-id",
                "InsideJobPort": 5151,
                "InsideJobPollingInterval": 3.0,
                "InsideJobScope": "simulator,usb",
                "InsideJobSessionTimeout": 120.0
            ]
        )

        let expected = StartupConfiguration(
            disableAutoStart: ResolvedStartupValue(value: false, source: .environment),
            token: ResolvedStartupValue(value: "env-token", source: .environment),
            instanceId: ResolvedStartupValue(value: "env-id", source: .environment),
            preferredPort: ResolvedStartupValue(value: 4242, source: .environment),
            pollingInterval: ResolvedStartupValue(value: 2.25, source: .environment),
            allowedScopes: ResolvedStartupValue(value: [.network], source: .environment),
            sessionTimeout: ResolvedStartupValue(value: 45.0, source: .environment),
            warnings: []
        )
        XCTAssertEqual(configuration, expected)
    }

    func testInfoPlistUsedWhenEnvironmentMissing() {
        let configuration = StartupConfiguration.resolve(
            env: [:],
            infoDictionary: [
                "InsideJobDisableAutoStart": true,
                "InsideJobToken": "plist-token",
                "InsideJobInstanceId": "plist-id",
                "InsideJobPort": 5151,
                "InsideJobPollingInterval": 3.0,
                "InsideJobScope": ["simulator", "usb"],
                "InsideJobSessionTimeout": 120.0
            ]
        )

        let expected = StartupConfiguration(
            disableAutoStart: ResolvedStartupValue(value: true, source: .infoPlist),
            token: ResolvedStartupValue(value: "plist-token", source: .infoPlist),
            instanceId: ResolvedStartupValue(value: "plist-id", source: .infoPlist),
            preferredPort: ResolvedStartupValue(value: 5151, source: .infoPlist),
            pollingInterval: ResolvedStartupValue(value: 3.0, source: .infoPlist),
            allowedScopes: ResolvedStartupValue(value: [.simulator, .usb], source: .infoPlist),
            sessionTimeout: ResolvedStartupValue(value: 120.0, source: .infoPlist),
            warnings: []
        )
        XCTAssertEqual(configuration, expected)
    }

    func testEmptyTokenAndInstanceIdAreIgnoredWithWarnings() {
        let configuration = StartupConfiguration.resolve(
            env: [
                "INSIDEJOB_TOKEN": "",
                "INSIDEJOB_ID": "   "
            ],
            infoDictionary: [
                "InsideJobToken": "plist-token",
                "InsideJobInstanceId": "plist-id"
            ]
        )

        let expected = StartupConfiguration(
            disableAutoStart: ResolvedStartupValue(value: false, source: .defaultValue),
            token: ResolvedStartupValue(value: "plist-token", source: .infoPlist),
            instanceId: ResolvedStartupValue(value: "plist-id", source: .infoPlist),
            preferredPort: ResolvedStartupValue(value: 0, source: .defaultValue),
            pollingInterval: ResolvedStartupValue(value: 1.0, source: .defaultValue),
            allowedScopes: ResolvedStartupValue(value: ConnectionScope.default, source: .defaultValue),
            sessionTimeout: ResolvedStartupValue(value: 30.0, source: .defaultValue),
            warnings: [
                .emptyValueIgnored(key: "INSIDEJOB_TOKEN", source: .environment),
                .emptyValueIgnored(key: "INSIDEJOB_ID", source: .environment)
            ]
        )
        XCTAssertEqual(configuration, expected)
    }

    func testInvalidValuesFallBackAndNumericValuesClamp() {
        let configuration = StartupConfiguration.resolve(
            env: [
                "INSIDEJOB_PORT": "99999",
                "INSIDEJOB_POLLING_INTERVAL": "0.1",
                "INSIDEJOB_SCOPE": "bogus",
                "INSIDEJOB_SESSION_TIMEOUT": "0"
            ],
            infoDictionary: [
                "InsideJobPort": 5151,
                "InsideJobScope": "usb"
            ]
        )

        let expected = StartupConfiguration(
            disableAutoStart: ResolvedStartupValue(value: false, source: .defaultValue),
            token: ResolvedStartupValue(value: nil, source: .generated),
            instanceId: ResolvedStartupValue(value: nil, source: .generated),
            preferredPort: ResolvedStartupValue(value: 5151, source: .infoPlist),
            pollingInterval: ResolvedStartupValue(value: 0.5, source: .environment),
            allowedScopes: ResolvedStartupValue(value: [.usb], source: .infoPlist),
            sessionTimeout: ResolvedStartupValue(value: 1.0, source: .environment),
            warnings: [
                .invalidValueIgnored(key: "INSIDEJOB_PORT", source: .environment, value: "99999"),
                .invalidValueIgnored(key: "INSIDEJOB_SCOPE", source: .environment, value: "bogus")
            ]
        )
        XCTAssertEqual(configuration, expected)
    }
}
#endif
