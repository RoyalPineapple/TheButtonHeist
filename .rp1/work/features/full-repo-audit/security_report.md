# Security Validation Report

**Feature ID**: full-repo-audit
**Security Scope**: full
**Compliance Framework**: N/A (general security best practices)
**Analysis Date**: 2026-02-24

## Executive Summary
**Security Posture**: Needs Attention

ButtonHeist is a developer/testing tool that gives AI agents and CLI tools remote control over iOS apps via a TCP server embedded in the target app. The security model intentionally opens a powerful control surface (synthetic touch injection, screen capture, accessibility tree traversal, text input) for development and testing purposes. The core security concern is that this control surface uses **unauthenticated, unencrypted plaintext TCP** and is discoverable via Bonjour mDNS, meaning any device on the same local network segment can discover, connect to, and fully control any app running InsideMan.

While the `#if DEBUG` compile-time guard is the primary safety mechanism (preventing inclusion in release builds), there are several areas where the security posture could be strengthened, particularly around network exposure, protocol security, buffer handling, and the presence of high-privilege research artifacts in the repository.

## Vulnerability Summary
- **Critical**: 1 - Unauthenticated remote app control over plaintext TCP
- **High**: 3 - No TLS, unbounded buffer growth, private entitlements in repo
- **Medium**: 4 - No rate limiting, information leakage, broad port binding, port scanning in USB script
- **Low**: 3 - Missing input validation bounds, debug logging verbosity, shell injection potential
- **Informational**: 3 - Private API usage, `#if DEBUG` guard reliance, dependency supply chain

---

## Critical Security Findings

### CRIT-1: Unauthenticated Remote App Control Over Network
**Severity**: Critical
**Location**: `/Users/aodawa/conductor/workspaces/accra/curitiba/ButtonHeist/Sources/Wheelman/SimpleSocketServer.swift` (lines 37-84) and `/Users/aodawa/conductor/workspaces/accra/curitiba/ButtonHeist/Sources/InsideMan/InsideMan.swift` (lines 72-110)
**Evidence**: The TCP server accepts all incoming connections without any form of authentication:
```swift
// SimpleSocketServer.swift line 66-68
newListener.newConnectionHandler = { [weak self] connection in
    self?.handleNewConnection(connection)
}
```
The Bonjour service is advertised to the entire local network:
```swift
// InsideMan.swift line 165-168
let service = NetService(
    domain: "local.",
    type: buttonHeistServiceType,
    name: serviceName,
    port: Int32(port)
)
```
**Impact**: Any device on the same network (e.g., shared WiFi in an office, coffee shop, or conference) can discover the service via mDNS, connect, and perform any action: capture screenshots (exposing on-screen content including sensitive data), read the full accessibility hierarchy, inject synthetic touches (tap buttons, fill forms, navigate), type arbitrary text into focused fields, and perform clipboard operations (copy, paste, cut). This is effectively full remote control of the app with zero authentication.
**Remediation**: Implement at minimum a shared-secret token challenge on connection (e.g., a random token displayed in Xcode console that the client must present). For stronger security, implement TLS with mutual authentication or restrict binding to the loopback interface when not in USB mode.

---

## High Severity Findings

### HIGH-1: No Transport Encryption (Plaintext TCP)
**Severity**: High
**Location**: `/Users/aodawa/conductor/workspaces/accra/curitiba/ButtonHeist/Sources/Wheelman/SimpleSocketServer.swift` (line 38)
**Evidence**:
```swift
let parameters = NWParameters.tcp
```
The Network framework supports TLS natively via `NWParameters(tls:)` but only raw TCP is used.
**Impact**: All data is transmitted in cleartext, including full UI hierarchy (which may contain user data displayed on screen), base64-encoded screenshots of the app, text typed into fields, and device identifiers. On shared networks, any passive observer can capture this traffic.
**Remediation**: Use `NWParameters(tls: NWProtocolTLS.Options())` for encrypted connections. The Network framework makes this straightforward. At minimum, consider optional TLS with self-signed certificates for development convenience.

