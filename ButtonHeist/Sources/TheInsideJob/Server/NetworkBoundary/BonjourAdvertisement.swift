import Foundation
import os.log

import TheScore

private let logger = ButtonHeistLog.logger(.handoff(.transport))

/// Bonjour `NetService` advertisement and TXT record state.
final class BonjourAdvertisement: NSObject {
    @MainActor private var netService: NetService?
    @MainActor private var currentTXT: [String: Data] = [:]

    @MainActor
    var isAdvertising: Bool {
        netService != nil
    }

    @MainActor
    var currentTXTRecord: [String: Data] {
        currentTXT
    }

    @MainActor
    func publish(
        serviceName: String,
        port: UInt16,
        simulatorUDID: String? = nil,
        installationId: String? = nil,
        instanceId: String? = nil,
        additionalTXT: [String: String] = [:]
    ) {
        guard port > 0 else {
            logger.error("Cannot advertise: server not started")
            return
        }

        stop()

        let service = NetService(
            domain: "local.",
            type: buttonHeistServiceType,
            name: serviceName,
            port: Int32(port)
        )

        var txtDict: [String: Data] = [:]
        if let simUDID = simulatorUDID, let data = simUDID.data(using: .utf8) {
            txtDict[TXTRecordKey.simUDID.rawValue] = data
        }
        if let installationId, let data = installationId.data(using: .utf8) {
            txtDict[TXTRecordKey.installationId.rawValue] = data
        }
        if let id = instanceId, let data = id.data(using: .utf8) {
            txtDict[TXTRecordKey.instanceId.rawValue] = data
        }
        for (key, value) in additionalTXT {
            if let data = value.data(using: .utf8) {
                txtDict[key] = data
            }
        }
        txtDict[TXTRecordKey.transport.rawValue] = Data("tls-psk".utf8)

        currentTXT = txtDict
        service.setTXTRecord(NetService.data(fromTXTRecord: txtDict))

        netService = service
        netService?.delegate = self
        netService?.publish()
        logger.info("Advertising as '\(serviceName)' on port \(port)")
    }

    @MainActor
    func updateTXTRecord(_ entries: [String: String]) {
        guard let service = netService else {
            logger.warning("Cannot update TXT record: not advertising")
            return
        }

        for (key, value) in entries {
            if let data = value.data(using: .utf8) {
                currentTXT[key] = data
            }
        }
        service.setTXTRecord(NetService.data(fromTXTRecord: currentTXT))
    }

    @MainActor
    func stop() {
        netService?.stop()
        netService = nil
        currentTXT.removeAll()
    }
}

extension BonjourAdvertisement: NetServiceDelegate {

    nonisolated func netServiceDidPublish(_ sender: NetService) {
        logger.info("Bonjour service published: '\(sender.name)' on port \(sender.port)")
    }

    nonisolated func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        let code = errorDict[NetService.errorCode]?.intValue ?? -1
        let domain = errorDict[NetService.errorDomain]?.intValue ?? -1
        logger.error("Bonjour publish failed for '\(sender.name)': error \(code) domain \(domain)")
    }
}
