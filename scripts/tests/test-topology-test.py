#!/usr/bin/env python3

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TEST_ROOT = ROOT / "ButtonHeist/Tests/TheInsideJobTests"
PROJECT = (ROOT / "Project.swift").read_text(encoding="utf-8")
SOURCE_PREFIX = "ButtonHeist/Tests/TheInsideJobTests/"

EXPECTED_OWNERS = {
    "Logic": {"TheInsideJobLogicTests"},
    "Window": {"TheInsideJobWindowTests"},
    "Integration": {"TheInsideJobIntegrationTests"},
    "HostedBehavior": {"TheInsideJobHostedBehaviorTests"},
    "Shared/LogicWindow": {
        "TheInsideJobLogicTests",
        "TheInsideJobWindowTests",
    },
    "Shared/Socket": {
        "TheInsideJobLogicTests",
        "TheInsideJobWindowTests",
        "TheInsideJobIntegrationTests",
    },
}


def inside_job_source_owners() -> dict[str, set[str]]:
    configurations = re.finditer(
        r"(?:unhostedInsideJobTestTarget|HostedTestDescriptor)\("
        r'\s*name: "(?P<name>[^"]+)"(?P<body>.*?)(?=\n\s{0,4}\),?)',
        PROJECT,
        re.DOTALL,
    )
    owners: dict[str, set[str]] = {}
    for configuration in configurations:
        name = configuration.group("name")
        for source in re.findall(
            rf'"{re.escape(SOURCE_PREFIX)}([^"]+)/\*\*"',
            configuration.group("body"),
        ):
            owners.setdefault(source, set()).add(name)
    return owners


class TestTopologyTests(unittest.TestCase):
    def test_every_inside_job_source_has_one_admitted_directory(self) -> None:
        admitted = set(EXPECTED_OWNERS)
        sources = list(TEST_ROOT.rglob("*.swift"))
        actual_directories = {
            source.relative_to(TEST_ROOT).parent.as_posix()
            for source in sources
        }

        for source in sources:
            relative = source.relative_to(TEST_ROOT)
            directory = relative.parent.as_posix()
            with self.subTest(source=relative):
                self.assertIn(directory, admitted)
        self.assertEqual(actual_directories, admitted)

    def test_each_directory_maps_to_its_intended_targets(self) -> None:
        self.assertEqual(inside_job_source_owners(), EXPECTED_OWNERS)

    def test_project_uses_directory_globs_instead_of_file_manifests(self) -> None:
        self.assertNotRegex(
            PROJECT,
            rf'"{re.escape(SOURCE_PREFIX)}[^"]+\.swift"',
        )

    def test_logic_target_is_unhosted(self) -> None:
        definition = PROJECT.split(
            "func unhostedInsideJobTestTarget",
            1,
        )[1].split("func testScheme", 1)[0]
        logic_configuration = PROJECT.split(
            'name: "TheInsideJobLogicTests"',
            1,
        )[1].split("let hostedTestDescriptors", 1)[0]

        for forbidden in (
            "BH Demo",
            "ButtonHeistHostedTestSupport",
            "BUNDLE_LOADER",
            "TEST_HOST",
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, definition)
                self.assertNotIn(forbidden, logic_configuration)


if __name__ == "__main__":
    unittest.main()