### HIGH-2: Unbounded Receive Buffer Growth
**Severity**: High
**Location**: `/Users/aodawa/conductor/workspaces/accra/curitiba/ButtonHeist/Sources/Wheelman/SimpleSocketServer.swift` (lines 172-205) and `/Users/aodawa/conductor/workspaces/accra/curitiba/ButtonHeist/Sources/Wheelman/DeviceConnection.swift` (lines 90-116)
**Evidence**:
```swift
// SimpleSocketServer.swift - server side
private func receiveNextChunk(clientId: Int, connection: NWConnection, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { ... in
        var messageBuffer = buffer
        if let content {
            messageBuffer.append(content)
        }
        // Process newline-delimited messages
        while let newlineIndex = messageBuffer.firstIndex(of: 0x0A) { ... }
        // If no newline found, keeps accumulating...
        self.receiveNextChunk(clientId: clientId, connection: connection, buffer: messageBuffer)
    }
}
```
```swift
// DeviceConnection.swift - client side
if let content {
    self.receiveBuffer.append(content)
    self.processBuffer()
}
```
**Impact**: A malicious client can send data without newline delimiters, causing the buffer to grow indefinitely until the process exhausts available memory. On the iOS side, this would crash the host app. On the macOS client side, it would crash the MCP server or CLI tool. This is a denial-of-service vector.
**Remediation**: Implement a maximum buffer size (e.g., 10 MB). If the buffer exceeds this threshold without a complete message, disconnect the client. Example: `guard messageBuffer.count < 10_000_000 else { removeClient(clientId); return }`.

### HIGH-3: Private Entitlements Plist in Repository
**Severity**: High
**Location**: `/Users/aodawa/conductor/workspaces/accra/curitiba/test-aoo/test-aoo/PrivateAccessibilityEntitlements.plist`
**Evidence**:
```xml
<key>com.apple.private.security.no-sandbox</key>
<true/>
<key>com.apple.private.skip-library-validation</key>
<true/>
<key>com.apple.private.tcc.allow</key>
<array>
    <string>kTCCServiceAccessibility</string>
</array>
```
This file grants sandbox escape, library validation bypass, TCC bypass for accessibility, platform-application status, and XPC server capabilities. The companion script at `/Users/aodawa/conductor/workspaces/accra/curitiba/test-aoo/scripts/sign-with-private-entitlements.sh` provides instructions for applying these to apps via `ldid` for jailbroken devices and TrollStore.
**Impact**: If these entitlements were accidentally applied to a build distributed beyond the development team, they would grant the app extremely broad privileges including sandbox escape and accessibility TCC bypass. The script and entitlements together serve as a ready-made privilege escalation toolkit.
**Remediation**: Move this file and the signing script out of the main repository. If they must remain, add prominent warnings, ensure they are in `.gitignore` for any CI/CD pipelines, and add a pre-commit hook that prevents committing changes to this file without explicit acknowledgment.

---

## Medium Severity Findings

### MED-1: No Rate Limiting on TCP Server
**Severity**: Medium
**Location**: `/Users/aodawa/conductor/workspaces/accra/curitiba/ButtonHeist/Sources/Wheelman/SimpleSocketServer.swift` (lines 66-68, 133-157)
**Evidence**: The server accepts unlimited connections and processes messages at the rate they arrive. There is no per-client rate limiting, no maximum connection count, and no message throttling.
**Impact**: A malicious client could flood the server with rapid requests (e.g., `requestScreen` which triggers a full UI render and PNG encode, or `requestInterface` which triggers accessibility tree parsing), causing the main thread to become unresponsive and the host app to appear frozen or crash.
**Remediation**: Implement a maximum connection count (e.g., 5 simultaneous clients) and per-message rate limiting (e.g., maximum 10 screen capture requests per second).

