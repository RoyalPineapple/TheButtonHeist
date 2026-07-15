#!/usr/bin/env python3

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = (REPO_ROOT / ".github/workflows/ci.yml").read_text()


def job_blocks() -> dict[str, str]:
    jobs = WORKFLOW.split("\njobs:\n", 1)[1]
    matches = list(re.finditer(r"(?m)^  ([a-z0-9-]+):\n", jobs))
    return {
        match.group(1): jobs[match.end() : matches[index + 1].start()]
        if index + 1 < len(matches)
        else jobs[match.end() :]
        for index, match in enumerate(matches)
    }


class CIWorkflowTests(unittest.TestCase):
    def test_pull_requests_use_exactly_three_macos_runners(self) -> None:
        blocks = job_blocks()
        mac_jobs = {
            name
            for name, block in blocks.items()
            if "runs-on: macos-15" in block
            and "if: github.event_name == 'pull_request'" in block
        }
        self.assertEqual(mac_jobs, {"macos-tests", "ios-tests", "ios-demo-gates"})

    def test_main_owns_only_the_integration_macos_job(self) -> None:
        blocks = job_blocks()
        main_mac_jobs = {
            name
            for name, block in blocks.items()
            if "runs-on: macos-15" in block
            and "if: github.event_name == 'push' && github.ref == 'refs/heads/main'" in block
        }
        self.assertEqual(main_mac_jobs, {"main-integration"})
        self.assertIn("-scheme TheInsideJobIntegrationTests", blocks["main-integration"])

    def test_portable_contracts_stay_on_linux(self) -> None:
        release = job_blocks()["release-contract"]
        self.assertIn("runs-on: ubuntu-latest", release)
        self.assertNotIn("xcodebuild", release)
        self.assertNotIn("tuist", release)

    def test_test_membership_and_failure_evidence_are_structural(self) -> None:
        self.assertNotIn("-only-testing", WORKFLOW)
        self.assertNotIn("-skip-testing", WORKFLOW)
        self.assertEqual(WORKFLOW.count("-collect-test-diagnostics never"), 3)

        for job in ("macos-tests", "ios-tests", "ios-demo-gates", "main-integration"):
            block = job_blocks()[job]
            for match in re.finditer(r"(?m)^      - name: (?:Collect|Upload).+$", block):
                following = block[match.end() :].split("\n      - name:", 1)[0]
                self.assertIn("if: failure()", following, f"{job}: {match.group(0)}")


if __name__ == "__main__":
    unittest.main()
