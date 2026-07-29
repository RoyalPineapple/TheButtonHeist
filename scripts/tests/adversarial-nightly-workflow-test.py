#!/usr/bin/env python3

import unittest
from pathlib import Path


WORKFLOW = (
    Path(__file__).resolve().parents[2] / ".github/workflows/adversarial-nightly.yml"
).read_text()


class AdversarialNightlyWorkflowTests(unittest.TestCase):
    def test_daily_schedule_and_repeat_policy(self) -> None:
        self.assertEqual(WORKFLOW.count('- cron: "17 3 * * *"'), 1)
        self.assertIn("default: \"5\"", WORKFLOW)
        self.assertIn("github.event.inputs.passing_repeat_count || '5'", WORKFLOW)
        self.assertNotIn("failure_repeat_count", WORKFLOW)

    def test_complete_gates_and_failure_evidence(self) -> None:
        self.assertIn("scripts/e2e-adversarial-lab.py", WORKFLOW)
        self.assertIn("scripts/e2e-lifecycle-gate.py", WORKFLOW)
        self.assertIn("--repeat-count", WORKFLOW)
        self.assertNotIn("--failure-repeat-count", WORKFLOW)
        self.assertNotIn("--ceiling-policy", WORKFLOW)
        self.assertIn("BUTTONHEIST_RESULTS_MODE: failures", WORKFLOW)
        self.assertEqual(WORKFLOW.count("if: failure()"), 2)
        self.assertNotIn("git submodule update", WORKFLOW)


if __name__ == "__main__":
    unittest.main()
