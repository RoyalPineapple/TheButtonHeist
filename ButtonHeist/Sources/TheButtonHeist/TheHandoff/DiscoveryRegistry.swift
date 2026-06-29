/// A single change in the discovered device list.
enum DiscoveryMutation: Equatable {
    case found(DiscoveredDevice)
    case lost(DiscoveredDevice)
}

/// Deduplicates Bonjour advertisements by device identity, tracking the newest per identity.
///
/// **Ownership.** Ephemeral index, owned by `DeviceDiscovery` (TheHandoff), for
/// the span of a discovery scan. Key: Bonjour service name, plus device identity
/// for the visible-selection index. Invalidation: `recordLost` evicts a service
/// name; a newer advertisement supersedes an older one for the same identity.
/// It cannot be derived from a receipt — the network emits raw add/remove
/// events and this is the dedup state that turns them into a stable device list.
/// See `docs/ARCHITECTURE.md#state-has-one-owner`.
struct DiscoveryRegistry {
    struct Advertisement {
        let serviceName: DiscoveryServiceName
        let device: DiscoveredDevice
        let identity: DiscoveryIdentity
        let sequence: UInt64
    }

    private var advertisementsByServiceName: [DiscoveryServiceName: Advertisement] = [:]
    private var visibleServiceNameByIdentity: [DiscoveryIdentity: DiscoveryServiceName] = [:]
    private var nextSequence: UInt64 = 0

    var devices: [DiscoveredDevice] {
        visibleServiceNameByIdentity.values
            .compactMap { advertisementsByServiceName[$0] }
            .sorted { lhs, rhs in lhs.sequence > rhs.sequence }
            .map(\.device)
    }

    mutating func recordFound(_ device: DiscoveredDevice) -> [DiscoveryMutation] {
        nextSequence &+= 1

        let serviceName = device.discoveryServiceName
        let advertisement = Advertisement(
            serviceName: serviceName,
            device: device,
            identity: device.discoveryIdentity,
            sequence: nextSequence
        )
        advertisementsByServiceName[serviceName] = advertisement

        let identity = advertisement.identity
        guard let visibleServiceName = visibleServiceNameByIdentity[identity] else {
            visibleServiceNameByIdentity[identity] = serviceName
            return [.found(device)]
        }

        guard visibleServiceName != serviceName else {
            return []
        }

        if let previous = advertisementsByServiceName[visibleServiceName] {
            visibleServiceNameByIdentity[identity] = serviceName
            return [.lost(previous.device), .found(device)]
        }

        visibleServiceNameByIdentity[identity] = serviceName
        return [.found(device)]
    }

    mutating func recordLost(_ serviceName: DiscoveryServiceName) -> [DiscoveryMutation] {
        guard let removed = advertisementsByServiceName.removeValue(forKey: serviceName) else {
            return []
        }

        let identity = removed.identity
        guard visibleServiceNameByIdentity[identity] == serviceName else {
            return []
        }

        if let replacement = newestAdvertisement(for: identity) {
            visibleServiceNameByIdentity[identity] = replacement.serviceName
            return [.lost(removed.device), .found(replacement.device)]
        }

        visibleServiceNameByIdentity.removeValue(forKey: identity)
        return [.lost(removed.device)]
    }

    private func newestAdvertisement(for identity: DiscoveryIdentity) -> Advertisement? {
        advertisementsByServiceName.values
            .filter { $0.identity == identity }
            .max { lhs, rhs in lhs.sequence < rhs.sequence }
    }
}
