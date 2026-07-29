#!/usr/bin/env python3

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TEST_ROOT = ROOT / "ButtonHeist/Tests/TheInsideJobTests"
ADMITTED_DIRECTORIES = {
    "HostedBehavior",
    "Integration",
    "Logic",
    "Shared/LogicWindow",
    "Shared/Socket",
    "Window",
}


class TestTopologyTests(unittest.TestCase):
    def test_swift_sources_stay_in_admitted_directories(self) -> None:
        outside = sorted(
            source.relative_to(TEST_ROOT).as_posix()
            for source in TEST_ROOT.rglob("*.swift")
            if source.relative_to(TEST_ROOT).parent.as_posix()
            not in ADMITTED_DIRECTORIES
        )

        self.assertEqual(outside, [])


if __name__ == "__main__":
    unittest.main()
