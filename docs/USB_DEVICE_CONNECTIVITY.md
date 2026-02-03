# USB Device Connectivity for Accra

This document describes how to connect to iOS devices over USB using the CoreDevice IPv6 tunnel, bypassing WiFi/mDNS discovery issues.

## Overview

When WiFi connectivity is unreliable (VPN interference, network segmentation, mDNS issues), you can connect to AccraHost on a physical iOS device over USB. Apple's CoreDevice framework creates an IPv6 tunnel over USB that we can use for TCP connections.

## How It Works

### The CoreDevice IPv6 Tunnel

When an iOS device is connected via USB and recognized by Xcode/CoreDevice:

1. **CoreDevice creates a tunnel** on a `utun` interface (typically `utun5`)
2. **IPv6 addresses are assigned**:
   - Mac: `fd9a:6190:eed7::2` (or similar ULA prefix)
   - Device: `fd9a:6190:eed7::1`
3. **TCP connections can be made** directly to the device's IPv6 address

### Requirements

1. **Device must be "connected"** in devicectl (USB cable attached, trusted)
2. **AccraHost must use IPv6 dual-stack** (enabled by default since commit `7c3f07a`)
3. **App must be running** on the device with AccraHost started

## Discovering the Tunnel

### Check Device Status

```bash
xcrun devicectl list devices
```

Look for `connected` status:
```
Test Phone 15 Pro     Test-Phone-15-Pro.coredevice.local    ...   connected   iPhone 15 Pro
```

### Find the IPv6 Tunnel Addresses

```bash
lsof -i -P -n | grep CoreDev
```

Output shows the tunnel prefix (e.g., `fd9a:6190:eed7::`):
```
CoreDevic  6391 aodawa   9u  IPv6 ...  TCP [fd9a:6190:eed7::2]:49241->[fd9a:6190:eed7::1]:52826 (ESTABLISHED)
```

- **Mac address**: `fd9a:6190:eed7::2`
- **Device address**: `fd9a:6190:eed7::1`

### Verify Routing

```bash
netstat -rn -f inet6 | grep fd9a
```

Should show route via `utun5` (or similar):
```
fd9a:6190:eed7::/64     fe80::...%utun5     Uc      utun5
```

## Connecting to AccraHost

### Step 1: Launch the App

```bash
xcrun devicectl device process launch --device "Test Phone 15 Pro" com.accra.testapp
```

### Step 2: Find the Server Port

The port changes each launch. Scan for it:

```bash
for port in $(seq 52900 52999); do
  timeout 0.5 nc -6 -z "fd9a:6190:eed7::1" $port 2>/dev/null && echo "Port $port open"
done
```

Or launch with `--console` to see the port in logs:
```bash
timeout 5 xcrun devicectl device process launch --device "Test Phone 15 Pro" --console --terminate-existing com.accra.testapp
```

Look for: `[SimpleSocketServer] Listening on port 52XXX`

### Step 3: Connect and Communicate

**Using netcat:**
```bash
echo '{"requestHierarchy":{}}' | nc -6 "fd9a:6190:eed7::1" 52XXX
```

**Using Python:**
```python
import socket
import json

sock = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
sock.connect(("fd9a:6190:eed7::1", 52XXX))
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
- Wrong port (rescan after relaunching app)
- Device went to sleep/background

### "No route to host"
- Device not connected or not trusted
- CoreDevice tunnel not established
- Check `xcrun devicectl list devices` for "connected" status

### "Network is unreachable"
- Wrong IPv6 prefix (check `lsof -i -P -n | grep CoreDev`)
- Tunnel interface not up (reconnect USB cable)

### Port Scanning Finds Nothing
- App may have crashed - check with `--console` flag
- AccraHost may have failed to start - check device logs
- Rebuild and reinstall app

## Future Improvements

1. **Fixed port option**: Allow configuring a known port to avoid scanning
2. **CLI integration**: Add `--usb` flag to accra CLI for direct IPv6 connection
3. **Auto-discovery**: Query devicectl for tunnel prefix automatically
4. **Connection pooling**: Reuse connections across multiple operations
