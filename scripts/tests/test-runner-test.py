#!/usr/bin/env python3

import os
import runpy
import unittest
from pathlib import Path
from unittest import mock


RUNNER = runpy.run_path(str(Path(__file__).resolve().parents[1] / "test-runner.py"))
SUITES = RUNNER["SUITES"]
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
                "TheScoreTests",
                "ButtonHeistTests",
                "TheInsideJobTests",
                "TheInsideJobIntegrationTests",
                "HostedBehaviorTests",
                "MacFrameworkTests",
            },
        )
    def test_arguments_expand_suites_in_source_order(self) -> None:
        args = RUNNER["parse_args"](
            ["run", "TheScoreTests", "ButtonHeistTests", "--selection", "full"]
        )
        self.assertEqual(args.suites, ["TheScoreTests", "ButtonHeistTests"])
        self.assertEqual(args.selection, "full")

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
