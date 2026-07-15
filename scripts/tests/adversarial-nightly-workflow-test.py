#!/usr/bin/env python3

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_PATH = REPO_ROOT / ".github/workflows/adversarial-nightly.yml"


def indented_block(text: str, anchor: str, indent: int) -> str:
    lines = text.splitlines()
    anchor_index = next(
        index for index, line in enumerate(lines) if line == f"{' ' * indent}{anchor}:"
    )
    block = []
    for line in lines[anchor_index + 1 :]:
        if line and len(line) - len(line.lstrip()) <= indent:
            break
        block.append(line)
    return "\n".join(block)


def mapping_value(block: str, key: str) -> str:
    match = re.search(rf"^\s*{re.escape(key)}:\s*(.+?)\s*$", block, re.MULTILINE)
    if match is None:
        raise AssertionError(f"missing mapping key: {key}")
    return match.group(1).strip('"')


def step_containing(text: str, token: str) -> str:
    steps = re.split(r"(?m)^\s{6}-\s+", text)
    return next(step for step in steps if token in step)


class AdversarialNightlyWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow = WORKFLOW_PATH.read_text()

    def test_one_daily_schedule_has_bounded_repeat_policy(self) -> None:
        schedules = re.findall(
            r'^\s*- cron:\s*["\']([^"\']+)["\']',
            self.workflow,
            re.MULTILINE,
        )
        self.assertEqual(schedules, ["17 3 * * *"])

        job = indented_block(self.workflow, "adversarial-nightly", 2)
        passing_policy = mapping_value(job, "BUTTONHEIST_ADVERSARIAL_REPEAT_COUNT")
        failure_policy = mapping_value(job, "BUTTONHEIST_ADVERSARIAL_FAILURE_REPEAT_COUNT")

        self.assertEqual(
            passing_policy,
            "${{ github.event.inputs.passing_repeat_count || '5' }}",
        )
        self.assertEqual(
            failure_policy,
            "${{ github.event.inputs.failure_repeat_count || '1' }}",
        )

    def test_manual_dispatch_defaults_passing_and_failure_repeats_separately(self) -> None:
        dispatch = indented_block(self.workflow, "workflow_dispatch", 2)
        inputs = indented_block(dispatch, "inputs", 4)
        passing = indented_block(inputs, "passing_repeat_count", 6)
        failing = indented_block(inputs, "failure_repeat_count", 6)

        self.assertEqual(mapping_value(passing, "default"), "5")
        self.assertEqual(mapping_value(failing, "default"), "1")

    def test_nightly_owns_the_complete_adversarial_matrix(self) -> None:
        lab_step = step_containing(self.workflow, "scripts/e2e-adversarial-lab.py")
        lifecycle_step = step_containing(self.workflow, "scripts/e2e-lifecycle-gate.py")

        self.assertIn('--repeat-count "$BUTTONHEIST_ADVERSARIAL_REPEAT_COUNT"', lab_step)
        self.assertIn(
            '--failure-repeat-count "$BUTTONHEIST_ADVERSARIAL_FAILURE_REPEAT_COUNT"',
            lab_step,
        )
        self.assertNotRegex(lab_step, r"--(?:scenario|filter|only)\b")
        self.assertNotRegex(lifecycle_step, r"--(?:scenario|filter|only)\b")

        lab_source = (REPO_ROOT / "scripts/e2e-adversarial-lab.py").read_text()
        self.assertRegex(lab_source, r"for scenario, plan in PASSING_PLANS\.items\(\):")
        self.assertRegex(
            lab_source,
            r"for scenario, \(plan, expected_text\) in FAILING_PLANS\.items\(\):",
        )

    def test_receipts_and_diagnostics_are_retained_only_when_the_job_fails(self) -> None:
        job = indented_block(self.workflow, "adversarial-nightly", 2)
        self.assertEqual(mapping_value(job, "BUTTONHEIST_RECEIPTS_MODE"), "failures")

        diagnostic_step = step_containing(
            self.workflow,
            'mkdir -p "$BUTTONHEIST_RECEIPTS_DIR/diagnostics"',
        )
        artifact_step = step_containing(
            self.workflow,
            "./.github/actions/finalize-heist-receipts",
        )
        self.assertRegex(diagnostic_step, r"(?m)^\s*if:\s*failure\(\)\s*$")
        self.assertIn("buttonheist-adversarial-nightly-report.json", diagnostic_step)
        self.assertIn("buttonheist-lifecycle-nightly-report.json", diagnostic_step)
        self.assertRegex(artifact_step, r"(?m)^\s*if:\s*failure\(\)\s*$")


if __name__ == "__main__":
    unittest.main()
