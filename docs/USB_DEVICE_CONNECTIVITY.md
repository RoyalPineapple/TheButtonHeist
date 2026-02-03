# USB Device Connectivity for Accra

This document describes how to connect to iOS devices over USB using the CoreDevice IPv6 tunnel, bypassing WiFi/mDNS discovery issues.

## Overview

When WiFi connectivity is unreliable (VPN interference, network segmentation, mDNS issues), you can connect to AccraHost on a physical iOS device over USB. Apple's CoreDevice framework creates an IPv6 tunnel over USB that we can use for TCP connections.

## Quick Start

```bash
# Connect to device (launches app, connects on port 1455)
./scripts/usb-connect.sh "Your Device Name"

# Or use Python
python3 scripts/accra_usb.py
```

## How It Works

### The CoreDevice IPv6 Tunnel

When an iOS device is connected via USB and recognized by Xcode/CoreDevice:

1. **CoreDevice creates a tunnel** on a `utun` interface (typically `utun5`)
2. **IPv6 addresses are assigned**:
   - Mac: `fd9a:6190:eed7::2` (or similar ULA prefix)
   - Device: `fd9a:6190:eed7::1`
3. **TCP connections can be made** directly to the device's IPv6 address

### Fixed Port Configuration

AccraHost uses a fixed port configured in `Info.plist`:

```xml
<key>AccraHostPort</key>
<integer>1455</integer>
```

This eliminates the need for port scanning and enables instant connections.

### Requirements

1. **Device must be "connected"** in devicectl (USB cable attached, trusted)
2. **AccraHost must use IPv6 dual-stack** (enabled by default)
3. **App must be running** on the device with AccraHost started

## Building and Deploying

### Command Line Build

```bash
# Build for device with automatic signing
xcodebuild -workspace Accra.xcworkspace \
  -scheme AccessibilityTestApp \
  -destination 'platform=iOS,name=Your Device Name' \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  build

# Find your team ID from provisioning profile
cat path/to/app/embedded.mobileprovision | security cms -D | grep -A1 TeamIdentifier
```

### Install to Device

```bash
# Install the built app
xcrun devicectl device install app \
  --device "Your Device Name" \
  ~/Library/Developer/Xcode/DerivedData/Accra-*/Build/Products/Debug-iphoneos/AccessibilityTestApp.app

# Launch the app
xcrun devicectl device process launch \
  --device "Your Device Name" \
  --terminate-existing --activate \
  com.accra.testapp
```

## Discovering the Tunnel

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

Output shows the tunnel prefix (e.g., `fd9a:6190:eed7::1`).

## Connecting to AccraHost

### Using the Helper Script

```bash
./scripts/usb-connect.sh "Test Phone 15 Pro"
```

Output:
```
=== Accra USB Connection ===

Connected to AccessibilityTestApp on fd9a:6190:eed7::1:1455
Device: iPhone (iOS 26.2.1)
Elements: 15

Quick connect:
  nc -6 fd9a:6190:eed7::1 1455

Python:
  sock.connect(('fd9a:6190:eed7::1', 1455))
```

### Using Python

```python
from scripts.accra_usb import AccraUSBConnection

with AccraUSBConnection() as conn:
    print(f"Connected to: {conn.info['appName']}")
    hierarchy = conn.get_hierarchy()
    print(f"Elements: {len(hierarchy['elements'])}")

    # Activate a button
    conn.activate(identifier="myButton")
```

### Manual Connection

```bash
# Using netcat
echo '{"requestHierarchy":{}}' | nc -6 "fd9a:6190:eed7::1" 1455
```

```python
import socket
import json

sock = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
sock.connect(("fd9a:6190:eed7::1", 1455))
sock.settimeout(5)

# Read initial info message
data = b""
while b"\n" not in data:
    data += sock.recv(4096)
info = json.loads(data.split(b"\n")[0])
print("Connected to:", info["info"]["_0"]["appName"])

# Request hierarchy
sock.send(b'{"requestHierarchy":{}}\n')
data = b""
while b"\n" not in data:
    data += sock.recv(4096)
hierarchy = json.loads(data.split(b"\n")[0])
print("Elements:", len(hierarchy["hierarchy"]["_0"]["elements"]))

sock.close()
```

## Message Protocol

Messages are newline-delimited JSON. Swift enums encode with `_0` wrapper for associated values.

### Request Hierarchy
```json
{"requestHierarchy":{}}
```

### Activate Element (by traversal index)
```json
{"activate":{"_0":{"traversalIndex":6}}}
```

### Activate Element (by identifier)
```json
{"activate":{"_0":{"identifier":"accra.action.testButton"}}}
```

### Tap at Coordinates
```json
{"tap":{"_0":{"pointX":196.5,"pointY":659}}}
```

### Ping
```json
{"ping":{}}
```

## Configuration

### Changing the Port

The port is configured in three places:

1. **Info.plist** (app reads this on launch):
   ```xml
   <key>AccraHostPort</key>
   <integer>1455</integer>
   ```

2. **scripts/usb-connect.sh** (default port):
   ```bash
   PORT="${3:-1455}"
   ```

3. **scripts/accra_usb.py** (Python default):
   ```python
   DEFAULT_PORT = 1455
   ```

After changing, rebuild and reinstall the app.

## Implementation Details

### IPv6 Dual-Stack Server

The `SimpleSocketServer` uses an IPv6 dual-stack socket to accept both IPv4 (simulator) and IPv6 (USB device) connections:

```swift
// Create IPv6 socket
let fd = socket(AF_INET6, SOCK_STREAM, 0)

// Enable dual-stack (accept IPv4 via mapped addresses)
var no: Int32 = 0
setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &no, socklen_t(MemoryLayout<Int32>.size))

// Bind to all interfaces
var addr = sockaddr_in6()
addr.sin6_family = sa_family_t(AF_INET6)
addr.sin6_port = port.bigEndian
addr.sin6_addr = in6addr_any
```

This allows:
- Simulator connections via `127.0.0.1` (mapped to `::ffff:127.0.0.1`)
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
- App not running or AccraHost not started
- Wrong port (verify Info.plist has correct port)
- Device went to sleep/background

### "No route to host"
- Device not connected or not trusted
- CoreDevice tunnel not established
- Check `xcrun devicectl list devices` for "connected" status

### "Network is unreachable"
- Wrong IPv6 prefix (check `lsof -i -P -n | grep CoreDev`)
- Tunnel interface not up (reconnect USB cable)

### Connection Works But Port Wrong
- App was built with old Info.plist - rebuild and reinstall
- Verify with: `plutil -p /path/to/AccessibilityTestApp.app/Info.plist | grep AccraHostPort`
