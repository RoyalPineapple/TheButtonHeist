# USB Connectivity Scripts

Tools for connecting to iOS devices over USB when WiFi is unreliable — VPN interference, network segmentation, or flaky mDNS.

## When to Use USB vs WiFi

| Method | When to Use |
|--------|-------------|
| **WiFi** (default) | Simulator, or physical device on the same network. Zero config. |
| **USB** | Physical device behind VPN, on a different network, or when Bonjour discovery fails. |

Both methods use the same TCP protocol on port 1455. USB connections go through a CoreDevice IPv6 tunnel that macOS creates automatically for USB-connected devices.

## usb-connect.sh

Quick connection script that discovers the device, finds the IPv6 tunnel, launches your app, and connects.

### Usage

```bash
./scripts/usb-connect.sh [device-name] [bundle-id] [port]
```

| Argument | Default | Description |
|----------|---------|-------------|
| `device-name` | `"Test Phone 15 Pro"` | Name of the USB-connected device |
| `bundle-id` | `com.buttonheist.testapp` | App bundle identifier to launch |
| `port` | `1455` | InsideMan listening port |

### What It Does

1. Checks that the device is connected via `xcrun devicectl list devices`
2. Finds the CoreDevice IPv6 tunnel address from `lsof`
3. Launches the app on the device
4. Connects over IPv6 and prints the UI hierarchy
5. Handles v3.0 token authentication (reads `BUTTONHEIST_TOKEN` env var)

### Prerequisites

- Device connected via USB and trusted
- Xcode 15+ (`xcrun devicectl` required)
- Python 3

## buttonheist_usb.py

Python module for programmatic USB connections.

### Quick Start

```python
from scripts.buttonheist_usb import ButtonHeistUSBConnection

with ButtonHeistUSBConnection() as conn:
    print(f"Connected to: {conn.info['appName']}")
    hierarchy = conn.get_hierarchy()

    # Interact with elements
    conn.activate(identifier="loginButton")
    conn.tap(x=196.5, y=659)
```

### Constructor Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `device_name` | Auto-detect | USB device name filter |
| `bundle_id` | `com.buttonheist.testapp` | App to launch |
| `port` | `1455` | InsideMan port |
| `auto_launch` | `True` | Launch the app before connecting |
| `timeout` | `5` | Connection timeout in seconds |

### Available Methods

| Method | Description |
|--------|-------------|
| `connect()` | Discover tunnel, launch app, establish TCP connection |
| `close()` | Close the socket |
| `get_hierarchy()` | Request the current UI element hierarchy |
| `activate(identifier, index)` | Activate an element (VoiceOver double-tap) |
| `tap(x, y, identifier, index)` | Tap at coordinates or on an element |
| `ping()` | Keepalive ping |
| `find_element(identifier, label, trait)` | Search hierarchy for a matching element |
| `quick_connect()` | Module-level helper — connect and return a `ButtonHeistUSBConnection` |

### Authentication

Set the `BUTTONHEIST_TOKEN` environment variable to match the token configured on the iOS app (via `INSIDEMAN_TOKEN` env var or `InsideManToken` Info.plist key).

## Further Reading

- [USB Device Connectivity Guide](../docs/USB_DEVICE_CONNECTIVITY.md) — Deep dive on CoreDevice tunnels and troubleshooting
- [Project Overview](../README.md)
