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
        async let connectedDevicesTask = Self.discoverConnectedDevices()
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
    private static func discoverConnectedDevices() async -> [String] {
        guard let output = await runProcess(
            "/usr/bin/xcrun",
            arguments: ["devicectl", "list", "devices"],
            timeout: 10
        ) else {
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
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }
        defer {
            outputHandle.closeFile()
            try? FileManager.default.removeItem(at: outputURL)
        }

        process.standardOutput = outputHandle
        process.standardError = FileHandle.nullDevice

        // Schedule a terminate after `timeout`. If the process exits first, cancel.
        // When process exits naturally OR via terminate, the terminationHandler
        // fires exactly once and resumes the continuation below.
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
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
        guard let data = try? Data(contentsOf: outputURL) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }
}
#endif // os(macOS)
