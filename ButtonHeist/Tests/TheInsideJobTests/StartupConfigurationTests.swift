#if canImport(UIKit)
import XCTest
import TheScore
@testable import TheInsideJob

final class StartupConfigurationTests: XCTestCase {

    func testAutoStartIsDisabledUnderXCTestEnvironment() {
        XCTAssertTrue(isRunningUnderXCTest(environment: [
            "XCTestConfigurationFilePath": "/tmp/session.xctestconfiguration"
        ]))
        XCTAssertTrue(isRunningUnderXCTest(environment: [
            "XCTestSessionIdentifier": "session"
        ]))
        XCTAssertFalse(isRunningUnderXCTest(environment: [:]))
    }

    func testEnvironmentOverridesInfoPlist() {
        let configuration = StartupConfiguration.resolve(
            env: [
                "INSIDEJOB_DISABLE": "false",
                "INSIDEJOB_TOKEN": "env-token",
                "INSIDEJOB_ID": "env-id",
                "INSIDEJOB_PORT": "4242",
                "INSIDEJOB_SCOPE": "network",
                "INSIDEJOB_SESSION_TIMEOUT": "45"
            ],
            infoPlist: makeInfoPlist([
                "InsideJobDisableAutoStart": true,
                "InsideJobToken": "plist-token",
                "InsideJobInstanceId": "plist-id",
                "InsideJobPort": 5151,
                "InsideJobScope": "simulator,usb",
                "InsideJobSessionTimeout": 120.0
            ])
        )

        let expected = StartupConfiguration(
            disableAutoStart: ResolvedStartupValue(value: false, source: .environment),
            token: ResolvedStartupValue(value: "env-token", source: .environment),
            instanceId: ResolvedStartupValue(value: "env-id", source: .environment),
            preferredPort: ResolvedStartupValue(value: 4242, source: .environment),
            allowedScopes: ResolvedStartupValue(value: [.network], source: .environment),
            sessionTimeout: ResolvedStartupValue(value: 45.0, source: .environment),
            warnings: []
        )
        XCTAssertEqual(configuration, expected)
    }

    func testInfoPlistUsedWhenEnvironmentMissing() {
        let configuration = StartupConfiguration.resolve(
            env: [:],
            infoPlist: makeInfoPlist([
                "InsideJobDisableAutoStart": true,
                "InsideJobToken": "plist-token",
                "InsideJobInstanceId": "plist-id",
                "InsideJobPort": 5151,
                "InsideJobScope": ["simulator", "usb"],
                "InsideJobSessionTimeout": 120.0
            ])
        )

        let expected = StartupConfiguration(
            disableAutoStart: ResolvedStartupValue(value: true, source: .infoPlist),
            token: ResolvedStartupValue(value: "plist-token", source: .infoPlist),
            instanceId: ResolvedStartupValue(value: "plist-id", source: .infoPlist),
            preferredPort: ResolvedStartupValue(value: 5151, source: .infoPlist),
            allowedScopes: ResolvedStartupValue(value: [.simulator, .usb], source: .infoPlist),
            sessionTimeout: ResolvedStartupValue(value: 120.0, source: .infoPlist),
            warnings: []
        )
        XCTAssertEqual(configuration, expected)
    }

    func testInfoPlistBoundaryParsesTypedShapes() {
        let configuration = StartupConfiguration.resolve(
            env: [:],
            infoPlist: makeInfoPlist([
                "InsideJobDisableAutoStart": "yes",
                "InsideJobFingerprintsEnabled": "no",
                "InsideJobPort": 5151.0,
                "InsideJobScope": "simulator,network",
                "InsideJobSessionTimeout": " 120.5 "
            ])
        )

        XCTAssertEqual(configuration.disableAutoStart, ResolvedStartupValue(value: true, source: .infoPlist))
        XCTAssertEqual(configuration.fingerprintsEnabled, ResolvedStartupValue(value: false, source: .infoPlist))
        XCTAssertEqual(configuration.preferredPort, ResolvedStartupValue(value: 5151, source: .infoPlist))
        XCTAssertEqual(configuration.allowedScopes, ResolvedStartupValue(value: [.simulator, .network], source: .infoPlist))
        XCTAssertEqual(configuration.sessionTimeout, ResolvedStartupValue(value: 120.5, source: .infoPlist))
        XCTAssertEqual(configuration.warnings, [])
    }

