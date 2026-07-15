#!/usr/bin/env python3

import re
import unittest
from pathlib import Path


WORKFLOW = (Path(__file__).resolve().parents[2] / ".github/workflows/ci.yml").read_text()


def job_blocks() -> dict[str, str]:
    jobs = WORKFLOW.split("\njobs:\n", 1)[1]
    starts = list(re.finditer(r"(?m)^  ([a-z0-9-]+):\n", jobs))
    return {
        match.group(1): jobs[match.end() : starts[index + 1].start()]
        if index + 1 < len(starts)
        else jobs[match.end() :]
        for index, match in enumerate(starts)
    }


class CIWorkflowTests(unittest.TestCase):
    def test_macos_runner_topology(self) -> None:
        blocks = job_blocks()
        pr_jobs = {
            name
            for name, block in blocks.items()
            if "runs-on: macos-15" in block and "github.event_name == 'pull_request'" in block
        }
        main_jobs = {
            name
            for name, block in blocks.items()
            if "runs-on: macos-15" in block and "github.ref == 'refs/heads/main'" in block
        }

        self.assertEqual(pr_jobs, {"macos-tests", "ios-tests", "ios-demo-gates"})
        self.assertEqual(main_jobs, {"main-integration"})

    def test_portable_contracts_stay_on_linux(self) -> None:
        release = job_blocks()["release-contract"]
        self.assertIn("runs-on: ubuntu-latest", release)
        self.assertNotRegex(release, r"\b(?:xcodebuild|tuist)\b")

    def test_hosted_canaries_reuse_the_dedicated_simulator(self) -> None:
        hosted = job_blocks()["ios-demo-gates"]
        self.assertIn("-parallel-testing-enabled NO", hosted)
        self.assertNotIn("-parallel-testing-worker-count", hosted)


if __name__ == "__main__":
    unittest.main()
