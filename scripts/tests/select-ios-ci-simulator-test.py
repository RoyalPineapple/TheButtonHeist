#!/usr/bin/env python3

import importlib.util
import subprocess
import unittest
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / "select-ios-ci-simulator.py"
SPEC = importlib.util.spec_from_file_location("select_ios_ci_simulator", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
SELECTOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SELECTOR)


class SimulatorSelectionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.runtimes = [
            {
                "identifier": "ios-26-3",
                "version": "26.3",
                "platform": "iOS",
                "isAvailable": True,
                "supportedDeviceTypes": [
                    {
                        "identifier": "iphone-16-pro",
                        "name": "iPhone 16 Pro",
                        "productFamily": "iPhone",
                    }
                ],
            }
        ]
        self.runtimes = [
            {
                **self.runtimes[0],
                "identifier": f"ios-{version.replace('.', '-')}",
                "version": version,
            }
            for version in ("26.4", "26.3", "27.0")
        ]
        self.devices = {
            "ios-26-3": [
                {
                    "udid": "owned",
                    "name": "buttonheist-ci-owned",
                    "isAvailable": True,
                    "deviceTypeIdentifier": "iphone-16-pro",
                },
                {
                    "udid": "other",
                    "name": "buttonheist-ci-other",
                    "isAvailable": True,
                    "deviceTypeIdentifier": "iphone-16-pro",
                },
            ]
        }

    def test_reuses_only_the_named_simulator(self) -> None:
        selected = SELECTOR.existing_simulator(
            self.runtimes,
            self.devices,
            "buttonheist-ci-owned",
        )
        self.assertIsNotNone(selected)
        self.assertEqual(selected["udid"], "owned")

    def test_does_not_borrow_another_workstream_simulator(self) -> None:
        selected = SELECTOR.existing_simulator(
            self.runtimes,
            self.devices,
            "buttonheist-ci-new",
        )
        self.assertIsNone(selected)

    def test_prefers_the_requested_device_type_for_creation(self) -> None:
        preferred, fallback = SELECTOR.create_candidates(self.runtimes, "iPhone 16 Pro")
        self.assertEqual(preferred[0]["device_type_identifier"], "iphone-16-pro")
        self.assertEqual(fallback, [])

    def test_runtime_filter_uses_newest_compatible_or_exact_requested(self) -> None:
        maximum = SELECTOR.version_key("26.5")
        self.assertEqual(
            [runtime["version"] for runtime in SELECTOR.ios_runtimes(self.runtimes, maximum)],
            ["26.4", "26.3"],
        )
        requested = SELECTOR.version_key("26.3")
        self.assertEqual(
            [runtime["version"] for runtime in SELECTOR.ios_runtimes(self.runtimes, maximum, requested)],
            ["26.3"],
        )

    def test_too_new_explicit_runtime_fails_before_simctl_selection(self) -> None:
        with mock.patch.object(SELECTOR, "load_json") as load, self.assertRaisesRegex(
            RuntimeError, "requested iOS simulator runtime 27.0 exceeds active SDK 26.5"
        ):
            SELECTOR.select_or_create_simulator("iPhone 16 Pro", "accra-created", "26.5", "27.0")

        load.assert_not_called()

    def test_no_compatible_runtime_does_not_fall_forward(self) -> None:
        with mock.patch.object(
            SELECTOR, "load_json", return_value={"runtimes": self.runtimes[-1:]}
        ), self.assertRaisesRegex(
            RuntimeError, "No available iOS simulator runtime at or below active SDK 26.5"
        ):
            SELECTOR.select_or_create_simulator("iPhone 16 Pro", "accra-created", "26.5")

    def test_failed_boot_deletes_the_selected_simulator(self) -> None:
        selected = {
            "source": "existing",
            "udid": "selected-udid",
            "name": "accra-created",
            "device_type": "iPhone 16 Pro",
            "runtime_version": "26.3",
        }
        sdk = mock.Mock(stdout="26.5")
        boot = mock.Mock(returncode=0, stdout="", stderr="")
        failure = subprocess.CalledProcessError(1, ["bootstatus"])
        cleaned = mock.Mock(returncode=0, stdout="", stderr="")
        with mock.patch.object(
            SELECTOR,
            "parse_args",
            return_value=mock.Mock(
                sim_name="accra-created",
                preferred_device="iPhone 16 Pro",
                runtime=None,
                wait=True,
                github_env=None,
                github_output=None,
            ),
        ), mock.patch.object(
            SELECTOR,
            "select_or_create_simulator",
            return_value=selected,
        ), mock.patch.object(
            SELECTOR,
            "run",
            side_effect=[sdk, boot, failure, cleaned, cleaned],
        ) as run:
            with self.assertRaises(subprocess.CalledProcessError):
                SELECTOR.main()

        self.assertEqual(
            [call.args[0][2] for call in run.call_args_list],
            ["iphonesimulator", "boot", "bootstatus", "shutdown", "delete"],
        )


if __name__ == "__main__":
    unittest.main()
