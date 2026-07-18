import Network
import TheScore

extension DeviceDiscovery {
    func makeDevice(from result: NWBrowser.Result) -> DiscoveredDevice? {
        guard case let .service(name, type, domain, _) = result.endpoint else {
            return nil
        }
        guard let deviceID = try? DiscoveryDeviceID(validating: name) else { return nil }

        let txtRecord = result.endpoint.txtRecord ?? {
            if case .bonjour(let metadataTXTRecord) = result.metadata {
                return metadataTXTRecord
            }
            return nil
        }()

        var simUDID: SimulatorUDID?
        var installationId: InstallationID?
        var displayDeviceName: String?
        var instanceId: InsideJobInstanceID?
        if let txtRecord {
            simUDID = txtRecord[TXTRecordKey.simUDID.rawValue]
                .flatMap { try? SimulatorUDID(validating: $0) }
            installationId = txtRecord[TXTRecordKey.installationId.rawValue]
                .flatMap { try? InstallationID(validating: $0) }
            displayDeviceName = txtRecord[TXTRecordKey.deviceName.rawValue]
            instanceId = txtRecord[TXTRecordKey.instanceId.rawValue]
                .flatMap { try? InsideJobInstanceID(validating: $0) }
        }

        return DiscoveredDevice(
            id: deviceID,
            name: name,
            endpoint: .service(name: name, type: type, domain: domain),
            simulatorUDID: simUDID,
            installationId: installationId,
            displayDeviceName: displayDeviceName,
            instanceId: instanceId
        )
    }
}
