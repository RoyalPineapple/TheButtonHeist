import Network

extension DeviceDiscovery {
    func makeDevice(from result: NWBrowser.Result) -> DiscoveredDevice? {
        guard case let .service(name, _, _, _) = result.endpoint else {
            return nil
        }
        let serviceName = DiscoveryServiceName(name)

        let txtRecord = result.endpoint.txtRecord ?? {
            if case .bonjour(let metadataTXTRecord) = result.metadata {
                return metadataTXTRecord
            }
            return nil
        }()

        var simUDID: String?
        var installationId: String?
        var displayDeviceName: String?
        var instanceId: String?
        if let txtRecord {
            simUDID = txtRecord[TXTRecordKey.simUDID.rawValue]
            installationId = txtRecord[TXTRecordKey.installationId.rawValue]
            displayDeviceName = txtRecord[TXTRecordKey.deviceName.rawValue]
            instanceId = txtRecord[TXTRecordKey.instanceId.rawValue]
        }

        return DiscoveredDevice(
            deviceID: .serviceName(serviceName),
            name: serviceName.rawValue,
            endpoint: result.endpoint,
            simulatorUDID: simUDID,
            installationId: installationId,
            displayDeviceName: displayDeviceName,
            instanceId: instanceId
        )
    }
}
