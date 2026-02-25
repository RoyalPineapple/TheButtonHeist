# USB Device Connectivity

Connecting to iOS devices over USB via CoreDevice IPv6 tunnels, bypassing WiFi/mDNS discovery.

## Overview

When WiFi is unreliable (VPN interference, network segmentation, mDNS issues), ButtonHeist automatically discovers USB-connected devices alongside WiFi devices. No extra flags or scripts needed — `buttonheist list` shows both.

USB discovery uses the same protocol as WiFi. The only difference is how the endpoint is found: Bonjour for WiFi, CoreDevice IPv6 tunnel for USB.

## How It Works

### The CoreDevice IPv6 Tunnel

When an iOS device is connected via USB and recognized by Xcode/CoreDevice:

1. **CoreDevice creates a tunnel** on a `utun` interface (typically `utun5`)
2. **IPv6 addresses are assigned**:
   - Mac: `fd9a:6190:eed7::2` (or similar ULA prefix)
   - Device: `fd9a:6190:eed7::1`
3. **TCP connections can be made** directly to the device's IPv6 address

### Automatic Discovery

> **Note:** `USBDeviceDiscovery` (in the Wheelman framework) is defined but not currently wired into `TheClient`. USB devices are discovered via Bonjour over the CoreDevice IPv6 tunnel — no separate USB discovery step is needed.

The `USBDeviceDiscovery` class implements this flow:

1. Polls `xcrun devicectl list devices` to find connected devices
2. Parses `lsof -i -P -n` output to locate the CoreDevice IPv6 tunnel address
3. Constructs an `NWEndpoint` with the IPv6 address and port
4. Produces a `DiscoveredDevice` — identical to Bonjour-discovered devices

### Port Discovery

InsideJob uses an OS-assigned port advertised via Bonjour. USB-connected devices are reachable on the same port via the CoreDevice IPv6 tunnel.

### Requirements

1. **Device must be "connected"** in devicectl (USB cable attached, trusted)
2. **InsideJob must use IPv6 dual-stack** (enabled by default)
3. **App must be running** on the device with InsideJob started
4. **Xcode command line tools** installed (`xcrun` must be available)

## Usage

### CLI

```bash
# List all devices (WiFi and USB appear together)
buttonheist list

# Connect to a USB device by name
buttonheist --device "iPhone 15 Pro" watch --once

# Take a screenshot over USB
buttonheist --device "iPhone 15 Pro" screenshot --output screen.png
```

### MCP Server

Target a USB device in `.mcp.json`:

```json
{
  "mcpServers": {
    "buttonheist": {
      "command": "./ButtonHeistMCP/.build/release/buttonheist-mcp",
      "args": ["--device", "iPhone 15 Pro"]
    }
  }
}
```

## Building and Deploying to Device

### Command Line Build

```bash
xcodebuild -workspace ButtonHeist.xcworkspace \
  -scheme AccessibilityTestApp \
  -destination 'platform=iOS,name=Your Device Name' \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  build
```

### Install to Device

```bash
xcrun devicectl device install app \
  --device "Your Device Name" \
  ~/Library/Developer/Xcode/DerivedData/ButtonHeist-*/Build/Products/Debug-iphoneos/AccessibilityTestApp.app

xcrun devicectl device process launch \
  --device "Your Device Name" \
  --terminate-existing --activate \
  com.buttonheist.testapp
```

## Discovering the Tunnel Manually

### Check Device Status

```bash
xcrun devicectl list devices
```

Look for `connected` status:
```
Test Phone 15 Pro     Test-Phone-15-Pro.coredevice.local    ...   connected   iPhone 15 Pro
```

### Find the IPv6 Tunnel Address

```bash
lsof -i -P -n | grep CoreDev | grep -oE '\[fd[0-9a-f:]+::[12]\]' | head -1
```

### Manual Connection (for debugging)

**Note**: Protocol v3.1 requires token authentication before any commands are accepted.

```bash
# Using netcat (must authenticate first)
nc -6 "fd9a:6190:eed7::1" <port>   # use port from `buttonheist list --format json`
# Server sends: {"authRequired":{}}
# Send: {"authenticate":{"_0":{"token":"your-token"}}}
# Server sends: {"info":{"_0":{...}}}
# Send: {"requestInterface":{}}
```

## Message Protocol

Messages are newline-delimited JSON. Swift enums encode with `_0` wrapper for associated values. Protocol v3.1 requires authentication before any commands are accepted.

### Authenticate
```json
{"authenticate":{"_0":{"token":"your-secret-token"}}}
```

### Request Interface
```json
{"requestInterface":{}}
```

### Activate Element (by order index)
```json
{"activate":{"_0":{"order":6}}}
```

### Activate Element (by identifier)
```json
{"activate":{"_0":{"identifier":"loginButton"}}}
```

### Tap at Coordinates
```json
{"touchTap":{"_0":{"pointX":196.5,"pointY":659}}}
```

### Ping
```json
{"ping":{}}
```

## Implementation Details

### IPv6 Dual-Stack Server

The `SimpleSocketServer` uses Network framework (`NWListener`) with IPv6 dual-stack to accept both IPv4 and IPv6 connections:

```swift
// Network framework listener
let parameters = NWParameters.tcp
let host: NWEndpoint.Host = bindToLoopback ? .ipv6(.loopback) : .ipv6(.any)
parameters.requiredLocalEndpoint = .hostPort(host: host, port: NWEndpoint.Port(rawValue: port)!)
let listener = try NWListener(using: parameters)
```

On simulators, the server binds to loopback only (`::1`) by default. On physical devices, it binds to all interfaces (`::`) to accept USB tunnel connections. Override with `INSIDEJOB_BIND_ALL=true`.

This allows:
- Simulator connections via `127.0.0.1` (loopback)
- USB device connections via the CoreDevice IPv6 tunnel
- WiFi connections via local network IPv4/IPv6

### Why WiFi Might Fail

Common issues that USB bypasses:
- **VPN routing**: VPN may route local traffic through tunnel
- **mDNS blocking**: Bonjour discovery blocked or filtered
- **Network segmentation**: Device on different subnet
- **Firewall rules**: Port blocked on WiFi interface

## Troubleshooting

### "Connection refused"
- App not running or InsideJob not started
- Wrong port (verify Info.plist has correct port)
- Device went to sleep/background

### "No route to host"
- Device not connected or not trusted
- CoreDevice tunnel not established
- Check `xcrun devicectl list devices` for "connected" status

### "Network is unreachable"
- Wrong IPv6 prefix (check `lsof -i -P -n | grep CoreDev`)
- Tunnel interface not up (reconnect USB cable)

### USB device not appearing in `buttonheist list`
- Verify device shows as "connected" in `xcrun devicectl list devices`
- Ensure app is running on the device
- USB discovery polls every 3 seconds — wait a moment

## See Also

- [Wire Protocol](WIRE-PROTOCOL.md) — Message format (identical over WiFi and USB)
- [Project Overview](../README.md) — Architecture and quick start
- [CLI Reference](../ButtonHeistCLI/) — All commands work over USB