    func testMalformedInfoPlistValuesFallBackWithWarnings() {
        let configuration = StartupConfiguration.resolve(
            env: [:],
            infoPlist: makeInfoPlist([
                "InsideJobDisableAutoStart": ["true"],
                "InsideJobFingerprintsEnabled": ["false"],
                "InsideJobToken": 42,
                "InsideJobPort": 12.5,
                "InsideJobScope": ["simulator", "bogus"],
                "InsideJobSessionTimeout": "soon"
            ])
        )

        XCTAssertEqual(configuration.disableAutoStart, ResolvedStartupValue(value: false, source: .defaultValue))
        XCTAssertEqual(configuration.fingerprintsEnabled, ResolvedStartupValue(value: true, source: .defaultValue))
        XCTAssertEqual(configuration.token, ResolvedStartupValue(value: nil, source: .generated))
        XCTAssertEqual(configuration.preferredPort, ResolvedStartupValue(value: 0, source: .defaultValue))
        XCTAssertEqual(configuration.allowedScopes, ResolvedStartupValue(value: ConnectionScope.default, source: .defaultValue))
        XCTAssertEqual(configuration.sessionTimeout, ResolvedStartupValue(value: 30.0, source: .defaultValue))
        XCTAssertEqual(configuration.warnings, [
            .invalidValueIgnored(key: "InsideJobDisableAutoStart", source: .infoPlist, value: "[\"true\"]"),
            .invalidValueIgnored(key: "InsideJobFingerprintsEnabled", source: .infoPlist, value: "[\"false\"]"),
            .invalidValueIgnored(key: "InsideJobPort", source: .infoPlist, value: "12.5"),
            .invalidValueIgnored(key: "InsideJobScope", source: .infoPlist, value: "[\"simulator\", \"bogus\"]"),
            .invalidValueIgnored(key: "InsideJobSessionTimeout", source: .infoPlist, value: "soon")
        ])
    }

    func testInfoPlistStringArraysOnlyResolveForScope() {
        let configuration = StartupConfiguration.resolve(
            env: [:],
            infoPlist: makeInfoPlist([
                "InsideJobToken": ["token"],
                "InsideJobInstanceId": ["instance-id"],
                "InsideJobScope": ["simulator", "usb"]
            ])
        )

        let expected = StartupConfiguration(
            disableAutoStart: ResolvedStartupValue(value: false, source: .defaultValue),
            token: ResolvedStartupValue(value: nil, source: .generated),
            instanceId: ResolvedStartupValue(value: nil, source: .generated),
            preferredPort: ResolvedStartupValue(value: 0, source: .defaultValue),
            allowedScopes: ResolvedStartupValue(value: [.simulator, .usb], source: .infoPlist),
            sessionTimeout: ResolvedStartupValue(value: 30.0, source: .defaultValue),
            warnings: []
        )
        XCTAssertEqual(configuration, expected)
    }

    func testFingerprintsConfigResolvesPositiveAndLegacyDisableKeys() {
        XCTAssertEqual(
            StartupConfiguration.resolve(
                env: ["INSIDEJOB_FINGERPRINTS": "false"],
                infoPlist: makeInfoPlist(["InsideJobFingerprintsEnabled": true])
            ).fingerprintsEnabled,
            ResolvedStartupValue(value: false, source: .environment)
        )
        XCTAssertEqual(
            StartupConfiguration.resolve(
                env: ["INSIDEJOB_DISABLE_FINGERPRINTS": "true"],
                infoPlist: makeInfoPlist(["InsideJobFingerprintsEnabled": true])
            ).fingerprintsEnabled,
            ResolvedStartupValue(value: false, source: .environment)
        )
        XCTAssertEqual(
            StartupConfiguration.resolve(
                env: [:],
                infoPlist: makeInfoPlist(["InsideJobDisableFingerprints": true])
            ).fingerprintsEnabled,
            ResolvedStartupValue(value: false, source: .infoPlist)
        )
    }

    func testEmptyTokenAndInstanceIdAreIgnoredWithWarnings() {
        let configuration = StartupConfiguration.resolve(
            env: [
                "INSIDEJOB_TOKEN": "",
                "INSIDEJOB_ID": "   "
            ],
            infoPlist: makeInfoPlist([
                "InsideJobToken": "plist-token",
                "InsideJobInstanceId": "plist-id"
            ])
        )

        let expected = StartupConfiguration(
            disableAutoStart: ResolvedStartupValue(value: false, source: .defaultValue),
            token: ResolvedStartupValue(value: "plist-token", source: .infoPlist),
            instanceId: ResolvedStartupValue(value: "plist-id", source: .infoPlist),
            preferredPort: ResolvedStartupValue(value: 0, source: .defaultValue),
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
                "INSIDEJOB_SCOPE": "bogus",
                "INSIDEJOB_SESSION_TIMEOUT": "0"
            ],
            infoPlist: makeInfoPlist([
                "InsideJobPort": 5151,
                "InsideJobScope": "usb"
            ])
        )

