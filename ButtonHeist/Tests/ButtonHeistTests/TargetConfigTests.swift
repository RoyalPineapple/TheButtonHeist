import XCTest
import Network
@testable import ButtonHeist
import TheScore

final class TargetConfigTests: XCTestCase {

    // MARK: - ButtonHeistFileConfig Parsing

    func testParseValidConfig() throws {
        let json = """
        {
            "targets": {
                "sim1": {"device": "127.0.0.1:1455", "token": "abc123"},
                "sim2": {"device": "127.0.0.1:1456"}
            },
            "default": "sim1"
        }
        """
        let config = try JSONDecoder().decode(ButtonHeistFileConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.targets.count, 2)
        XCTAssertEqual(config.targets["sim1"]?.device, "127.0.0.1:1455")
        XCTAssertEqual(config.targets["sim1"]?.token, "abc123")
        XCTAssertEqual(config.targets["sim2"]?.device, "127.0.0.1:1456")
        XCTAssertNil(config.targets["sim2"]?.token)
        XCTAssertEqual(config.defaultTarget, "sim1")
    }

    func testParseConfigWithoutDefault() throws {
        let json = """
        {
            "targets": {
                "dev": {"device": "127.0.0.1:1455"}
            }
        }
        """
        let config = try JSONDecoder().decode(ButtonHeistFileConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.targets.count, 1)
        XCTAssertNil(config.defaultTarget)
    }

    func testParseEmptyTargets() throws {
        let json = """
        {"targets": {}}
        """
        let config = try JSONDecoder().decode(ButtonHeistFileConfig.self, from: Data(json.utf8))
        XCTAssertTrue(config.targets.isEmpty)
    }

    func testParseInvalidJSONFails() {
        let json = "not json"
        XCTAssertThrowsError(try JSONDecoder().decode(ButtonHeistFileConfig.self, from: Data(json.utf8)))
    }

