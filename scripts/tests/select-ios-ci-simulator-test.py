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

    def test_failed_boot_deletes_the_selected_simulator(self) -> None:
        selected = {
            "source": "existing",
            "udid": "selected-udid",
            "name": "accra-created",
            "device_type": "iPhone 16 Pro",
            "runtime_version": "26.3",
        }
        boot = mock.Mock(returncode=0, stdout="", stderr="")
        failure = subprocess.CalledProcessError(1, ["bootstatus"])
        cleaned = mock.Mock(returncode=0, stdout="", stderr="")
        with mock.patch.object(
            SELECTOR,
            "parse_args",
            return_value=mock.Mock(
                sim_name="accra-created",
                preferred_device="iPhone 16 Pro",
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
            side_effect=[boot, failure, cleaned, cleaned],
        ) as run:
            with self.assertRaises(subprocess.CalledProcessError):
                SELECTOR.main()

        self.assertEqual(
            run.call_args_list[-2:],
            [
                mock.call(
                    ["xcrun", "simctl", "shutdown", "selected-udid"],
                    check=False,
                ),
                mock.call(
                    ["xcrun", "simctl", "delete", "selected-udid"],
                    check=False,
                ),
            ],
        )


if __name__ == "__main__":
    unittest.main()
