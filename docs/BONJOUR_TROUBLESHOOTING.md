# Bonjour Troubleshooting

ButtonHeist uses Bonjour (mDNS) to advertise and discover iOS app instances on the local network. When Bonjour is unavailable, direct connection via a fixed port is the recommended workaround.

## Quick Diagnosis

```bash
# 1. Register a test service from the host
dns-sd -R "Test" _buttonheist._tcp . 12345 &

# 2. Try to browse for it
timeout 5 dns-sd -B _buttonheist._tcp .

# 3. Clean up
kill %1
```

If registration says "Name now registered and active" but the browse returns nothing, Bonjour is broken at the mDNSResponder level on your machine.

## Known Issue: macOS Firewall Stealth Mode Breaks mDNS

### Symptoms

- `dns-sd -B _buttonheist._tcp .` finds zero services
- `dns-sd -R` registration appears to succeed but nothing is discoverable
- `buttonheist list` returns no devices even though the app is running
- mDNSResponder logs show continuous `sendto()` failures:
  ```
  mDNSPlatformSendUDP -> sendto(6) failed ... errno 32 (Broken pipe)
  Sending mDNS message failed - mStatus: -65537
  ```

### Root Cause

MDM-enforced firewall stealth mode deploys a Network Extension content filter (CFIL) that breaks mDNSResponder's multicast sockets at the kernel level. The CFIL layer cannot model multicast UDP (port 5353) as a trackable flow, which corrupts the socket file descriptor. All subsequent `sendto()` calls return `EPIPE` (errno 32) in an infinite loop.

This is **not** a ButtonHeist bug. All Bonjour services on the machine are affected.

Key distinction: manually enabling stealth mode (System Settings > Network > Firewall) generally does **not** break Bonjour. The issue is specific to MDM-deployed stealth mode, which uses a Network Extension content filter rather than plain `pf` rules.

### Verification

```bash
# Check if stealth mode is on
/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode

# Check mDNSResponder for broken pipe errors
log show --predicate 'process == "mDNSResponder"' --last 5m --style compact 2>&1 | grep "errno 32"
```

### References

- [Apple Developer Forums — CFIL: Failed to create UDP flow](https://developer.apple.com/forums/thread/728397)
- [Microsoft Intune — macOS stealth mode known issue](https://techcommunity.microsoft.com/blog/intunecustomersuccess/known-issue-macos-devices-using-stealth-mode-turn-non-compliant-after-upgrading-/4250583)
- [LuLu issue #355 — mDNSResponder broken pipe](https://github.com/objective-see/LuLu/issues/355)

## Workaround: Fixed Port Direct Connection

When Bonjour is broken, bypass discovery entirely by pinning the server to a known port.

### 1. Set the port in the app

**Via Info.plist** (recommended for test apps — baked in at build time):

```swift
// In TestApp/Project.swift (Tuist)
infoPlist: .extendingDefault(with: [
    "InsideJobPort": 1455,
    // ...
])
```

**Via environment variable** (overrides Info.plist):

```bash
SIMCTL_CHILD_INSIDEJOB_PORT=1455 xcrun simctl launch $SIM com.buttonheist.testapp
```

### 2. Point clients at the fixed port

**CLI:**

```bash
export BUTTONHEIST_DEVICE=127.0.0.1:1455
export BUTTONHEIST_TOKEN=your-token
buttonheist session
```

**MCP server** (`.mcp.json`):

```json
{
  "mcpServers": {
    "buttonheist": {
      "command": "./ButtonHeistMCP/.build/release/buttonheist-mcp",
      "env": {
        "BUTTONHEIST_DEVICE": "127.0.0.1:1455",
        "BUTTONHEIST_TOKEN": "your-token"
      }
    }
  }
}
```

**Framework (TheFence):**

```bash
export BUTTONHEIST_DEVICE=127.0.0.1:1455
```

### 3. How it works

The `INSIDEJOB_PORT` / `InsideJobPort` configuration tells `TheInsideJob` to bind to a specific TCP port instead of letting the OS pick a random one. The `BUTTONHEIST_DEVICE` environment variable on the client side triggers `DiscoveredDevice.directConnectTarget(from:)`, which parses the `host:port` string and bypasses Bonjour entirely.

The direct connect path uses the same TLS transport and authentication as Bonjour-discovered connections — only the discovery step is different.

### Port selection

- `0` (default): OS picks a random available port. Requires Bonjour for discovery.
- Any non-zero value: Server binds to that specific port. Use with `BUTTONHEIST_DEVICE` on the client.
- Priority: `INSIDEJOB_PORT` env var > `InsideJobPort` Info.plist key > default (0).

## Other Bonjour Issues

### Temporary mDNSResponder fix

Restarting mDNSResponder re-creates the multicast sockets. This is a temporary fix — the sockets will break again if the MDM filter is still active.

```bash
sudo killall -9 mDNSResponder
```

### NetService publish errors

`ServerTransport` implements `NetServiceDelegate` to log publish failures. Check the simulator logs:

```bash
xcrun simctl spawn $SIM log show \
  --predicate 'subsystem == "com.buttonheist.thehandoff" AND category == "transport"' \
  --last 10m --style compact
```

Look for:
- `Bonjour service published: '...' on port ...` — success
- `Bonjour publish failed for '...': error N domain N` — failure with error code

### Simulator Local Network permission

iOS 14+ requires Local Network permission for Bonjour. In the simulator, this is usually auto-granted but can be checked/set in the TCC database:

```bash
SIM_UDID=<your-simulator-udid>
TCCDB="$HOME/Library/Developer/CoreSimulator/Devices/$SIM_UDID/data/Library/TCC/TCC.db"
sqlite3 "$TCCDB" "SELECT service, client, auth_value FROM access WHERE service='kTCCServiceLocalNetwork';"
```