    func testParseMissingTargetsKeyFails() {
        let json = """
        {"default": "sim1"}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(ButtonHeistFileConfig.self, from: Data(json.utf8)))
    }

    // MARK: - TargetConfigResolver.resolveEffective

    func testEnvVarsOverrideEverything() {
        let config = ButtonHeistFileConfig(
            targets: ["sim1": TargetConfig(device: "127.0.0.1:1455", token: "config-token")],
            defaultTarget: "sim1"
        )
        let env = [
            "BUTTONHEIST_DEVICE": "127.0.0.1:9999",
            "BUTTONHEIST_TOKEN": "env-token",
        ]

        let resolved = TargetConfigResolver.resolveEffective(targetName: "sim1", config: config, env: env)
        XCTAssertEqual(resolved?.device, "127.0.0.1:9999")
        XCTAssertEqual(resolved?.token, "env-token")
    }

    func testEnvDeviceWithoutTokenUsesNilToken() {
        let env = ["BUTTONHEIST_DEVICE": "127.0.0.1:9999"]
        let resolved = TargetConfigResolver.resolveEffective(config: nil, env: env)
        XCTAssertEqual(resolved?.device, "127.0.0.1:9999")
        XCTAssertNil(resolved?.token)
    }

    func testNamedTargetFromConfig() {
        let config = ButtonHeistFileConfig(
            targets: ["sim1": TargetConfig(device: "127.0.0.1:1455", token: "t1")],
            defaultTarget: nil
        )
        let resolved = TargetConfigResolver.resolveEffective(targetName: "sim1", config: config, env: [:])
        XCTAssertEqual(resolved?.device, "127.0.0.1:1455")
        XCTAssertEqual(resolved?.token, "t1")
    }

    func testDefaultTargetFromConfig() {
        let config = ButtonHeistFileConfig(
            targets: [
                "sim1": TargetConfig(device: "127.0.0.1:1455"),
                "sim2": TargetConfig(device: "127.0.0.1:1456"),
            ],
            defaultTarget: "sim2"
        )
        let resolved = TargetConfigResolver.resolveEffective(config: config, env: [:])
        XCTAssertEqual(resolved?.device, "127.0.0.1:1456")
    }

    func testNoConfigNoEnvReturnsNil() {
        let resolved = TargetConfigResolver.resolveEffective(config: nil, env: [:])
        XCTAssertNil(resolved)
    }

    func testUnknownTargetNameReturnsNil() {
        let config = ButtonHeistFileConfig(
            targets: ["sim1": TargetConfig(device: "127.0.0.1:1455")],
            defaultTarget: nil
        )
        let resolved = TargetConfigResolver.resolveEffective(targetName: "unknown", config: config, env: [:])
        XCTAssertNil(resolved)
    }

    func testEnvTokenOverridesConfigToken() {
        let config = ButtonHeistFileConfig(
            targets: ["sim1": TargetConfig(device: "127.0.0.1:1455", token: "config-token")],
            defaultTarget: "sim1"
        )
        let env = ["BUTTONHEIST_TOKEN": "env-token"]
        let resolved = TargetConfigResolver.resolveEffective(config: config, env: env)
        XCTAssertEqual(resolved?.device, "127.0.0.1:1455")
        XCTAssertEqual(resolved?.token, "env-token")
    }

    // MARK: - TargetConfigResolver.loadConfig

    func testLoadConfigFromExplicitPath() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let configFile = tmpDir.appendingPathComponent(".buttonheist.json")
        let json = """
        {
            "targets": {
                "test": {"device": "127.0.0.1:1455", "token": "test-token"}
            },
            "default": "test"
        }
        """
        try json.write(to: configFile, atomically: true, encoding: .utf8)

        let config = TargetConfigResolver.loadConfig(from: configFile.path)
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.targets["test"]?.device, "127.0.0.1:1455")
        XCTAssertEqual(config?.targets["test"]?.token, "test-token")
        XCTAssertEqual(config?.defaultTarget, "test")
    }

    func testLoadConfigMissingFileReturnsNil() {
        let config = TargetConfigResolver.loadConfig(from: "/nonexistent/path/.buttonheist.json")
        XCTAssertNil(config)
    }

    // MARK: - TheFence Command Enum (updated count)

    func testCommandCaseCountIncludesNewCommands() {
        let allCases = TheFence.Command.allCases
        XCTAssertTrue(allCases.contains(.connect))
        XCTAssertTrue(allCases.contains(.listTargets))
    }

    func testConnectCommandRawValue() {
        XCTAssertEqual(TheFence.Command.connect.rawValue, "connect")
        XCTAssertEqual(TheFence.Command.listTargets.rawValue, "list_targets")
    }

    // MARK: - TheFence.configTargetsAsDevices

    @ButtonHeistActor
    func testConfigTargetsAsDevices() async {
        let config = ButtonHeistFileConfig(
            targets: [
                "sim1": TargetConfig(device: "127.0.0.1:1455"),
                "sim2": TargetConfig(device: "127.0.0.1:1456", token: "tok"),
            ]
        )
        let devices = TheFence.configTargetsAsDevices(config)
        XCTAssertEqual(devices.count, 2)

        let sim1 = devices.first { $0.id == "config-sim1" }
        XCTAssertNotNil(sim1)
        XCTAssertEqual(sim1?.name, "sim1")

        let sim2 = devices.first { $0.id == "config-sim2" }
        XCTAssertNotNil(sim2)
        XCTAssertEqual(sim2?.name, "sim2")
    }

    @ButtonHeistActor
    func testConfigTargetsWithInvalidDeviceSkipped() async {
        let config = ButtonHeistFileConfig(
            targets: [
                "good": TargetConfig(device: "127.0.0.1:1455"),
                "bad": TargetConfig(device: "no-port-here"),
            ]
        )
        let devices = TheFence.configTargetsAsDevices(config)
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices.first?.id, "config-good")
    }

    // MARK: - FenceResponse.targets formatting

    func testTargetsResponseHumanFormatting() {
        let response = FenceResponse.targets(
            ["sim1": TargetConfig(device: "127.0.0.1:1455")],
            defaultTarget: "sim1"
        )
        let text = response.humanFormatted()
        XCTAssertTrue(text.contains("sim1"))
        XCTAssertTrue(text.contains("127.0.0.1:1455"))
        XCTAssertTrue(text.contains("(default)"))
    }

    func testTargetsResponseEmptyHumanFormatting() {
        let response = FenceResponse.targets([:], defaultTarget: nil)
        XCTAssertEqual(response.humanFormatted(), "No targets configured")
    }

    func testTargetsResponseJSON() {
        let response = FenceResponse.targets(
            [
                "sim1": TargetConfig(device: "127.0.0.1:1455", token: "tok"),
                "sim2": TargetConfig(device: "127.0.0.1:1456"),
            ],
            defaultTarget: "sim1"
        )
        let json = response.jsonDict()!
        XCTAssertEqual(json["status"] as? String, "ok")
        XCTAssertEqual(json["default"] as? String, "sim1")
        let targets = json["targets"] as? [String: [String: Any]]
        XCTAssertNotNil(targets)
        XCTAssertEqual(targets?["sim1"]?["device"] as? String, "127.0.0.1:1455")
        XCTAssertEqual(targets?["sim1"]?["hasToken"] as? Bool, true)
        XCTAssertNil(targets?["sim2"]?["hasToken"])
    }

    func testTargetsResponseCompactFormatting() {
        let response = FenceResponse.targets(
            ["sim1": TargetConfig(device: "127.0.0.1:1455")],
            defaultTarget: "sim1"
        )
        let text = response.compactFormatted()
        XCTAssertTrue(text.contains("sim1"))
        XCTAssertTrue(text.contains("*"))
    }

    // MARK: - TheFence connect dispatch (with mock injection)

    private static let testDevice = DiscoveredDevice(
        id: "mock-device",
        name: "MockApp#test",
        endpoint: NWEndpoint.hostPort(host: .ipv6(.loopback), port: 1),
        certFingerprint: "sha256:mock"
    )

    private static let testServerInfo = ServerInfo(
        protocolVersion: "5.0",
        appName: "MockApp",
        bundleIdentifier: "com.test.mock",
        deviceName: "MockDevice",
        systemVersion: "18.0",
        screenWidth: 393,
        screenHeight: 852
    )

    @ButtonHeistActor
    private func makeMockFence(fileConfig: ButtonHeistFileConfig? = nil) -> TheFence {
        let mockConn = MockConnection()
        mockConn.serverInfo = Self.testServerInfo
        mockConn.autoResponse = { message in
            switch message {
            case .requestInterface:
                return .interface(Interface(timestamp: Date(), tree: []))
            case .explore:
                return .actionResult(ActionResult(
                    success: true, method: .explore,
                    exploreResult: ExploreResult(
                        elements: [], scrollCount: 0,
                        containersExplored: 0, explorationTime: 0
                    )
                ))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }

        let mockDisc = MockDiscovery()
        mockDisc.discoveredDevices = [Self.testDevice]

        let fence = TheFence(configuration: .init(fileConfig: fileConfig))
        fence.handoff.makeDiscovery = { mockDisc }
        fence.handoff.makeConnection = { _, _, _ in mockConn }

        makeReachabilityConnection = { _ in
            let probe = MockConnection()
            probe.emitTransportReadyOnConnect = true
            probe.autoResponse = { message in
                if case .status = message {
                    return .status(StatusPayload(
                        identity: StatusIdentity(
                            appName: "Mock", bundleIdentifier: "com.test",
                            appBuild: "1", deviceName: "Mock",
                            systemVersion: "18.0", buttonHeistVersion: "0.0.1"
                        ),
                        session: StatusSession(active: false, watchersAllowed: false, activeConnections: 0)
                    ))
                }
                return .actionResult(ActionResult(success: true, method: .activate))
            }
            return probe
        }

        return fence
    }

    @ButtonHeistActor
    func testConnectWithNamedTargetSwitchesConnection() async throws {
        let config = ButtonHeistFileConfig(
            targets: [
                "sim1": TargetConfig(device: "127.0.0.1:1455", token: "tok1"),
                "sim2": TargetConfig(device: "127.0.0.1:1456", token: "tok2"),
            ],
            defaultTarget: "sim1"
        )
        let fence = makeMockFence(fileConfig: config)

        let response = try await fence.execute(request: ["command": "connect", "target": "sim2"])
        guard case .interface = response else {
            XCTFail("Expected interface response, got \(response)")
            return
        }
        XCTAssertEqual(fence.config.deviceFilter, "127.0.0.1:1456")
        XCTAssertEqual(fence.config.token, "tok2")
    }

    @ButtonHeistActor
    func testConnectWithDirectDeviceSwitchesConnection() async throws {
        let fence = makeMockFence()

        let response = try await fence.execute(request: [
            "command": "connect",
            "device": "127.0.0.1:9999",
            "token": "direct-tok",
        ])
        guard case .interface = response else {
            XCTFail("Expected interface response, got \(response)")
            return
        }
        XCTAssertEqual(fence.config.deviceFilter, "127.0.0.1:9999")
        XCTAssertEqual(fence.config.token, "direct-tok")
    }

    @ButtonHeistActor
    func testConnectFailureRestoresPreviousConfig() async throws {
        let config = ButtonHeistFileConfig(
            targets: [
                "sim1": TargetConfig(device: "127.0.0.1:1455", token: "tok1"),
            ],
            defaultTarget: "sim1"
        )
        let fence = TheFence(configuration: .init(
            deviceFilter: "127.0.0.1:1455",
            token: "tok1",
            fileConfig: config
        ))

        // First connect attempt (new target) fails; second (restore) succeeds
        var connectAttempt = 0

        let mockDisc = MockDiscovery()
        mockDisc.discoveredDevices = [Self.testDevice]
        fence.handoff.makeDiscovery = { mockDisc }
        fence.handoff.makeConnection = { _, _, _ in
            connectAttempt += 1
            if connectAttempt == 1 {
                let failing = MockConnection()
                failing.connectEventsOverride = [
                    .transportReady,
                    .disconnected(.authFailed("denied")),
                ]
                return failing
            }
            let succeeding = MockConnection()
            succeeding.serverInfo = Self.testServerInfo
            succeeding.autoResponse = { _ in
                .actionResult(ActionResult(success: true, method: .activate))
            }
            return succeeding
        }

        makeReachabilityConnection = { _ in
            let probe = MockConnection()
            probe.emitTransportReadyOnConnect = true
            probe.autoResponse = { message in
                if case .status = message {
                    return .status(StatusPayload(
                        identity: StatusIdentity(
                            appName: "Mock", bundleIdentifier: "com.test",
                            appBuild: "1", deviceName: "Mock",
                            systemVersion: "18.0", buttonHeistVersion: "0.0.1"
                        ),
                        session: StatusSession(active: false, watchersAllowed: false, activeConnections: 0)
                    ))
                }
                return .actionResult(ActionResult(success: true, method: .activate))
            }
            return probe
        }

        let response = try await fence.execute(request: [
            "command": "connect",
            "device": "127.0.0.1:9999",
            "token": "bad-tok",
        ])
        if case .error(let message) = response {
            XCTAssertTrue(message.contains("restored previous connection"))
        } else {
            XCTFail("Expected error response, got \(response)")
        }
        // Previous config should be restored and connection re-established
        XCTAssertEqual(fence.config.deviceFilter, "127.0.0.1:1455")
        XCTAssertEqual(fence.config.token, "tok1")
        XCTAssertEqual(connectAttempt, 2)
    }

    @ButtonHeistActor
    func testConnectWithoutTargetOrDeviceReturnsError() async throws {
        let fence = TheFence()
        let response = try await fence.execute(request: ["command": "connect"])
        if case .error(let message) = response {
            XCTAssertTrue(message.contains("Must specify"))
        } else {
            XCTFail("Expected error response, got \(response)")
        }
    }

    @ButtonHeistActor
    func testConnectWithUnknownTargetReturnsError() async throws {
        let config = ButtonHeistFileConfig(
            targets: ["sim1": TargetConfig(device: "127.0.0.1:1455")],
            defaultTarget: "sim1"
        )
        let fence = TheFence(configuration: .init(fileConfig: config))
        let response = try await fence.execute(request: ["command": "connect", "target": "nonexistent"])
        if case .error(let message) = response {
            XCTAssertTrue(message.contains("Unknown target"))
            XCTAssertTrue(message.contains("sim1"))
        } else {
            XCTFail("Expected error response, got \(response)")
        }
    }

    @ButtonHeistActor
    func testConnectWithNoConfigFileReturnsError() async throws {
        let fence = TheFence()
        let response = try await fence.execute(request: ["command": "connect", "target": "sim1"])
        if case .error(let message) = response {
            XCTAssertTrue(message.contains("No config file"))
        } else {
            XCTFail("Expected error response, got \(response)")
        }
    }

    @ButtonHeistActor
    func testListTargetsWithNoConfig() async throws {
        let fence = TheFence()
        let response = try await fence.execute(request: ["command": "list_targets"])
        if case .targets(let targets, _) = response {
            XCTAssertTrue(targets.isEmpty)
        } else {
            XCTFail("Expected targets response, got \(response)")
        }
    }

    @ButtonHeistActor
    func testListTargetsWithConfig() async throws {
        let config = ButtonHeistFileConfig(
            targets: [
                "sim1": TargetConfig(device: "127.0.0.1:1455"),
                "sim2": TargetConfig(device: "127.0.0.1:1456"),
            ],
            defaultTarget: "sim1"
        )
        let fence = TheFence(configuration: .init(fileConfig: config))
        let response = try await fence.execute(request: ["command": "list_targets"])
        if case .targets(let targets, let defaultTarget) = response {
            XCTAssertEqual(targets.count, 2)
            XCTAssertEqual(defaultTarget, "sim1")
        } else {
            XCTFail("Expected targets response, got \(response)")
        }
    }

    // MARK: - TargetConfig Codable round-trip

    func testTargetConfigRoundTrip() throws {
        let original = TargetConfig(device: "127.0.0.1:1455", token: "secret")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TargetConfig.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testButtonHeistFileConfigRoundTrip() throws {
        let original = ButtonHeistFileConfig(
            targets: [
                "sim1": TargetConfig(device: "127.0.0.1:1455", token: "tok"),
                "sim2": TargetConfig(device: "127.0.0.1:1456"),
            ],
            defaultTarget: "sim1"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ButtonHeistFileConfig.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
