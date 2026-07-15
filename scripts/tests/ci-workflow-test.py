#!/usr/bin/env python3

import re
import unittest
from pathlib import Path


WORKFLOW = (Path(__file__).resolve().parents[2] / ".github/workflows/ci.yml").read_text()
PROJECT = (Path(__file__).resolve().parents[2] / "Project.swift").read_text()


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
        hosted_scheme = PROJECT.split('name: "HostedBehaviorTests"', 1)[1]
        self.assertIn("parallelization: .disabled", hosted_scheme)

    def test_tuist_test_jobs_do_not_initialize_the_parser_submodule(self) -> None:
        blocks = job_blocks()
        for name in ("macos-tests", "ios-tests", "ios-demo-gates", "main-integration"):
            with self.subTest(job=name):
                self.assertNotIn("git submodule update", blocks[name])

    def test_macos_frameworks_share_one_test_invocation(self) -> None:
        macos = job_blocks()["macos-tests"]
        self.assertIn("tuist test MacFrameworkTests --no-selective-testing", macos)
        self.assertNotIn("for scheme in", macos)
        self.assertIn('name: "MacFrameworkTests"', PROJECT)

    def test_swift_test_owns_cli_and_mcp_builds(self) -> None:
        macos = job_blocks()["macos-tests"]
        self.assertIn("scripts/swift-test-gate.sh ButtonHeistCLI", macos)
        self.assertIn("scripts/swift-test-gate.sh ButtonHeistMCP", macos)
        self.assertNotIn("swift build --package-path ButtonHeistCLI", macos)
        self.assertNotIn("swift build --package-path ButtonHeistMCP", macos)

    def test_expensive_macos_scopes_follow_the_tested_path_classifier(self) -> None:
        macos = job_blocks()["macos-tests"]
        release = job_blocks()["release-contract"]
        self.assertIn("id: changes", macos)
        self.assertIn("git diff --name-only --no-renames", macos)
        self.assertIn(
            'python3 scripts/select-ci-change-scopes.py --github-output "$GITHUB_OUTPUT"',
            macos,
        )
        self.assertIn(
            "if: steps.changes.outputs.run_bumper_rule_tests == 'true'",
            macos,
        )
        self.assertIn("run: scripts/check-source-shape.sh test", macos)
        self.assertIn(
            "if: steps.changes.outputs.run_package_api_contracts == 'true'",
            macos,
        )
        self.assertIn(
            "if: steps.changes.outputs.run_cli_tool_tests == 'true'",
            macos,
        )
        self.assertIn("python3 scripts/tests/select-ci-change-scopes-test.py", release)


if __name__ == "__main__":
    unittest.main()
