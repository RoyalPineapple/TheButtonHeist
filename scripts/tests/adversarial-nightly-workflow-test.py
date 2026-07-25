#!/usr/bin/env python3

import sys
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
WORKFLOW = (ROOT / ".github/workflows/adversarial-nightly.yml").read_text()
LAB_SCRIPT = (SCRIPTS / "e2e-adversarial-lab.py").read_text()

if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import e2e_runtime as RUNTIME  # noqa: E402


class AdversarialNightlyWorkflowTests(unittest.TestCase):
    def test_daily_schedule_and_repeat_policy(self) -> None:
        self.assertEqual(WORKFLOW.count('- cron: "17 3 * * *"'), 1)
        self.assertIn("default: \"5\"", WORKFLOW)
        self.assertIn("default: \"1\"", WORKFLOW)
        self.assertIn("github.event.inputs.passing_repeat_count || '5'", WORKFLOW)
        self.assertIn("github.event.inputs.failure_repeat_count || '1'", WORKFLOW)

    def test_complete_gates_and_failure_evidence(self) -> None:
        self.assertIn("scripts/e2e-adversarial-lab.py", WORKFLOW)
        self.assertIn("scripts/e2e-lifecycle-gate.py", WORKFLOW)
        self.assertIn("--repeat-count", WORKFLOW)
        self.assertIn("--failure-repeat-count", WORKFLOW)
        self.assertNotIn("--scenario", WORKFLOW)
        self.assertNotIn("--filter", WORKFLOW)
        self.assertIn("BUTTONHEIST_RESULTS_MODE: failures", WORKFLOW)
        self.assertEqual(WORKFLOW.count("if: failure()"), 2)
        self.assertNotIn("git submodule update", WORKFLOW)

    def test_recovery_uses_hard_restart(self) -> None:
        self.assertIn(
            "if observation.requires_app_recovery:\n            app.restart()",
            LAB_SCRIPT,
        )

    def test_restart_terminates_before_launch(self) -> None:
        app = RUNTIME.DemoApp("simulator", port=24681, token="nightly")
        events: list[str] = []
        with mock.patch.object(
            app,
            "terminate",
            side_effect=lambda **_: events.append("terminate"),
        ), mock.patch.object(
            app,
            "launch",
            side_effect=lambda **_: events.append("launch") or 4321,
        ):
            self.assertEqual(app.restart(close_timeout=3, attempts=2, wait_timeout=5), 4321)
        self.assertEqual(events, ["terminate", "launch"])


if __name__ == "__main__":
    unittest.main()
