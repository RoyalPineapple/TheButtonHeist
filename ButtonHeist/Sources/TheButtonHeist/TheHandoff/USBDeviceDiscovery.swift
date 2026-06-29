#if os(macOS)
import Foundation
import Network
import os.log

import TheScore

private let logger = ButtonHeistLog.logger(.handoff(.usbDiscovery))

/// Discovers iOS devices connected over USB via CoreDevice IPv6 tunnels.
///
/// Polls periodically using `xcrun devicectl` and `lsof` to find connected devices
/// and their IPv6 tunnel addresses. Produces `DiscoveredDevice` instances that work
/// identically to Bonjour-discovered devices — same wire protocol, same connection path.
///
/// Subprocess execution runs on detached tasks to avoid blocking the actor.
@ButtonHeistActor
final class USBDeviceDiscovery: DeviceDiscovering {

    private let port: UInt16
    private var pollTask: Task<Void, Never>?
    private var knownDevices: [DiscoveryDeviceID: DiscoveredDevice] = [:]

    var onEvent: (@ButtonHeistActor (DiscoveryEvent) -> Void)?

    var discoveredDevices: [DiscoveredDevice] {
        Array(knownDevices.values)
    }

    /// - Parameter port: The InsideJob port to connect to on the device
    init(port: UInt16) {
        self.port = port
    }

    func start() {
        logger.info("Starting USB device discovery (port \(self.port))")
        onEvent?(.stateChanged(isReady: true))
        startPolling()
    }

    func stop() {
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
        async let connectedDevicesTask = Self.discoverConnectedUSBDevices()
        async let ipv6AddressTask = Self.findIPv6Tunnel()
        let connectedDevices = await connectedDevicesTask
        let ipv6Address = await ipv6AddressTask

        guard let ipv6Address else {
            for (id, device) in knownDevices {
                knownDevices.removeValue(forKey: id)
                onEvent?(.lost(device))
            }
            return
        }

        guard connectedDevices.count == 1 else {
            if connectedDevices.count > 1 {
                logger.warning("Multiple USB devices are connected; CoreDevice tunnel correlation is ambiguous, so USB discovery is disabled")
            }
            for (id, device) in knownDevices {
                knownDevices.removeValue(forKey: id)
                onEvent?(.lost(device))
            }
            return
        }

        var currentIDs = Set<DiscoveryDeviceID>()

        for connectedDevice in connectedDevices {
            let deviceID = DiscoveryDeviceID.usbIdentifier(connectedDevice.identifier)
            currentIDs.insert(deviceID)

            if knownDevices[deviceID] == nil {
                guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                    logger.error("Invalid port number: \(self.port)")
                    return
                }
                let endpoint = NWEndpoint.hostPort(
                    host: NWEndpoint.Host(ipv6Address),
                    port: nwPort
                )
                let device = DiscoveredDevice(
                    deviceID: deviceID,
                    name: "\(connectedDevice.name) (USB)",
                    endpoint: endpoint,
                    displayDeviceName: connectedDevice.name,
                    connectionType: .usb
                )
                knownDevices[deviceID] = device
                logger.info("USB device found: \(connectedDevice.name) at \(ipv6Address):\(self.port)")
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

    struct ConnectedUSBDevice: Equatable {
        let name: String
        let identifier: String
    }

    /// Run `xcrun devicectl list devices` and return connected USB device identities.
    private static func discoverConnectedUSBDevices() async -> [ConnectedUSBDevice] {
        guard let output = await runProcess(
            "/usr/bin/xcrun",
            arguments: ["devicectl", "list", "devices"],
            timeout: 10
        ) else {
            return []
        }

        return parseConnectedUSBDevices(from: output)
    }

    static func parseConnectedDeviceNames(from output: String) -> [String] {
        parseConnectedUSBDevices(from: output).map(\.name)
    }

    static func parseConnectedUSBDevices(from output: String) -> [ConnectedUSBDevice] {
        var devices: [ConnectedUSBDevice] = []
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

            guard columns.count >= 4 else { continue }
            let name = columns[0]
            let identifier = columns[2]
            guard !name.isEmpty, !identifier.isEmpty else { continue }
            let hasConnectedState = columns.contains { $0.caseInsensitiveCompare("connected") == .orderedSame }
            guard hasConnectedState else { continue }

            devices.append(ConnectedUSBDevice(name: name, identifier: identifier))
        }

        return devices
    }

    /// Run `lsof -i -P -n` and extract the CoreDevice IPv6 tunnel address.
    private static func findIPv6Tunnel() async -> String? {
        guard let output = await runProcess(
            "/usr/sbin/lsof",
            arguments: ["-i", "-P", "-n"],
            timeout: 5
        ) else {
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

    private static func runProcess(
        _ path: String,
        arguments: [String],
        timeout: TimeInterval
    ) async -> String? {
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
            do {
                try FileManager.default.removeItem(at: outputURL)
            } catch {
                logger.debug("Failed to remove temporary output file: \(error.localizedDescription)")
            }
            return nil
        }
        defer {
            outputHandle.closeFile()
            do {
                try FileManager.default.removeItem(at: outputURL)
            } catch {
                logger.debug("Failed to remove temporary output file: \(error.localizedDescription)")
            }
        }

        process.standardOutput = outputHandle
        process.standardError = FileHandle.nullDevice

        // Schedule a terminate after `timeout`. If the process exits first, cancel.
        // When process exits naturally OR via terminate, the terminationHandler
        // fires exactly once and resumes the continuation below.
        let timeoutTask = Task {
            guard await Task<Never, Never>.cancellableSleep(nanoseconds: UInt64(timeout * 1_000_000_000)) else { return }
            if process.isRunning {
                logger.debug("Timed out running \(path) after \(timeout)s")
                process.terminate()
            }
        }
        defer { timeoutTask.cancel() }

        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in cont.resume() }
                do {
                    try process.run()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        } catch {
            logger.debug("Failed to run \(path): \(error.localizedDescription)")
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        // Safe to read before `outputHandle.closeFile()` runs in the defer: the
        // child has exited and flushed its dup'd fd, and the kernel page cache
        // serves reads from the same file regardless of open write handles.
        let data: Data
        do {
            data = try Data(contentsOf: outputURL)
        } catch {
            logger.debug("Failed to read output of \(path): \(error.localizedDescription)")
            return nil
        }

        return String(data: data, encoding: .utf8)
    }
}
#endif // os(macOS)
