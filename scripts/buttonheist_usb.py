#!/usr/bin/env python3
"""
ButtonHeist USB Connection Module

Provides reliable connection to InsideMan on iOS devices over USB
using the CoreDevice IPv6 tunnel.

Usage:
    from buttonheist_usb import ButtonHeistUSBConnection

    with ButtonHeistUSBConnection() as conn:
        print(conn.info)
        hierarchy = conn.get_hierarchy()
        for element in hierarchy['elements']:
            print(element['label'])
"""

import socket
import json
import subprocess
import re
import time
from typing import Optional, Dict, Any, List
from contextlib import contextmanager


class ButtonHeistUSBError(Exception):
    """Base exception for ButtonHeist USB connection errors."""
    pass


class DeviceNotFoundError(ButtonHeistUSBError):
    """Raised when the specified device is not found or not connected."""
    pass


class ConnectionError(ButtonHeistUSBError):
    """Raised when connection to InsideMan fails."""
    pass


class ButtonHeistUSBConnection:
    """
    Manages a connection to InsideMan on an iOS device over USB.

    The connection uses the CoreDevice IPv6 tunnel that macOS creates
    for USB-connected iOS devices.

    Args:
        device_name: Name of the device (default: auto-detect first connected)
        bundle_id: App bundle ID (default: com.buttonheist.testapp)
        port: Fixed port (default: 1455, 0 to scan)
        auto_launch: Launch app if not running (default: True)
        timeout: Socket timeout in seconds (default: 5)

    Example:
        with ButtonHeistUSBConnection() as conn:
            hierarchy = conn.get_hierarchy()
            print(f"Found {len(hierarchy['elements'])} elements")
    """

    DEFAULT_PORT = 1455
    DEFAULT_BUNDLE_ID = "com.buttonheist.testapp"

    def __init__(
        self,
        device_name: Optional[str] = None,
        bundle_id: str = DEFAULT_BUNDLE_ID,
        port: int = DEFAULT_PORT,
        auto_launch: bool = True,
        timeout: float = 5.0
    ):
        self.device_name = device_name
        self.bundle_id = bundle_id
        self.port = port
        self.auto_launch = auto_launch
        self.timeout = timeout

        self._socket: Optional[socket.socket] = None
        self._ipv6_addr: Optional[str] = None
        self._actual_port: Optional[int] = None
        self._info: Optional[Dict[str, Any]] = None
        self._buffer: bytes = b""

    def __enter__(self) -> "ButtonHeistUSBConnection":
        self.connect()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()
        return False

    @property
    def info(self) -> Dict[str, Any]:
        """Server info received on connection."""
        if self._info is None:
            raise ConnectionError("Not connected")
        return self._info

    @property
    def connected(self) -> bool:
        """Check if connection is active."""
        return self._socket is not None

    def connect(self) -> None:
        """
        Establish connection to InsideMan.

        Discovers the CoreDevice IPv6 tunnel, optionally launches the app,
        finds the port, and establishes the TCP connection.
        """
        # Find device
        self._ipv6_addr = self._discover_ipv6_tunnel()

        # Launch app if needed
        if self.auto_launch:
            self._launch_app()
            time.sleep(3)  # Wait for app to start and InsideMan to initialize

        # Find and connect to port
        self._actual_port = self._find_port()
        self._connect_socket()

        # Read initial info message
        self._info = self._read_message()
        if "info" not in self._info:
            raise ConnectionError("Invalid server response")
        self._info = self._info["info"]["_0"]

    def close(self) -> None:
        """Close the connection."""
        if self._socket:
            try:
                self._socket.close()
            except:
                pass
            self._socket = None

    def reconnect(self) -> None:
        """Reconnect to the server (e.g., after app restart)."""
        self.close()
        self._buffer = b""
        self.connect()

    def get_hierarchy(self) -> Dict[str, Any]:
        """
        Request the current accessibility hierarchy.

        Returns:
            Dict with 'timestamp' and 'elements' list
        """
        self._send_message({"requestHierarchy": {}})
        response = self._read_message()
        if "hierarchy" not in response:
            raise ConnectionError(f"Unexpected response: {response}")
        return response["hierarchy"]["_0"]

    def activate(self, identifier: Optional[str] = None, index: Optional[int] = None) -> Dict[str, Any]:
        """
        Activate an element (equivalent to VoiceOver double-tap).

        Args:
            identifier: Element's accessibilityIdentifier
            index: Element's traversal index

        Returns:
            Action result dict with 'success' and 'method'
        """
        target = {}
        if identifier:
            target["identifier"] = identifier
        if index is not None:
            target["traversalIndex"] = index

        self._send_message({"activate": {"_0": target}})
        response = self._read_message()
        if "actionResult" not in response:
            raise ConnectionError(f"Unexpected response: {response}")
        return response["actionResult"]["_0"]

    def tap(self, x: Optional[float] = None, y: Optional[float] = None,
            identifier: Optional[str] = None, index: Optional[int] = None) -> Dict[str, Any]:
        """
        Tap at coordinates or on an element.

        Args:
            x, y: Screen coordinates
            identifier: Element's accessibilityIdentifier
            index: Element's traversal index

        Returns:
            Action result dict
        """
        target = {}
        if x is not None and y is not None:
            target["pointX"] = x
            target["pointY"] = y
        else:
            element_target = {}
            if identifier:
                element_target["identifier"] = identifier
            if index is not None:
                element_target["traversalIndex"] = index
            target["elementTarget"] = element_target

        self._send_message({"tap": {"_0": target}})
        response = self._read_message()
        if "actionResult" not in response:
            raise ConnectionError(f"Unexpected response: {response}")
        return response["actionResult"]["_0"]

    def ping(self) -> bool:
        """Send a ping and wait for pong."""
        self._send_message({"ping": {}})
        response = self._read_message()
        return "pong" in response

    def find_element(self, identifier: Optional[str] = None,
                     label: Optional[str] = None,
                     trait: Optional[str] = None) -> Optional[Dict[str, Any]]:
        """
        Find an element in the current hierarchy.

        Args:
            identifier: Match accessibilityIdentifier
            label: Match label (substring)
            trait: Match trait (e.g., 'button', 'staticText')

        Returns:
            Element dict or None if not found
        """
        hierarchy = self.get_hierarchy()
        for element in hierarchy.get("elements", []):
            if identifier and element.get("identifier") == identifier:
                return element
            if label and label in (element.get("label") or ""):
                return element
            if trait and trait in element.get("traits", []):
                return element
        return None

    def _discover_ipv6_tunnel(self) -> str:
        """Find the CoreDevice IPv6 tunnel address."""
        # Check device is connected
        result = subprocess.run(
            ["xcrun", "devicectl", "list", "devices"],
            capture_output=True, text=True, timeout=10
        )

        if self.device_name:
            if self.device_name not in result.stdout:
                raise DeviceNotFoundError(f"Device '{self.device_name}' not found")
            if "connected" not in result.stdout.split(self.device_name)[1].split("\n")[0]:
                raise DeviceNotFoundError(f"Device '{self.device_name}' not connected via USB")
        else:
            # Find first connected device
            for line in result.stdout.split("\n"):
                if "connected" in line:
                    self.device_name = line.split()[0]
                    break
            if not self.device_name:
                raise DeviceNotFoundError("No connected devices found")

        # Find IPv6 tunnel from CoreDevice connections
        result = subprocess.run(
            ["lsof", "-i", "-P", "-n"],
            capture_output=True, text=True, timeout=5
        )

        match = re.search(r'\[(fd[0-9a-f:]+)::1\]', result.stdout)
        if not match:
            raise ConnectionError("No CoreDevice IPv6 tunnel found")

        return match.group(1) + "::1"

    def _launch_app(self) -> None:
        """Launch the app on the device."""
        subprocess.run(
            ["xcrun", "devicectl", "device", "process", "launch",
             "--device", self.device_name,
             "--terminate-existing", "--activate",
             self.bundle_id],
            capture_output=True, timeout=15
        )

    def _find_port(self) -> int:
        """Find the InsideMan port."""
        # Try fixed port first with retries
        if self.port > 0:
            for attempt in range(3):
                if self._test_port(self.port):
                    return self.port
                time.sleep(0.5)

        # Scan for port
        import concurrent.futures
        with concurrent.futures.ThreadPoolExecutor(max_workers=50) as executor:
            futures = {executor.submit(self._test_port, p): p
                      for p in range(52500, 53500)}
            for future in concurrent.futures.as_completed(futures):
                if future.result():
                    port = futures[future]
                    for f in futures:
                        f.cancel()
                    return port

        raise ConnectionError("Could not find InsideMan port")

    def _test_port(self, port: int) -> bool:
        """Test if a port has InsideMan."""
        try:
            s = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
            s.settimeout(0.5)
            s.connect((self._ipv6_addr, port))
            data = s.recv(256)
            s.close()
            return b'info' in data and b'appName' in data
        except:
            return False

    def _connect_socket(self) -> None:
        """Establish the socket connection."""
        self._socket = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
        self._socket.settimeout(self.timeout)
        try:
            self._socket.connect((self._ipv6_addr, self._actual_port))
        except Exception as e:
            raise ConnectionError(f"Failed to connect: {e}")

    def _send_message(self, msg: Dict) -> None:
        """Send a JSON message."""
        if not self._socket:
            raise ConnectionError("Not connected")
        data = json.dumps(msg).encode() + b"\n"
        self._socket.sendall(data)

    def _read_message(self) -> Dict:
        """Read a JSON message."""
        if not self._socket:
            raise ConnectionError("Not connected")

        while b"\n" not in self._buffer:
            chunk = self._socket.recv(8192)
            if not chunk:
                raise ConnectionError("Connection closed")
            self._buffer += chunk

        line, self._buffer = self._buffer.split(b"\n", 1)
        return json.loads(line)


def quick_connect(device_name: Optional[str] = None) -> ButtonHeistUSBConnection:
    """
    Quick helper to connect with default settings.

    Example:
        conn = quick_connect()
        print(conn.get_hierarchy())
        conn.close()
    """
    conn = ButtonHeistUSBConnection(device_name=device_name)
    conn.connect()
    return conn


if __name__ == "__main__":
    # Demo usage
    print("Connecting to InsideMan over USB...")
    with ButtonHeistUSBConnection() as conn:
        print(f"Connected to: {conn.info['appName']}")
        print(f"Device: {conn.info['deviceName']}")
        print(f"iOS: {conn.info['systemVersion']}")

        hierarchy = conn.get_hierarchy()
        print(f"\nAccessibility Elements ({len(hierarchy['elements'])}):")
        for el in hierarchy['elements'][:10]:
            label = el.get('label') or el.get('identifier') or el.get('description', 'unknown')
            traits = el.get('traits', [])
            print(f"  - {label} {traits}")
