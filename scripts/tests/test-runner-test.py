#!/usr/bin/env python3

import os
import runpy
import subprocess
import unittest
from pathlib import Path
from unittest import mock


RUNNER = runpy.run_path(str(Path(__file__).resolve().parents[1] / "test-runner.py"))
SUITES = RUNNER["SUITES"]
FOCUSES = RUNNER["FOCUSES"]
SIMULATOR = {
    "udid": "TEST-UDID",
    "name": "test-simulator",
    "device": "iPhone 16 Pro",
    "os": "26.3",
}


class TestRunnerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.environment = mock.patch.dict(
            os.environ,
            {
                "BUTTONHEIST_TEST_ARTIFACTS_DIR": "/artifacts",
                "BUTTONHEIST_TEST_DERIVED_DATA_ROOT": "/derived",
            },
        )
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def test_catalog_has_only_canonical_suite_spellings(self) -> None:
        self.assertEqual(
            set(SUITES),
            {
                "ReleaseContractTests",
                "TheScoreTests",
                "ButtonHeistTests",
                "TheInsideJobTests",
                "TheInsideJobIntegrationTests",
                "HostedBehaviorTests",
                "MacFrameworkTests",
            },
        )

    def test_focus_catalog_owns_vertical_contracts_and_named_mutations(self) -> None:
        self.assertTrue(
            {
                "contract-actions",
                "contract-predicates",
                "contract-receipts",
                "contract-wire",
                "contract-targets",
                "mutation-receipt-kind",
                "mutation-release-proof",
                "mutation-child-abort-path",
                "mutation-live-target-refresh",
                "mutation-interaction-fifo",
                "mutation-receipt-legality",
                "mutation-screen-generation",
                "mutation-active-cancellation",
                "mutation-settlement-threshold",
                "mutation-stale-discovery",
            }.issubset(FOCUSES)
        )

    def test_portable_contract_runs_through_the_canonical_interface(self) -> None:
        suite = SUITES["ReleaseContractTests"]
        paths = RUNNER["suite_paths"]("ReleaseContractTests")

        command = RUNNER["test_command"](
            "run", "ReleaseContractTests", suite, paths, None, "full"
        )

        self.assertEqual(
            command,
            [str(RUNNER["ROOT"] / "scripts/tests/require-successful-ci-for-commit-test.sh")],
        )
        with self.assertRaisesRegex(ValueError, "supports run mode only"):
            RUNNER["test_command"](
                "build-for-testing",
                "ReleaseContractTests",
                suite,
                paths,
                None,
                "full",
            )

    def test_arguments_expand_suites_in_source_order(self) -> None:
        args = RUNNER["parse_args"](
            ["run", "TheScoreTests", "ButtonHeistTests", "--selection", "full"]
        )
        self.assertEqual(args.suites, ["TheScoreTests", "ButtonHeistTests"])
        self.assertEqual(args.selection, "full")

    def test_arguments_accept_focus_instead_of_suites(self) -> None:
        args = RUNNER["parse_args"]([
            "run",
            "--focus",
            "contract-actions",
            "--focus",
            "contract-receipts",
        ])

        self.assertEqual(args.suites, [])
        self.assertEqual(args.focus, ["contract-actions", "contract-receipts"])

    def test_arguments_reject_mixed_or_missing_selection(self) -> None:
        with self.assertRaises(ValueError):
            RUNNER["parse_args"]([
                "run",
                "TheScoreTests",
                "--focus",
                "contract-actions",
            ])
        with self.assertRaises(ValueError):
            RUNNER["parse_args"](["run"])

    def test_focus_expansion_merges_tests_per_suite_without_duplicates(self) -> None:
        selected = RUNNER["focus_runs"]([
            "contract-predicates",
            "contract-receipts",
            "contract-predicates",
        ])

        self.assertEqual(list(selected), ["TheScoreTests"])
        self.assertEqual(
            selected["TheScoreTests"],
            (
                "TheScoreTests/AccessibilityPredicateTests",
                "TheScoreTests/HeistExecutionReceiptContractTests",
            ),
        )

    def test_paths_are_deterministic(self) -> None:
        for name in SUITES:
            paths = RUNNER["suite_paths"](name)
            self.assertEqual(
                paths["result"],
                Path(f"/artifacts/{name}/results/{name}.xcresult"),
            )
            self.assertEqual(paths["receipts"], Path(f"/artifacts/{name}/receipts"))
            self.assertEqual(paths["diagnostics"], Path(f"/artifacts/{name}/diagnostics"))
            self.assertEqual(paths["derived"], Path(f"/derived/{name}"))
            self.assertEqual(paths["record"], Path(f"/artifacts/{name}/run.json"))

    def test_local_run_owns_full_and_selective_flags(self) -> None:
        suite = SUITES["TheScoreTests"]
        paths = RUNNER["suite_paths"]("TheScoreTests")
        selective = RUNNER["test_command"](
            "run", "TheScoreTests", suite, paths, None, "selective"
        )
        full = RUNNER["test_command"](
            "run", "TheScoreTests", suite, paths, None, "full"
        )
        self.assertIn("--selective-testing", selective)
        self.assertNotIn("--no-selective-testing", selective)
        self.assertIn("--no-selective-testing", full)
        self.assertIn("platform=macOS", full)
        self.assertIn(str(paths["result"]), full)
        self.assertIn(str(paths["receipts"]), full)

    def test_focused_run_passes_only_testing_identifiers_to_canonical_command(self) -> None:
        suite = SUITES["TheScoreTests"]
        paths = RUNNER["suite_paths"]("TheScoreTests")
        command = RUNNER["test_command"](
            "run",
            "TheScoreTests",
            suite,
            paths,
            None,
            "full",
            (
                "TheScoreTests/AccessibilityPredicateTests",
                "TheScoreTests/HeistExecutionReceiptContractTests",
            ),
        )

        self.assertIn("-only-testing:TheScoreTests/AccessibilityPredicateTests", command)
        self.assertIn(
            "-only-testing:TheScoreTests/HeistExecutionReceiptContractTests",
            command,
        )

    def test_catalog_manifest_is_a_deterministic_projection_of_one_owner(self) -> None:
        manifest = RUNNER["catalog_manifest"]()

        self.assertEqual(list(manifest["suites"]), list(SUITES))
        self.assertEqual(list(manifest["focuses"]), list(FOCUSES))
        self.assertEqual(
            manifest["focuses"]["contract-predicates"],
            {"TheScoreTests": ["TheScoreTests/AccessibilityPredicateTests"]},
        )

    def test_source_state_records_commit_and_cleanliness(self) -> None:
        commit = mock.Mock(stdout="abc123\n")
        status = mock.Mock(stdout=" M source.swift\n")
        with mock.patch.object(RUNNER["subprocess"], "run", side_effect=[commit, status]):
            source = RUNNER["source_state"]()

        self.assertEqual(source.commit, "abc123")
        self.assertFalse(source.clean)

    def test_result_summary_rejects_zero_tests(self) -> None:
        completed = mock.Mock(stdout='{"totalTestCount": 0}')
        with mock.patch.object(RUNNER["subprocess"], "run", return_value=completed):
            with self.assertRaisesRegex(RuntimeError, "zero tests"):
                RUNNER["require_executed_tests"](Path("/results/tests.xcresult"))

    def test_result_summary_returns_executed_test_count(self) -> None:
        completed = mock.Mock(stdout='{"totalTestCount": 7}')
        with mock.patch.object(RUNNER["subprocess"], "run", return_value=completed):
            self.assertEqual(
                RUNNER["require_executed_tests"](Path("/results/tests.xcresult")),
                7,
            )

    def test_phase_timeout_terminates_the_process_group_and_is_classified(self) -> None:
        process = mock.Mock(pid=123)
        process.wait.side_effect = [subprocess.TimeoutExpired(["test"], 3), 0]
        with mock.patch.object(RUNNER["subprocess"], "Popen", return_value=process), \
             mock.patch.object(RUNNER["os"], "killpg") as kill_group, \
             mock.patch.object(RUNNER["time"], "monotonic", side_effect=[10.0, 13.0]):
            result = RUNNER["run_phase"](["test"], "tests", 3)

        self.assertEqual(result.exit_code, 124)
        self.assertEqual(result.phase, "tests")
        self.assertTrue(result.timed_out)
        self.assertEqual(result.duration_seconds, 3.0)
        kill_group.assert_called_once_with(123, RUNNER["signal"].SIGTERM)

    def test_split_modes_share_destination_and_paths(self) -> None:
        suite = SUITES["TheInsideJobIntegrationTests"]
        paths = RUNNER["suite_paths"]("TheInsideJobIntegrationTests")
        build = RUNNER["test_command"](
            "build-for-testing", "TheInsideJobIntegrationTests",
            suite, paths, SIMULATOR, "full"
        )
        test = RUNNER["test_command"](
            "test-without-building", "TheInsideJobIntegrationTests",
            suite, paths, SIMULATOR, "full"
        )
        expected_destination = "platform=iOS Simulator,id=TEST-UDID,arch=arm64"
        self.assertIn(expected_destination, build)
        self.assertIn(expected_destination, test)
        self.assertIn(str(paths["derived"]), build)
        self.assertIn(str(paths["derived"]), test)
        self.assertNotIn(str(RUNNER["WRAPPER"]), build)
        self.assertIn(str(RUNNER["WRAPPER"]), test)
        self.assertIn("--ios-sandbox", test)
        self.assertIn(str(paths["result"]), test)

    def test_macos_supports_prebuilt_focused_feedback(self) -> None:
        suite = SUITES["TheScoreTests"]
        paths = RUNNER["suite_paths"]("TheScoreTests")
        selected = ("TheScoreTests/HeistExecutionReceiptContractTests",)
        build = RUNNER["test_command"](
            "build-for-testing",
            "TheScoreTests",
            suite,
            paths,
            None,
            "full",
            selected,
        )
        test = RUNNER["test_command"](
            "test-without-building",
            "TheScoreTests",
            suite,
            paths,
            None,
            "full",
            selected,
        )

        self.assertIn("platform=macOS", build)
        self.assertIn("platform=macOS", test)
        self.assertIn(
            "-only-testing:TheScoreTests/HeistExecutionReceiptContractTests",
            build,
        )
        self.assertIn(
            "-only-testing:TheScoreTests/HeistExecutionReceiptContractTests",
            test,
        )

    def test_hosted_behavior_is_serial(self) -> None:
        suite = SUITES["HostedBehaviorTests"]
        paths = RUNNER["suite_paths"]("HostedBehaviorTests")
        command = RUNNER["test_command"](
            "test-without-building", "HostedBehaviorTests",
            suite, paths, SIMULATOR, "full"
        )
        index = command.index("-parallel-testing-enabled")
        self.assertEqual(command[index + 1], "NO")

    def test_simulator_receipt_cleanup_is_scoped_to_selected_device(self) -> None:
        with mock.patch.object(RUNNER["Path"], "home", return_value=Path("/Users/test")), \
             mock.patch.object(RUNNER["Path"], "exists", return_value=True), \
             mock.patch.object(RUNNER["Path"], "glob", return_value=[Path("/receipt-dir")]), \
             mock.patch.object(RUNNER["shutil"], "rmtree") as remove:
            RUNNER["clear_simulator_receipts"](SIMULATOR)

        remove.assert_called_once_with(Path("/receipt-dir"))

    @mock.patch.object(RUNNER["subprocess"], "run")
    def test_dependency_install_runs_once_for_multiple_suites(
        self,
        run: mock.Mock,
    ) -> None:
        run.return_value.returncode = 0
        with mock.patch.dict(
            RUNNER["main"].__globals__,
            {"execute": mock.Mock(return_value=0)},
        ):
            status = RUNNER["main"]([
                "run",
                "TheScoreTests",
                "ButtonHeistTests",
                "--install-dependencies",
            ])

        self.assertEqual(status, 0)
        run.assert_called_once_with(["tuist", "install"], check=True)


if __name__ == "__main__":
    unittest.main()
