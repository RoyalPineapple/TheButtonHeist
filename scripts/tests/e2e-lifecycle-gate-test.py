#!/usr/bin/env python3

import importlib.util
import subprocess
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "e2e-lifecycle-gate.py"
SPEC = importlib.util.spec_from_file_location("e2e_lifecycle_gate", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FailureKindTests(unittest.TestCase):
    def test_scenario_failure_is_a_product_failure(self) -> None:
        self.assertEqual(
            MODULE.failure_kind(AssertionError("contract"), scenario_started=True),
            "product-lifecycle-failure",
        )

    def test_setup_timeout_is_an_infrastructure_timeout(self) -> None:
        timeout = subprocess.TimeoutExpired(["xcrun"], 10)
        self.assertEqual(
            MODULE.failure_kind(timeout, scenario_started=False),
            "infrastructure-timeout",
        )

    def test_other_setup_failure_is_infrastructure(self) -> None:
        self.assertEqual(
            MODULE.failure_kind(RuntimeError("missing app"), scenario_started=False),
            "infrastructure-setup-failure",
        )


if __name__ == "__main__":
    unittest.main()