        let expected = StartupConfiguration(
            disableAutoStart: ResolvedStartupValue(value: false, source: .defaultValue),
            token: ResolvedStartupValue(value: nil, source: .generated),
            instanceId: ResolvedStartupValue(value: nil, source: .generated),
            preferredPort: ResolvedStartupValue(value: 5151, source: .infoPlist),
            allowedScopes: ResolvedStartupValue(value: [.usb], source: .infoPlist),
            sessionTimeout: ResolvedStartupValue(value: 1.0, source: .environment),
            warnings: [
                .invalidValueIgnored(key: "INSIDEJOB_PORT", source: .environment, value: "99999"),
                .invalidValueIgnored(key: "INSIDEJOB_SCOPE", source: .environment, value: "bogus")
            ]
        )
        XCTAssertEqual(configuration, expected)
    }

    func testRuntimeConfigurationAppliesAPIOverridesToResolvedStartupSnapshot() {
        let startupConfiguration = StartupConfiguration(
            disableAutoStart: ResolvedStartupValue(value: false, source: .defaultValue),
            token: ResolvedStartupValue(value: "startup-token", source: .environment),
            instanceId: ResolvedStartupValue(value: "startup-id", source: .environment),
            preferredPort: ResolvedStartupValue(value: 5151, source: .environment),
            allowedScopes: ResolvedStartupValue(value: [.simulator], source: .environment),
            sessionTimeout: ResolvedStartupValue(value: 12.0, source: .environment),
            warnings: []
        )

        let runtimeConfiguration = InsideJobRuntimeConfiguration.resolve(
            startupConfiguration: startupConfiguration,
            token: "api-token",
            instanceId: "api-id",
            allowedScopes: [.network],
            port: 4242,
            fingerprintsEnabled: false
        )

        XCTAssertEqual(runtimeConfiguration.token, "api-token")
        XCTAssertEqual(runtimeConfiguration.tokenSource, .api)
        XCTAssertEqual(runtimeConfiguration.sessionIdentity.effectiveInstanceId, "api-id")
        XCTAssertEqual(runtimeConfiguration.instanceIdSource, .api)
        XCTAssertEqual(runtimeConfiguration.preferredPort, 4242)
        XCTAssertEqual(runtimeConfiguration.preferredPortSource, .api)
        XCTAssertEqual(runtimeConfiguration.allowedScopes, [.network])
        XCTAssertEqual(runtimeConfiguration.allowedScopesSource, .api)
        XCTAssertEqual(runtimeConfiguration.sessionReleaseTimeout, startupConfiguration.sessionTimeout)
        XCTAssertFalse(runtimeConfiguration.fingerprintsEnabled)
        XCTAssertEqual(runtimeConfiguration.fingerprintsEnabledSource, .api)
    }

    func testRuntimeConfigurationUsesExplicitStartupSnapshotForSessionDefaults() {
        let startupConfiguration = StartupConfiguration(
            disableAutoStart: ResolvedStartupValue(value: false, source: .defaultValue),
            token: ResolvedStartupValue(value: "startup-token", source: .environment),
            instanceId: ResolvedStartupValue(value: "startup-id", source: .environment),
            preferredPort: ResolvedStartupValue(value: 5151, source: .environment),
            allowedScopes: ResolvedStartupValue(value: [.usb], source: .infoPlist),
            sessionTimeout: ResolvedStartupValue(value: 24.0, source: .infoPlist),
            warnings: []
        )

        let runtimeConfiguration = InsideJobRuntimeConfiguration.resolve(
            startupConfiguration: startupConfiguration,
            token: nil,
            instanceId: nil,
            allowedScopes: nil,
            port: 0
        )

        XCTAssertEqual(runtimeConfiguration.token, "startup-token")
        XCTAssertEqual(runtimeConfiguration.tokenSource, .environment)
        XCTAssertEqual(runtimeConfiguration.instanceIdSource, .generated)
        XCTAssertEqual(runtimeConfiguration.preferredPort, 0)
        XCTAssertEqual(runtimeConfiguration.preferredPortSource, .defaultValue)
        XCTAssertEqual(runtimeConfiguration.allowedScopes, [.usb])
        XCTAssertEqual(runtimeConfiguration.allowedScopesSource, .infoPlist)
        XCTAssertEqual(runtimeConfiguration.sessionReleaseTimeout, startupConfiguration.sessionTimeout)
    }

    func testRuntimeKnobsUseDefaults() {
        let knobs = InsideJobRuntimeKnobs.resolve(environment: [:])

        XCTAssertEqual(knobs.postScrollLayoutFrames, 3)
        XCTAssertEqual(knobs.tripwirePulseFramesPerSecond, 10)
        XCTAssertEqual(knobs.maxScrollsPerContainer, 200)
        XCTAssertEqual(knobs.maxScrollsPerDiscovery, 200)
        XCTAssertEqual(knobs.visibleElementBudget, 300)
        XCTAssertEqual(knobs.totalNodeBudget, 5_000)
        XCTAssertEqual(knobs.singleTripwireTickSettleTimeout, 0.2, accuracy: 0.001)
    }

    func testRuntimeKnobsReadEnvironmentFromOneResolver() {
        let knobs = InsideJobRuntimeKnobs.resolve(environment: [
            "BH_POST_SCROLL_LAYOUT_FRAMES": "0",
            "BH_TRIPWIRE_PULSE_HZ": "60",
            "BH_MAX_SCROLLS_PER_CONTAINER": "25",
            "BH_MAX_SCROLLS_PER_DISCOVERY": "30",
            "BH_SCROLL_SUBTREE_ELEMENT_BUDGET": "75",
            "BH_TOTAL_NODE_BUDGET": "4000"
        ])

        XCTAssertEqual(knobs.postScrollLayoutFrames, 0)
        XCTAssertEqual(knobs.tripwirePulseFramesPerSecond, 60)
        XCTAssertEqual(knobs.maxScrollsPerContainer, 25)
        XCTAssertEqual(knobs.maxScrollsPerDiscovery, 30)
        XCTAssertEqual(knobs.visibleElementBudget, 75)
        XCTAssertEqual(knobs.totalNodeBudget, 4_000)
        XCTAssertEqual(knobs.singleTripwireTickSettleTimeout, 0.05, accuracy: 0.001)
    }

    func testRuntimeKnobsReadTestRunnerPrefixedEnvironmentAndClamp() {
        let knobs = InsideJobRuntimeKnobs.resolve(environment: [
            "TEST_RUNNER_BH_POST_SCROLL_LAYOUT_FRAMES": "99",
            "TEST_RUNNER_BH_TRIPWIRE_PULSE_HZ": "0",
            "TEST_RUNNER_BH_MAX_SCROLLS_PER_CONTAINER": "9999",
            "TEST_RUNNER_BH_MAX_SCROLLS_PER_DISCOVERY": "9999",
            "TEST_RUNNER_BH_SCROLL_SUBTREE_ELEMENT_BUDGET": "9999",
            "TEST_RUNNER_BH_TOTAL_NODE_BUDGET": "9999"
        ])

        XCTAssertEqual(knobs.postScrollLayoutFrames, 10)
        XCTAssertEqual(knobs.tripwirePulseFramesPerSecond, 1)
        XCTAssertEqual(knobs.maxScrollsPerContainer, 2_000)
        XCTAssertEqual(knobs.maxScrollsPerDiscovery, 2_000)
        XCTAssertEqual(knobs.visibleElementBudget, 1_000)
        XCTAssertEqual(knobs.totalNodeBudget, 5_000)
        XCTAssertEqual(knobs.singleTripwireTickSettleTimeout, 2.0, accuracy: 0.001)
    }
}

private func makeInfoPlist(
    _ values: NSDictionary,
    file: StaticString = #filePath,
    line: UInt = #line
) -> StartupInfoPlist {
    do {
        let data = try PropertyListSerialization.data(
            fromPropertyList: values,
            format: .xml,
            options: 0
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("StartupConfigurationTests-\(UUID().uuidString)")
            .appendingPathExtension("plist")
        try data.write(to: url)
        return StartupInfoPlist(contentsOf: url)
    } catch {
        XCTFail("Failed to write Info.plist fixture: \(error)", file: file, line: line)
        return StartupInfoPlist(contentsOf: URL(fileURLWithPath: "/dev/null"))
    }
}
#endif