### MED-2: Information Leakage in Server Info and Bonjour Advertisement
**Severity**: Medium
**Location**: `/Users/aodawa/conductor/workspaces/accra/curitiba/ButtonHeist/Sources/InsideMan/InsideMan.swift` (lines 266-282) and (lines 160-189)
**Evidence**:
```swift
let info = ServerInfo(
    protocolVersion: protocolVersion,
    appName: Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App",
    bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
    deviceName: UIDevice.current.name,
    systemVersion: UIDevice.current.systemVersion,
    screenWidth: screenBounds.width,
    screenHeight: screenBounds.height,
    instanceId: sessionId.uuidString,
    listeningPort: socketServer?.listeningPort,
    simulatorUDID: ProcessInfo.processInfo.environment["SIMULATOR_UDID"],
    vendorIdentifier: UIDevice.current.identifierForVendor?.uuidString
)
```
Bonjour TXT records include `simudid` and `vendorid`, and the service name format is `{AppName}-{DeviceName}#shortId`.
**Impact**: Without even connecting, anyone on the local network can discover: the app name, device name (often personalized, e.g., "John's iPhone"), and device identifiers. Upon connecting, additional metadata including iOS version, bundle ID, screen dimensions, and vendor identifier are disclosed. This information could be used for targeted attacks or privacy violations.
**Remediation**: Consider reducing the information exposed in Bonjour advertisements (e.g., use a hash instead of readable names). Defer detailed server info to after authentication if an auth mechanism is added.

### MED-3: Server Binds to All Interfaces (IPv6 Any)
**Severity**: Medium
**Location**: `/Users/aodawa/conductor/workspaces/accra/curitiba/ButtonHeist/Sources/Wheelman/SimpleSocketServer.swift` (lines 38-42)
**Evidence**:
```swift
let parameters = NWParameters.tcp
parameters.requiredLocalEndpoint = .hostPort(
    host: .ipv6(.any),
    port: NWEndpoint.Port(rawValue: port) ?? .any
)
```
**Impact**: The server listens on all network interfaces, including WiFi. For simulator-only development workflows, binding to loopback (`::1` or `127.0.0.1`) would be sufficient and far more secure. The current configuration exposes the server to the entire local network.
**Remediation**: Add a configuration option to restrict binding to loopback only. Default to loopback for simulator builds and allow explicit opt-in for physical device testing that requires WiFi or USB connectivity.

### MED-4: Port Scanning in USB Connection Script
**Severity**: Medium
**Location**: `/Users/aodawa/conductor/workspaces/accra/curitiba/scripts/buttonheist_usb.py` (lines 296-306)
**Evidence**:
```python
import concurrent.futures
with concurrent.futures.ThreadPoolExecutor(max_workers=50) as executor:
    futures = {executor.submit(self._test_port, p): p
              for p in range(52500, 53500)}
```
**Impact**: When the fixed port is not responding, the script performs a 1000-port scan with 50 concurrent threads against the target device. While this is for legitimate device discovery, it generates substantial network noise and could trigger intrusion detection systems. The scan range (52500-53500) also appears to be a legacy artifact since the project now uses a fixed port (1455).
**Remediation**: Remove the port scanning fallback since the project has standardized on port 1455. If scanning must remain as a fallback, reduce the range and concurrency, and add a `--scan` flag to make it opt-in.

---

## Low Severity Findings

### LOW-1: Missing Input Validation Bounds on Numeric Parameters
**Severity**: Low
**Location**: `/Users/aodawa/conductor/workspaces/accra/curitiba/ButtonHeist/Sources/InsideMan/InsideMan.swift` (various touch handlers) and `/Users/aodawa/conductor/workspaces/accra/curitiba/ButtonHeist/Sources/TheGoods/Messages.swift`
**Evidence**: Touch coordinates, durations, scales, and other numeric parameters from client messages are used without bounds checking:
```swift
// No validation that coordinates are within screen bounds
case .touchTap(let target):
    await handleTouchTap(target, respond: respond)
// Duration values are used directly
let duration = target.duration ?? 0.5
```
**Impact**: Extremely large values for duration could cause long-running gesture operations that block the main thread. Negative or extremely large coordinates could cause unexpected behavior in the hit-testing system. A `samplesPerSegment` value of `Int.max` on a bezier path would cause excessive memory allocation.
**Remediation**: Clamp numeric parameters to reasonable bounds: coordinates to screen dimensions, durations to a maximum (e.g., 60 seconds), `samplesPerSegment` to a maximum (e.g., 1000), scale factors to a reasonable range.

