import Foundation

@ButtonHeistActor
extension TheFence {

    // MARK: - Handler: List Devices

    func handleListDevices() async throws -> FenceResponse {
        var devices = await handoff.discoverReachableDevices()
        if let fileConfig = config.fileConfig {
            let configDevices = Self.configTargetsAsDevices(fileConfig)
            let existingIDs = Set(devices.map(\.id))
            for device in configDevices where !existingIDs.contains(device.id) {
                devices.append(device)
            }
        }
        return .devices(devices)
    }

    // MARK: - Handler: Connect

    private func establishSessionOnly() async throws -> FenceResponse {
        try await start()
        return .sessionState(payload: currentSessionState())
    }

    func handleConnect(_ request: ConnectRequest) async throws -> FenceResponse {
        let resolvedDevice: String
        let resolvedToken: String?
        let resolvedDirectDevice: DiscoveredDevice?

        if let device = request.device {
            resolvedDevice = device
            resolvedToken = request.token
            resolvedDirectDevice = nil
        } else if let targetName = request.targetName {
            guard let fileConfig = config.fileConfig else {
                throw FenceError.invalidRequest(
                    "No config file loaded. Create .buttonheist.json or ~/.config/buttonheist/config.json"
                )
            }
            guard let target = fileConfig.targets[targetName] else {
                let available = fileConfig.targets.keys.sorted()
                throw FenceError.invalidRequest(
                    "Unknown target '\(targetName)'. Available: \(available.joined(separator: ", "))"
                )
            }
            resolvedDevice = target.device
            resolvedToken = request.token ?? target.token
            resolvedDirectDevice = DiscoveredDevice.fromHostPort(
                target.device,
                id: "config-\(targetName)",
                name: targetName
            )
        } else if handoff.isConnected || config.deviceFilter != nil || config.directDevice != nil {
            return try await establishSessionOnly()
        } else {
            throw FenceError.invalidRequest(
                "Must specify 'target' (named config target), 'device' (host:port), or configure BUTTONHEIST_DEVICE/.buttonheist.json"
            )
        }

        stop()

        handoff.token = resolvedToken
        let newConfig = Configuration(
            deviceFilter: resolvedDevice,
            connectionTimeout: config.connectionTimeout,
            token: resolvedToken,
            autoReconnect: config.autoReconnect,
            fileConfig: config.fileConfig,
            directDevice: resolvedDirectDevice,
            artifactBaseDirectory: config.artifactBaseDirectory
        )
        config = newConfig

        do {
            try await start()
        } catch let connectionFailure as FenceError {
            handoff.disableAutoReconnect()
            handoff.stopDiscovery()
            clearClientSessionState(error: connectionFailure)
            return .error(DiagnosticFailure(
                message: "Connect failed; disconnected from previous target: \(connectionFailure.coreMessage)",
                details: connectionFailure.failureDetails
            ))
        }

        return .sessionState(payload: currentSessionState())
    }

    func handleListTargets() -> FenceResponse {
        guard let fileConfig = config.fileConfig else {
            return .targets([:], defaultTarget: nil)
        }
        return .targets(fileConfig.targets, defaultTarget: fileConfig.defaultTarget)
    }

}
