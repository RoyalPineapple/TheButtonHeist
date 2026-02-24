#if os(macOS)
import Foundation
import Network
import os.log

private let logger = Logger(subsystem: "com.buttonheist.wheelman", category: "usb-discovery")

/// Discovers iOS devices connected over USB via CoreDevice IPv6 tunnels.
///
/// Polls periodically using `xcrun devicectl` and `lsof` to find connected devices
/// and their IPv6 tunnel addresses. Produces `DiscoveredDevice` instances that work
/// identically to Bonjour-discovered devices — same wire protocol, same connection path.
@MainActor
public final class USBDeviceDiscovery {

    private let port: UInt16
    private var timer: Timer?
    private var knownDevices: [String: DiscoveredDevice] = [:]

    public var onDeviceFound: ((DiscoveredDevice) -> Void)?
    public var onDeviceLost: ((DiscoveredDevice) -> Void)?

    /// - Parameter port: The InsideMan port to connect to (default 1455, configured in Info.plist)
    public init(port: UInt16 = 1455) {
        self.port = port
    }

    public func start() {
        logger.info("Starting USB device discovery (port \(self.port))")
        // Run immediately, then poll
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        knownDevices.removeAll()
    }

    // MARK: - Private

    private func poll() {
        let connectedDevices = discoverConnectedDevices()
        guard let ipv6Address = findIPv6Tunnel() else {
            // No tunnel — remove all USB devices
            for (id, device) in knownDevices {
                knownDevices.removeValue(forKey: id)
                onDeviceLost?(device)
            }
            return
        }

        // Build set of current device IDs
        var currentIDs = Set<String>()

        for deviceName in connectedDevices {
            let id = "usb-\(deviceName)"
            currentIDs.insert(id)

            if knownDevices[id] == nil {
                let endpoint = NWEndpoint.hostPort(
                    host: NWEndpoint.Host(ipv6Address),
                    port: NWEndpoint.Port(rawValue: port)!
                )
                let device = DiscoveredDevice(
                    id: id,
                    name: "\(deviceName) (USB)",
                    endpoint: endpoint
                )
                knownDevices[id] = device
                logger.info("USB device found: \(deviceName) at \(ipv6Address):\(self.port)")
                onDeviceFound?(device)
            }
        }

        // Remove devices that are no longer connected
        for (id, device) in knownDevices where !currentIDs.contains(id) {
            knownDevices.removeValue(forKey: id)
            logger.info("USB device lost: \(device.name)")
            onDeviceLost?(device)
        }
    }

    /// Run `xcrun devicectl list devices` and return names of connected devices.
    private func discoverConnectedDevices() -> [String] {
        guard let output = runProcess("/usr/bin/xcrun", arguments: ["devicectl", "list", "devices"], timeout: 10) else {
            return []
        }

        var devices: [String] = []
        for line in output.components(separatedBy: "\n") {
            // Lines with "connected" status indicate USB-attached devices
            guard line.contains("connected") else { continue }
            // Skip header lines
            guard !line.contains("Identifier") && !line.contains("---") else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Device name is the first column
            let columns = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if let name = columns.first, !name.isEmpty {
                devices.append(name)
            }
        }
        return devices
    }

    /// Run `lsof -i -P -n` and extract the CoreDevice IPv6 tunnel address.
    /// Returns an address like `fd9a:6190:eed7::1` or nil.
    private func findIPv6Tunnel() -> String? {
        guard let output = runProcess("/usr/sbin/lsof", arguments: ["-i", "-P", "-n"], timeout: 5) else {
            return nil
        }

        // Look for CoreDevice tunnel entries with fd-prefixed IPv6 ULA addresses
        // Pattern: [fd9a:6190:eed7::1] or [fd9a:6190:eed7::2]
        let pattern = #"\[(fd[0-9a-f:]+)::[12]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let prefixRange = Range(match.range(at: 1), in: output) else {
            return nil
        }

        let prefix = String(output[prefixRange])
        return "\(prefix)::1"
    }

    /// Run a subprocess and return its stdout, or nil on failure.
    private func runProcess(_ path: String, arguments: [String], timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            logger.debug("Failed to run \(path): \(error.localizedDescription)")
            return nil
        }

        // Read output with timeout
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }
}
#endif
