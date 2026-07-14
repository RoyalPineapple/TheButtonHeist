#!/usr/bin/env python3

import importlib.util
import unittest
from pathlib import Path


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


if __name__ == "__main__":
    unittest.main()
