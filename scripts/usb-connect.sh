#!/bin/bash
# USB Device Connection Helper for Accra
# Connects to AccraHost on an iOS device over USB via CoreDevice IPv6 tunnel

set -e

DEVICE_NAME="${1:-Test Phone 15 Pro}"
BUNDLE_ID="${2:-com.accra.testapp}"
PORT="${3:-9274}"  # Fixed port configured in AccraHost

echo "=== Accra USB Connection ==="

# Check device status
DEVICE_STATUS=$(xcrun devicectl list devices 2>&1 | grep -i "$DEVICE_NAME" || true)
if [ -z "$DEVICE_STATUS" ]; then
    echo "ERROR: Device '$DEVICE_NAME' not found"
    xcrun devicectl list devices 2>&1 | tail -n +3
    exit 1
fi

if ! echo "$DEVICE_STATUS" | grep -q "connected"; then
    echo "ERROR: Device not connected via USB"
    exit 1
fi

# Find IPv6 tunnel
IPV6_PREFIX=$(lsof -i -P -n 2>/dev/null | grep CoreDev | grep -oE '\[fd[0-9a-f:]+::[12]\]' | head -1 | tr -d '[]' | sed 's/::[12]$//')
if [ -z "$IPV6_PREFIX" ]; then
    echo "ERROR: No CoreDevice tunnel found"
    exit 1
fi
DEVICE_IPV6="${IPV6_PREFIX}::1"

# Launch app
xcrun devicectl device process launch --device "$DEVICE_NAME" --terminate-existing --activate "$BUNDLE_ID" >/dev/null 2>&1
sleep 2

# Connect to fixed port
python3 << PYEOF
import socket
import json

sock = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
sock.settimeout(5)
sock.connect(("$DEVICE_IPV6", $PORT))

# Read info
data = b""
while b"\n" not in data:
    data += sock.recv(4096)
info = json.loads(data.split(b"\n")[0])["info"]["_0"]

# Get hierarchy
sock.send(b'{"requestHierarchy":{}}\n')
data = b""
while b"\n" not in data:
    data += sock.recv(4096)
hier = json.loads(data.split(b"\n")[0])["hierarchy"]["_0"]

print(f"""
Connected to {info['appName']} on $DEVICE_IPV6:$PORT
Device: {info['deviceName']} (iOS {info['systemVersion']})
Elements: {len(hier['elements'])}

Quick connect:
  nc -6 $DEVICE_IPV6 $PORT

Python:
  sock.connect(('$DEVICE_IPV6', $PORT))
""")
sock.close()
PYEOF