### LOW-2: Verbose Debug Logging May Expose Sensitive Data
**Severity**: Low
**Location**: `/Users/aodawa/conductor/workspaces/accra/curitiba/ButtonHeist/Sources/InsideMan/InsideMan.swift` (line 204)
**Evidence**:
```swift
serverLog("Raw message: \(str.prefix(200))")
```
And throughout the file, various `serverLog()` and `NSLog()` calls log message contents, client IDs, and operational details.
**Impact**: On-device logs (accessible via Console.app or `xcrun simctl spawn`) may contain fragments of protocol messages, which could include UI element labels, values, or other app-specific data. While this is gated behind `#if DEBUG`, debug logs can persist and be captured by diagnostic tools.
**Remediation**: Avoid logging message content in raw form. Log only message types and sizes. Consider making verbose logging opt-in via an environment variable.

### LOW-3: Shell Variable Interpolation in USB Connect Script
**Severity**: Low
**Location**: `/Users/aodawa/conductor/workspaces/accra/curitiba/scripts/usb-connect.sh` (lines 14, 39-45)
**Evidence**:
```bash
DEVICE_NAME="${1:-Test Phone 15 Pro}"
# ...
DEVICE_STATUS=$(xcrun devicectl list devices 2>&1 | grep -i "$DEVICE_NAME" || true)
# ...
sock.connect(("$DEVICE_IPV6", $PORT))
```
The `DEVICE_NAME` parameter from user input is passed to `grep` and interpolated into an inline Python script.
**Impact**: A crafted device name argument could potentially inject additional shell commands, though the risk is low because `set -e` is enabled and the variable is double-quoted in most uses. The Python heredoc interpolation is more concerning but is constrained to the socket address context.
**Remediation**: Validate or sanitize the device name input. In the Python heredoc, use proper variable passing rather than shell interpolation (e.g., pass via environment variables that Python reads with `os.environ`).

---

## Informational Findings

### INFO-1: Extensive Private API Usage
**Severity**: Informational
**Locations**:
- `/Users/aodawa/conductor/workspaces/accra/curitiba/ButtonHeist/Sources/InsideMan/SyntheticTouchFactory.swift` - `setPhase:`, `setWindow:`, `_setLocationInWindow:resetPrevious:`, `_setIsFirstTouchForView:`, `_setHidEvent:`
- `/Users/aodawa/conductor/workspaces/accra/curitiba/ButtonHeist/Sources/InsideMan/SyntheticEventFactory.swift` - `_touchesEvent`, `_clearTouches`, `_addTouch:forDelayedDelivery:`, `_setHIDEvent:`
- `/Users/aodawa/conductor/workspaces/accra/curitiba/ButtonHeist/Sources/InsideMan/IOHIDEventBuilder.swift` - `IOHIDEventCreateDigitizerEvent`, `IOHIDEventCreateDigitizerFingerEventWithQuality` via `dlsym`
- `/Users/aodawa/conductor/workspaces/accra/curitiba/ButtonHeist/Sources/InsideMan/SafeCracker.swift` - `UIKeyboardImpl.activeInstance`, `addInputString:`, `deleteFromInput`
- `/Users/aodawa/conductor/workspaces/accra/curitiba/test-aoo/test-aoo/PrivateAccessibilityExplorer.swift` - `AXRuntime.framework`, `libAccessibility.dylib`, multiple private selectors
**Assessment**: This is expected for a testing/automation tool and mirrors approaches used by established frameworks like KIF. All private API usage is correctly gated behind `#if DEBUG`. However, `PrivateAccessibilityExplorer.swift` in the `test-aoo` target is NOT gated behind `#if DEBUG` and loads private frameworks unconditionally.

### INFO-2: Reliance on #if DEBUG as Sole Safety Gate
**Severity**: Informational
**Location**: All InsideMan, SafeCracker, SyntheticTouchFactory, SyntheticEventFactory, IOHIDEventBuilder, and TapVisualizerView source files.
**Evidence**:
```swift
#if canImport(UIKit)
#if DEBUG
// ... entire implementation ...
#endif // DEBUG
#endif // canImport(UIKit)
```
**Assessment**: The `#if DEBUG` guard is effective at the compiler level -- the code is literally not compiled into release builds. However, this is a single point of failure. If a developer accidentally builds with a Debug configuration for distribution, the entire control surface would be included. The `InsideManAutoStart.m` ObjC loader is also gated with `#ifdef DEBUG`.
**Recommendation**: Consider adding a runtime check as defense-in-depth (e.g., checking for the presence of a specific environment variable or file that only exists in development environments). Add CI checks that verify InsideMan symbols are not present in release artifacts.

