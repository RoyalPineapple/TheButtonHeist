"""Shared simulator runtime primitives for Python E2E gates."""

from __future__ import annotations

import os
import socket
import subprocess
import time
from pathlib import Path


BUNDLE_ID = "com.buttonheist.testapp"


def run(
    cmd: list[str],
    *,
    env: dict[str, str] | None = None,
    timeout: float = 60,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    try:
        result = subprocess.run(cmd, env=env, timeout=timeout, text=True, capture_output=True)
    except subprocess.TimeoutExpired as error:
        if check:
            raise
        stdout = error.stdout.decode(errors="replace") if isinstance(error.stdout, bytes) else (error.stdout or "")
        stderr = error.stderr.decode(errors="replace") if isinstance(error.stderr, bytes) else (error.stderr or "")
        timeout_message = f"timed out after {timeout:g} seconds"
        result = subprocess.CompletedProcess(cmd, 124, stdout, f"{stderr}\n{timeout_message}" if stderr else timeout_message)
    if check and result.returncode != 0:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(cmd)}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def wait_port(port: int, *, open_expected: bool = True, timeout: float = 20) -> None:
    deadline = time.time() + timeout
    last_error: OSError | None = None
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                if open_expected:
                    return
        except OSError as error:
            last_error = error
            if not open_expected:
                return
        time.sleep(0.1)
    if open_expected:
        raise TimeoutError(f"port {port} did not open: {last_error}")
    raise TimeoutError(f"port {port} did not close")


def boot_simulator(sim: str) -> None:
    run(["xcrun", "simctl", "boot", sim], check=False, timeout=30)
    run(["xcrun", "simctl", "bootstatus", sim, "-b"], timeout=120)


def install_app(sim: str, app: Path) -> None:
    terminate_app(sim)
    run(["xcrun", "simctl", "uninstall", sim, BUNDLE_ID], check=False, timeout=20)
    run(["xcrun", "simctl", "install", sim, str(app)], timeout=120)


def launch_environment(
    port: int,
    token: str,
    instance_id: str,
    *,
    session_timeout: float | None = None,
) -> dict[str, str]:
    env = {
        **os.environ,
        "SIMCTL_CHILD_INSIDEJOB_PORT": str(port),
        "SIMCTL_CHILD_INSIDEJOB_TOKEN": token,
        "SIMCTL_CHILD_INSIDEJOB_ID": instance_id,
    }
    if session_timeout is not None:
        env["SIMCTL_CHILD_INSIDEJOB_SESSION_TIMEOUT"] = str(session_timeout)
    return env


def launch_app(sim: str, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return run(["xcrun", "simctl", "launch", sim, BUNDLE_ID], env=env, timeout=45, check=False)


def terminate_app(sim: str) -> subprocess.CompletedProcess[str]:
    return run(["xcrun", "simctl", "terminate", sim, BUNDLE_ID], check=False, timeout=20)
