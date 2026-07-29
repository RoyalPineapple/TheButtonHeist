#!/usr/bin/env python3

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PROJECT = (ROOT / "Project.swift").read_text(encoding="utf-8")
TEST_ROOT = ROOT / "ButtonHeist/Tests/TheInsideJobTests"

SOURCE_LISTS = {
    "shared": "insideJobSharedLogicWindowTestSources",
    "shared_socket": "insideJobSharedSocketTestSources",
    "logic": "insideJobLogicOnlyTestSources",
    "window": "insideJobWindowOnlyTestSources",
    "integration": "insideJobIntegrationTestSources",
    "behavior": "insideJobHostedBehaviorTestSources",
}


def source_list(name: str) -> set[str]:
    match = re.search(
        rf"let {re.escape(name)}: SourceFilesList = \[(.*?)\n\]",
        PROJECT,
        re.DOTALL,
    )
    if match is None:
        raise AssertionError(f"Missing source list {name}")
    return set(re.findall(r'"(ButtonHeist/Tests/TheInsideJobTests/[^"]+\.swift)"', match.group(1)))


class TestTopologyContractTests(unittest.TestCase):
    def test_every_inside_job_test_source_has_explicit_boundary_ownership(self) -> None:
        ownership = {
            boundary: source_list(name)
            for boundary, name in SOURCE_LISTS.items()
        }
        actual = {
            path.relative_to(ROOT).as_posix()
            for path in TEST_ROOT.rglob("*.swift")
        }

        self.assertEqual(set().union(*ownership.values()), actual)
        for boundary, sources in ownership.items():
            others = set().union(*(
                other_sources
                for other_boundary, other_sources in ownership.items()
                if other_boundary != boundary
            ))
            self.assertFalse(sources & others, boundary)
            self.assertFalse(any("*" in source for source in sources), boundary)

    def test_logic_target_is_structurally_unhosted(self) -> None:
        helper = PROJECT.split("func unhostedInsideJobTestTarget(", 1)[1].split(
            "\nfunc hostedTestTarget(",
            1,
        )[0]
        logic_target = PROJECT.split("let insideJobLogicTestTarget =", 1)[1].split(
            "\nlet hostedTestDescriptors =",
            1,
        )[0]

        for forbidden in (
            "BUNDLE_LOADER",
            "TEST_HOST",
            "BH Demo",
            "ButtonHeistHostedTestSupport",
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, helper)
        self.assertIn('.target(name: "TheInsideJob")', helper)
        self.assertIn("unhostedInsideJobTestTarget(", logic_target)
        self.assertIn("insideJobLogicOnlyTestSources", logic_target)
        self.assertIn("insideJobSharedLogicWindowTestSources", logic_target)

    def test_logic_sources_do_not_reach_host_boundaries(self) -> None:
        logic_sources = set().union(*(
            source_list(SOURCE_LISTS[boundary])
            for boundary in ("logic", "shared", "shared_socket")
        ))
        host_markers = (
            "UIApplication.shared",
            "UIAccessibility.post(",
            "requireForegroundWindowScene",
            "makeKeyAndVisible()",
            "@testable import BHDemo",
            "import ButtonHeistHostedTestSupport",
        )

        for source in logic_sources:
            text = (ROOT / source).read_text(encoding="utf-8")
            with self.subTest(source=source):
                self.assertFalse(any(marker in text for marker in host_markers))

    def test_window_sources_state_their_process_or_foreground_dependency(self) -> None:
        direct_markers = (
            "UIApplication.shared",
            "UIAccessibility.post(",
            "requireForegroundWindowScene",
            "makeKeyAndVisible()",
            "anchorWindow = UIWindow",
            "live UIWindowScene test host",
            "@testable import BHDemo",
        )
        cross_file_families = (
            "ElementInflationProduct",
            "TheBrainsAction",
            "TheBrainsScroll",
        )

        for source in source_list(SOURCE_LISTS["window"]):
            text = (ROOT / source).read_text(encoding="utf-8")
            name = Path(source).name
            demonstrates_boundary = (
                any(marker in text for marker in direct_markers)
                or name.startswith(cross_file_families)
            )
            with self.subTest(source=source):
                self.assertTrue(demonstrates_boundary)

    def test_system_and_demo_boundaries_are_not_logic_sources(self) -> None:
        integration_markers = (
            "NWConnection",
            "startPlaintext(",
            "startAsync(",
            "BonjourAdvertisement",
        )
        for source in source_list(SOURCE_LISTS["integration"]):
            text = (ROOT / source).read_text(encoding="utf-8")
            with self.subTest(source=source):
                self.assertTrue(any(marker in text for marker in integration_markers))

        for source in source_list(SOURCE_LISTS["behavior"]):
            text = (ROOT / source).read_text(encoding="utf-8")
            with self.subTest(source=source):
                self.assertIn("import ButtonHeistHostedTestSupport", text)

    def test_project_declares_all_four_runner_boundaries(self) -> None:
        for name in (
            "TheInsideJobLogicTests",
            "TheInsideJobWindowTests",
            "TheInsideJobIntegrationTests",
            "HostedBehaviorTests",
        ):
            with self.subTest(name=name):
                self.assertIn(f'name: "{name}"', PROJECT)

    def test_source_groups_are_wired_to_their_declared_boundaries(self) -> None:
        logic = PROJECT.split("let insideJobLogicTestTarget =", 1)[1].split(
            "\nlet hostedTestDescriptors =",
            1,
        )[0]
        window = PROJECT.split('name: "TheInsideJobWindowTests"', 1)[1].split(
            "runsInBehaviorSuite:",
            1,
        )[0]
        integration = PROJECT.split('name: "TheInsideJobIntegrationTests"', 1)[1].split(
            "runsInBehaviorSuite:",
            1,
        )[0]
        behavior = PROJECT.split('name: "TheInsideJobHostedBehaviorTests"', 1)[1].split(
            'name: "DogfoodFeatureFlowTests"',
            1,
        )[0]

        for source_group in (
            "insideJobLogicOnlyTestSources",
            "insideJobSharedLogicWindowTestSources",
            "insideJobSharedSocketTestSources",
        ):
            self.assertIn(source_group, logic)
        for source_group in (
            "insideJobWindowOnlyTestSources",
            "insideJobSharedLogicWindowTestSources",
            "insideJobSharedSocketTestSources",
        ):
            self.assertIn(source_group, window)
        for source_group in (
            "insideJobIntegrationTestSources",
            "insideJobSharedSocketTestSources",
        ):
            self.assertIn(source_group, integration)
        self.assertIn("insideJobHostedBehaviorTestSources", behavior)
        self.assertIn("runsInBehaviorSuite: true", behavior)
        self.assertIn(
            "let behaviorTestDescriptors = hostedTestDescriptors.filter",
            PROJECT,
        )


if __name__ == "__main__":
    unittest.main()
