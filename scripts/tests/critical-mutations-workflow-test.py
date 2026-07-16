#!/usr/bin/env python3

import unittest
from pathlib import Path


WORKFLOW = (
    Path(__file__).resolve().parents[2] / ".github/workflows/critical-mutations.yml"
).read_text()


class CriticalMutationsWorkflowTests(unittest.TestCase):
    def test_scheduled_and_manual_runs_use_the_complete_exact_sha_gate(self) -> None:
        self.assertEqual(WORKFLOW.count('cron: "13 4 * * 1"'), 1)
        self.assertIn("workflow_dispatch:", WORKFLOW)
        self.assertIn("scripts/mutation-gate.py", WORKFLOW)
        self.assertIn('--commit "${{ github.sha }}"', WORKFLOW)
        self.assertIn("--all", WORKFLOW)
        self.assertIn('--simulator-name "$SIM_NAME"', WORKFLOW)

    def test_every_terminal_path_uploads_evidence_and_removes_the_simulator(self) -> None:
        self.assertEqual(WORKFLOW.count("if: always()"), 2)
        self.assertIn("buttonheist-scheduled-critical-mutations", WORKFLOW)
        self.assertIn('xcrun simctl shutdown "$SIM_UDID"', WORKFLOW)
        self.assertIn('xcrun simctl delete "$SIM_UDID"', WORKFLOW)


if __name__ == "__main__":
    unittest.main()
