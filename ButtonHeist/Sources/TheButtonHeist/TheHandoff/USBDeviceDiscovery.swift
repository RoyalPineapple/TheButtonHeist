#if os(macOS)
import Foundation
import Network
import os.log

private let logger = Logger(subsystem: "com.buttonheist.thehandoff", category: "usb-discovery")

/// Discovers iOS devices connected over USB via CoreDevice IPv6 tunnels.
///
/// Polls periodically using `xcrun devicectl` and `lsof` to find connected devices
/// and their IPv6 tunnel addresses. Produces `DiscoveredDevice` instances that work
/// identically to Bonjour-discovered devices — same wire protocol, same connection path.
///
/// Subprocess execution runs on detached tasks to avoid blocking the actor.
@ButtonHeistActor
public final class USBDeviceDiscovery: DeviceDiscovering {

    private let port: UInt16
    private var pollTask: Task<Void, Never>?
    private var knownDevices: [String: DiscoveredDevice] = [:]

    public var onEvent: ((DiscoveryEvent) -> Void)?

    public var discoveredDevices: [DiscoveredDevice] {
        Array(knownDevices.values)
    }

    /// - Parameter port: The InsideJob port to connect to on the device
    public init(port: UInt16) {
        self.port = port
    }

    public func start() {
        logger.info("Starting USB device discovery (port \(self.port))")
        onEvent?(.stateChanged(isReady: true))
        startPolling()
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
        knownDevices.removeAll()
    }

    // MARK: - Private

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                guard await Task<Never, Never>.cancellableSleep(nanoseconds: 3_000_000_000) else { break }
            }
        }
    }

    private func poll() async {
        let (connectedDevices, ipv6Address) = await Task.detached { () -> ([String], String?) in
            let devices = Self.discoverConnectedDevices()
            let address = Self.findIPv6Tunnel()
            return (devices, address)
        }.value

        guard let ipv6Address else {
            for (id, device) in knownDevices {
                knownDevices.removeValue(forKey: id)
                onEvent?(.lost(device))
            }
            return
        }

        var currentIDs = Set<String>()

        for deviceName in connectedDevices {
            let id = "usb-\(deviceName)"
            currentIDs.insert(id)

            if knownDevices[id] == nil {
                guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                    logger.error("Invalid port number: \(self.port)")
                    return
                }
                let endpoint = NWEndpoint.hostPort(
                    host: NWEndpoint.Host(ipv6Address),
                    port: nwPort
                )
                let device = DiscoveredDevice(
                    id: id,
                    name: "\(deviceName) (USB)",
                    endpoint: endpoint
                )
                knownDevices[id] = device
                logger.info("USB device found: \(deviceName) at \(ipv6Address):\(self.port)")
                onEvent?(.found(device))
            }
        }

        for (id, device) in knownDevices where !currentIDs.contains(id) {
            knownDevices.removeValue(forKey: id)
            logger.info("USB device lost: \(device.name)")
            onEvent?(.lost(device))
        }
    }

}

// MARK: - Subprocess Utilities

nonisolated extension USBDeviceDiscovery {

    /// Run `xcrun devicectl list devices` and return names of connected devices.
    private static func discoverConnectedDevices() -> [String] {
        guard let output = runProcess("/usr/bin/xcrun", arguments: ["devicectl", "list", "devices"], timeout: 10) else {
            return []
        }

        return parseConnectedDeviceNames(from: output)
    }

    static func parseConnectedDeviceNames(from output: String) -> [String] {
        var devices: [String] = []

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard !trimmed.contains("Identifier"), !trimmed.hasPrefix("---") else { continue }

            // devicectl table columns are separated by 2+ spaces; this preserves
            // device names that contain single spaces.
            let columns = trimmed
                .replacingOccurrences(of: #"\s{2,}"#, with: "\t", options: .regularExpression)
                .components(separatedBy: "\t")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            guard let name = columns.first, !name.isEmpty else { continue }
            let hasConnectedState = columns.contains { $0.caseInsensitiveCompare("connected") == .orderedSame }
            guard hasConnectedState else { continue }

            devices.append(name)
        }

        return devices
    }

    /// Run `lsof -i -P -n` and extract the CoreDevice IPv6 tunnel address.
    private static func findIPv6Tunnel() -> String? {
        guard let output = runProcess("/usr/sbin/lsof", arguments: ["-i", "-P", "-n"], timeout: 5) else {
            return nil
        }

        let pattern = #"\[(fd[0-9a-f:]+)::[12]\]"#
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern)
        } catch {
            logger.error("Invalid IPv6 tunnel regex: \(error.localizedDescription)")
            return nil
        }

        guard let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let prefixRange = Range(match.range(at: 1), in: output) else {
            return nil
        }

        let prefix = String(output[prefixRange])
        return "\(prefix)::1"
    }

    private static func runProcess(_ path: String, arguments: [String], timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("buttonheist-usb-discovery-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else {
            logger.debug("Failed to create temporary output file for \(path)")
            return nil
        }
        guard let outputHandle = FileHandle(forWritingAtPath: outputURL.path) else {
            logger.debug("Failed to open temporary output file for \(path)")
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }
        defer {
            outputHandle.closeFile()
            try? FileManager.default.removeItem(at: outputURL)
        }

        process.standardOutput = outputHandle
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            logger.debug("Failed to run \(path): \(error.localizedDescription)")
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }

        guard !process.isRunning else {
            logger.debug("Timed out running \(path) after \(timeout)s")
            process.terminate()
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        guard let data = try? Data(contentsOf: outputURL) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }
}
#endif // os(macOS)
