#!/bin/bash
# USB Device Connection Helper for Accra
# Connects to AccraHost on an iOS device over USB via CoreDevice IPv6 tunnel

set -e

DEVICE_NAME="${1:-Test Phone 15 Pro}"
BUNDLE_ID="${2:-com.accra.testapp}"
FIXED_PORT="${3:-9274}"  # Default fixed port configured in AccraHost

echo "=== Accra USB Connection Helper ==="
echo ""

# Check device status
echo "Checking device status..."
DEVICE_STATUS=$(xcrun devicectl list devices 2>&1 | grep -i "$DEVICE_NAME" || true)
if [ -z "$DEVICE_STATUS" ]; then
    echo "ERROR: Device '$DEVICE_NAME' not found"
    echo "Available devices:"
    xcrun devicectl list devices 2>&1 | tail -n +3
    exit 1
fi

if ! echo "$DEVICE_STATUS" | grep -q "connected"; then
    echo "ERROR: Device is not connected (USB cable or trust issue)"
    echo "Status: $DEVICE_STATUS"
    exit 1
fi
echo "Device connected."
echo ""

# Find IPv6 tunnel prefix
echo "Finding CoreDevice IPv6 tunnel..."
TUNNEL_INFO=$(lsof -i -P -n 2>/dev/null | grep CoreDev | head -1 || true)
if [ -z "$TUNNEL_INFO" ]; then
    echo "ERROR: No CoreDevice tunnel found"
    echo "Try reconnecting the USB cable"
    exit 1
fi

# Extract IPv6 prefix
IPV6_PREFIX=$(echo "$TUNNEL_INFO" | grep -oE '\[fd[0-9a-f:]+::[12]\]' | head -1 | tr -d '[]' | sed 's/::[12]$//')
if [ -z "$IPV6_PREFIX" ]; then
    echo "ERROR: Could not extract IPv6 prefix from tunnel"
    exit 1
fi

DEVICE_IPV6="${IPV6_PREFIX}::1"
echo "Device IPv6: $DEVICE_IPV6"
echo ""

# Launch the app and keep it in foreground
echo "Launching $BUNDLE_ID..."
xcrun devicectl device process launch --device "$DEVICE_NAME" --terminate-existing --activate "$BUNDLE_ID" 2>&1 || {
    echo "ERROR: Failed to launch app"
    exit 1
}
sleep 3

# Try fixed port first, then scan if needed
echo "Connecting to AccraHost..."
FOUND_PORT=$(python3 << PYEOF
import socket
import concurrent.futures

def test_port(port):
    try:
        s = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
        s.settimeout(0.5)
        s.connect(("$DEVICE_IPV6", port))
        data = s.recv(256)
        s.close()
        if b'info' in data and b'appName' in data:
            return port
    except:
        pass
    return None

# Try fixed port first (instant connection)
fixed_port = $FIXED_PORT
result = test_port(fixed_port)
if result:
    print(result)
else:
    # Fall back to scanning
    import sys
    print("Scanning...", file=sys.stderr)
    with concurrent.futures.ThreadPoolExecutor(max_workers=50) as executor:
        futures = {executor.submit(test_port, p): p for p in range(52500, 53500)}
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            if result:
                print(result)
                for f in futures:
                    f.cancel()
                break
PYEOF
)

if [ -z "$FOUND_PORT" ]; then
    echo "ERROR: Could not find AccraHost port"
    echo "Try running: xcrun devicectl device process launch --device \"$DEVICE_NAME\" --console $BUNDLE_ID"
    exit 1
fi

echo "AccraHost port: $FOUND_PORT"
echo ""

# Test full connection
echo "Verifying connection..."
python3 << PYEOF
import socket
import json

sock = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
sock.settimeout(5)
sock.connect(("$DEVICE_IPV6", $FOUND_PORT))

# Read info
data = b""
while b"\n" not in data:
    data += sock.recv(4096)
info = json.loads(data.split(b"\n")[0])

# Request hierarchy
sock.send(b'{"requestHierarchy":{}}\n')
data = b""
while b"\n" not in data:
    data += sock.recv(4096)
hier = json.loads(data.split(b"\n")[0])

app = info["info"]["_0"]
elements = hier["hierarchy"]["_0"]["elements"]

print("")
print("=== Connection Successful ===")
print(f"App: {app['appName']}")
print(f"Bundle: {app['bundleIdentifier']}")
print(f"Device: {app['deviceName']}")
print(f"iOS: {app['systemVersion']}")
print(f"Screen: {int(app['screenWidth'])}x{int(app['screenHeight'])}")
print(f"Elements: {len(elements)}")
print("")
print("Connect manually:")
print(f"  nc -6 $DEVICE_IPV6 $FOUND_PORT")
print("")
print("Python:")
print(f"  sock = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)")
print(f"  sock.connect(('$DEVICE_IPV6', $FOUND_PORT))")

sock.close()
PYEOF