### INFO-3: Third-Party Dependency Supply Chain
**Severity**: Informational
**Dependencies**:
- `AccessibilitySnapshot` (local git submodule from cashapp/AccessibilitySnapshot)
- `swift-sdk` (MCP SDK from modelcontextprotocol/swift-sdk, version >= 0.10.0)
- `swift-argument-parser` (from apple/swift-argument-parser, version >= 1.3.0)
**Assessment**: Dependencies are minimal and from reputable sources. The `AccessibilitySnapshot` submodule is pinned via git. The MCP SDK and argument parser use semver ranges. No `Package.resolved` files are committed (they are in `.gitignore`), which means builds are not deterministically reproducible.
**Recommendation**: Consider committing `Package.resolved` files for reproducible builds. Periodically audit dependencies for known vulnerabilities.

---

## Security Domain Assessment

| Domain | Status | Notes |
|--------|--------|-------|
| **Authentication Security** | FAIL | No authentication mechanism. Any network-reachable client can connect and control the app. |
| **Authorization Controls** | FAIL | No authorization model. All connected clients have full access to all capabilities. |
| **Input Validation** | Issues Identified | JSON decoding provides type safety, but no bounds validation on numeric parameters. |
| **Data Protection** | FAIL | No encryption in transit. Screenshots, UI hierarchy, and text input are sent in plaintext. |
| **Network Security** | Issues Identified | Server binds to all interfaces, no TLS, no rate limiting, no connection limits. |
| **Dependency Security** | Pass | Minimal, reputable dependencies. Proper use of version pinning. |

## Compliance Status
**Overall Compliance**: N/A - This is a development/testing tool, not a production application. Standard compliance frameworks (OWASP, SOC 2, etc.) are not directly applicable. However, the security gaps identified above should be addressed to prevent the tool itself from becoming an attack vector in development environments.

## Immediate Action Items

1. **Add authentication to the TCP server** (CRIT-1). Implement a shared-secret challenge on connection. This is the single most impactful security improvement. Even a simple random token printed to the Xcode console would dramatically reduce the attack surface.

2. **Implement buffer size limits** (HIGH-2). Add a maximum buffer size check in `SimpleSocketServer.receiveNextChunk` and `DeviceConnection.receiveNext` to prevent denial-of-service via memory exhaustion.

3. **Add TLS support** (HIGH-1). Switch from `NWParameters.tcp` to `NWParameters(tls:)` in `SimpleSocketServer`. The Network framework makes this a relatively small change.

4. **Move private entitlements out of the repository** (HIGH-3). The `PrivateAccessibilityEntitlements.plist` and `sign-with-private-entitlements.sh` files represent a privilege escalation toolkit that should not be version-controlled in the main repository.

5. **Add connection limits and rate limiting** (MED-1). Implement a maximum concurrent connection count and per-client message rate limiting.

6. **Gate PrivateAccessibilityExplorer behind #if DEBUG** (INFO-1). The `test-aoo/test-aoo/PrivateAccessibilityExplorer.swift` file loads private frameworks unconditionally.

## Release Recommendation

**CONDITIONAL APPROVAL** - The `#if DEBUG` compile-time guard prevents this code from reaching production App Store builds, which is the primary safety mechanism. However, the tool is actively used in development environments where the identified vulnerabilities create real risk. Specifically, the unauthenticated network exposure (CRIT-1) means any device on the same network segment as a developer can silently observe and control their iOS app during development. Address the Critical and High findings before use on shared or untrusted networks.

## Detailed Findings Report
Location: `/Users/aodawa/conductor/workspaces/accra/curitiba/.rp1/work/features/full-repo-audit/security_report.md`
