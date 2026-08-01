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

    def test_reports_are_retained_for_green_and_red_runs(self) -> None:
        upload_step = WORKFLOW[WORKFLOW.index("- name: Upload nightly reports"):]
        self.assertIn("if: always()", upload_step)
        self.assertIn("actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02", upload_step)
        self.assertIn("buttonheist-adversarial-nightly-report.json", upload_step)
        self.assertIn("buttonheist-lifecycle-nightly-report.json", upload_step)
        self.assertIn("retention-days: 30", upload_step)

    def test_summary_exposes_sampling_classification_and_cli_timing(self) -> None:
        summary_step = WORKFLOW[WORKFLOW.index("- name: Summarize nightly reports"):]
        self.assertIn("Requested / recorded", summary_step)
        self.assertIn("Classification", summary_step)
        self.assertIn("CLI timing (p50 / p95)", summary_step)
        self.assertIn("cliWallDurationMs", summary_step)

    def test_runner_owns_named_simulator_preparation_and_cleanup(self) -> None:
        simulator_name = (
            "buttonheist-ci-adversarial-${{ github.run_id }}-"
            "${{ github.run_attempt }}"
        )
        prepare = (
            "scripts/test-runner.py prepare-simulator \\\n"
            '            --simulator-name "$BUTTONHEIST_TEST_SIMULATOR_NAME"'
        )
        cleanup = (
            'run: scripts/test-runner.py cleanup --simulator-name '
            '"$BUTTONHEIST_TEST_SIMULATOR_NAME"'
        )

        self.assertEqual(
            WORKFLOW.count(
                f"BUTTONHEIST_TEST_SIMULATOR_NAME: {simulator_name}"
            ),
            1,
        )
        self.assertEqual(WORKFLOW.count(prepare), 1)
        self.assertEqual(WORKFLOW.count(cleanup), 1)
        self.assertLess(WORKFLOW.index(prepare), WORKFLOW.index(cleanup))
        cleanup_step = WORKFLOW[WORKFLOW.index("- name: Clean up adversarial simulator"):]
        self.assertIn("if: always()", cleanup_step)
        self.assertNotIn("select-ios-ci-simulator.py", WORKFLOW)


if __name__ == "__main__":
    unittest.main()
