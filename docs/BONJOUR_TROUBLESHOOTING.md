# Bonjour Troubleshooting

Button Heist uses Bonjour (mDNS) to advertise and discover iOS app instances on the local network. When Bonjour is unavailable, direct connection via a fixed port is the recommended workaround.

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

## Recovering Connection Info from Logs

If the app launched without explicit env vars, the port and token are logged at startup. Read them from the simulator:

```bash
xcrun simctl spawn $SIM_UDID log show \
  --predicate 'subsystem == "com.buttonheist.theinsidejob" AND category == "server"' \
  --last 5m --style compact 2>&1 | grep -E "listening on port|Auth token|Instance ID"
```

Output:
```
Server listening on port 23456
Auth token: E4F7A2B1-...
Instance ID: a1b2c3d4
```

Then connect directly: `BUTTONHEIST_DEVICE="127.0.0.1:23456" BUTTONHEIST_TOKEN="E4F7A2B1-..." buttonheist session`

## Workaround: Fixed Port Direct Connection

When Bonjour is broken, bypass discovery entirely by pinning the server to a known port.

### 1. Set the port at launch time

Pass a unique port and a human-readable token (your task slug) when launching the app:

```bash
TASK_SLUG="accra-scroll-detection"
INSIDEJOB_PORT=$((RANDOM % 10000 + 20000))
SIMCTL_CHILD_INSIDEJOB_PORT="$INSIDEJOB_PORT" \
SIMCTL_CHILD_INSIDEJOB_TOKEN="$TASK_SLUG" \
SIMCTL_CHILD_INSIDEJOB_ID="$TASK_SLUG" \
xcrun simctl launch "$SIM_UDID" com.buttonheist.testapp
```

### 2. Point clients at the port

**CLI:**

```bash
export BUTTONHEIST_DEVICE="127.0.0.1:$INSIDEJOB_PORT"
export BUTTONHEIST_TOKEN="$TASK_SLUG"
buttonheist session
```

**MCP server** (set env vars before invoking):

```bash
BUTTONHEIST_DEVICE="127.0.0.1:$INSIDEJOB_PORT" \
BUTTONHEIST_TOKEN="$TASK_SLUG" \
./scripts/buttonheist-mcp.sh
```

**Framework (TheFence):**

```bash
export BUTTONHEIST_DEVICE="127.0.0.1:$INSIDEJOB_PORT"
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
xcrun simctl spawn $SIM_UDID log show \
  --predicate 'subsystem == "com.buttonheist.thehandoff" AND category == "transport"' \
  --last 10m --style compact
```

Look for:
- `Bonjour service published: '...' on port ...` — success
- `Bonjour publish failed for '...': error N domain N` — failure with error code

### Simulator Local Network permission

iOS requires Local Network permission for Bonjour (since iOS 14; all supported deployment targets include this). In the simulator, this is usually auto-granted but can be checked in the TCC database:

```bash
SIM_UDID=<your-simulator-udid>
TCCDB="$HOME/Library/Developer/CoreSimulator/Devices/$SIM_UDID/data/Library/TCC/TCC.db"
sqlite3 "$TCCDB" "SELECT service, client, auth_value FROM access WHERE service='kTCCServiceLocalNetwork';"
```
