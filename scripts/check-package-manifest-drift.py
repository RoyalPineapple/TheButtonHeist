#!/usr/bin/env python3
"""Guard intentional overlap between root and ButtonHeist SwiftPM manifests."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
ROOT_PACKAGE = REPO_ROOT
BUTTONHEIST_PACKAGE = REPO_ROOT / "ButtonHeist"

CONTRACT_TARGETS = (
    "ThePlans",
    "TheScore",
    "ButtonHeistDSL",
    "HeistPlanTool",
    "HeistDoctorCore",
    "HeistDoctorTool",
    "TheInsideJob",
    "ThePlant",
    "ButtonHeistTesting",
    "ButtonHeist",
)

EXPECTED_RELATIONSHIP_EDGES = {
    "ThePlans": (),
    "TheScore": (
        "product:AccessibilitySnapshotBH/AccessibilitySnapshotModel",
        "target:ThePlans",
    ),
    "ButtonHeist": (
        "product:AccessibilitySnapshotBH/AccessibilitySnapshotModel",
        "target:ButtonHeistSupport",
        "target:ThePlans",
        "target:TheScore",
    ),
}

def fail(message: str) -> None:
    print(f"::error::{message}", file=sys.stderr)
    raise SystemExit(1)


def dump_package(package_path: Path, cache_root: Path) -> dict[str, Any]:
    env = os.environ.copy()
    env.setdefault("CLANG_MODULE_CACHE_PATH", str(cache_root / "clang-module-cache"))

    command = [
        "swift",
        "package",
        "--disable-sandbox",
        "--cache-path",
        str(cache_root / "swiftpm-cache"),
        "--config-path",
        str(cache_root / "swiftpm-config"),
        "--security-path",
        str(cache_root / "swiftpm-security"),
        "--manifest-cache",
        "none",
        "--package-path",
        str(package_path),
        "dump-package",
    ]
    result = subprocess.run(
        command,
        cwd=REPO_ROOT,
        env=env,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode != 0:
        fail(
            "swift package dump-package failed for "
            f"{package_path.relative_to(REPO_ROOT)}:\n{result.stderr.strip()}"
        )
    return json.loads(result.stdout)


def stable_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def product_type(product: dict[str, Any]) -> str:
    product_type_value = product["type"]
    if "library" in product_type_value:
        return "library:" + stable_json(product_type_value["library"])
    if "executable" in product_type_value:
        return "executable"
    return stable_json(product_type_value)


def product_summary(package: dict[str, Any]) -> list[tuple[str, str, tuple[str, ...]]]:
    return sorted(
        (
            product["name"],
            product_type(product),
            tuple(product["targets"]),
        )
        for product in package["products"]
    )


def dependency_summary(dependency: dict[str, Any]) -> tuple[str, str, str]:
    if "sourceControl" in dependency:
        entry = dependency["sourceControl"][0]
        location = entry["location"]
        remote = location.get("remote", [{}])[0].get("urlString", "")
        return (
            entry["identity"],
            "sourceControl",
            stable_json(
                {
                    "remote": remote,
                    "requirement": entry.get("requirement"),
                }
            ),
        )
    if "fileSystem" in dependency:
        entry = dependency["fileSystem"][0]
        return (entry["identity"], "fileSystem", "local-path")
    return ("<unknown>", "<unknown>", stable_json(dependency))


def dependency_summaries(package: dict[str, Any]) -> dict[str, tuple[str, str]]:
    return {
        identity: (kind, detail)
        for identity, kind, detail in (
            dependency_summary(dependency) for dependency in package["dependencies"]
        )
    }


def condition_suffix(condition: Any) -> str:
    if not condition:
        return ""
    platforms = condition.get("platformNames")
    if platforms:
        return "[platforms=" + ",".join(sorted(platforms)) + "]"
    return "[" + stable_json(condition) + "]"


def target_dependency_id(dependency: dict[str, Any]) -> str:
    if "byName" in dependency:
        name, condition = dependency["byName"]
        return f"target:{name}{condition_suffix(condition)}"
    if "product" in dependency:
        product, package, _module_aliases, condition = dependency["product"]
        return f"product:{package}/{product}{condition_suffix(condition)}"
    return stable_json(dependency)


def target_map(package: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {target["name"]: target for target in package["targets"]}


def normalized_target_path(label: str, path: str | None) -> str | None:
    if path is None:
        return None
    if label == "root" and path.startswith("ButtonHeist/"):
        return path.removeprefix("ButtonHeist/")
    return path


def swift_language_mode(target: dict[str, Any]) -> str | None:
    for setting in target.get("settings", []):
        kind = setting.get("kind", {})
        mode = kind.get("swiftLanguageMode")
        if mode:
            return mode.get("_0")
    return None


def target_summary(label: str, target: dict[str, Any]) -> dict[str, Any]:
    return {
        "type": target["type"],
        "path": normalized_target_path(label, target.get("path")),
        "publicHeadersPath": target.get("publicHeadersPath"),
        "swiftLanguageMode": swift_language_mode(target),
        "dependencies": tuple(
            sorted(target_dependency_id(dependency) for dependency in target["dependencies"])
        ),
    }


def compare_equal(name: str, root_value: Any, buttonheist_value: Any, failures: list[str]) -> None:
    if root_value != buttonheist_value:
        failures.append(
            f"{name} drifted:\n"
            f"  root:        {stable_json(root_value)}\n"
            f"  ButtonHeist: {stable_json(buttonheist_value)}"
        )


def check_package_dependencies(
    root: dict[str, Any],
    buttonheist: dict[str, Any],
    failures: list[str],
) -> None:
    root_dependencies = dependency_summaries(root)
    buttonheist_dependencies = dependency_summaries(buttonheist)
    compare_equal(
        "package dependency identities",
        sorted(root_dependencies),
        sorted(buttonheist_dependencies),
        failures,
    )

    for identity in sorted(set(root_dependencies) & set(buttonheist_dependencies)):
        if identity == "accessibilitysnapshotbh":
            root_kind, root_detail = root_dependencies[identity]
            buttonheist_kind, _buttonheist_detail = buttonheist_dependencies[identity]
            if root_kind != "sourceControl" or buttonheist_kind != "fileSystem":
                failures.append(
                    "AccessibilitySnapshotBH dependency must stay root remote exact "
                    "and ButtonHeist local fileSystem"
                )
            if '"exact"' not in root_detail:
                failures.append("root AccessibilitySnapshotBH dependency must use exact version pin")
            continue
        compare_equal(
            f"{identity} dependency",
            root_dependencies[identity],
            buttonheist_dependencies[identity],
            failures,
        )


def check_targets(root: dict[str, Any], buttonheist: dict[str, Any], failures: list[str]) -> None:
    root_targets = target_map(root)
    buttonheist_targets = target_map(buttonheist)
    for target_name in CONTRACT_TARGETS:
        if target_name not in root_targets:
            failures.append(f"root Package.swift is missing contract target {target_name}")
            continue
        if target_name not in buttonheist_targets:
            failures.append(f"ButtonHeist/Package.swift is missing contract target {target_name}")
            continue

        root_summary = target_summary("root", root_targets[target_name])
        buttonheist_summary = target_summary("buttonheist", buttonheist_targets[target_name])
        compare_equal(f"{target_name} target", root_summary, buttonheist_summary, failures)


def check_relationships(label: str, package: dict[str, Any], failures: list[str]) -> None:
    targets = target_map(package)
    for target_name, expected_dependencies in EXPECTED_RELATIONSHIP_EDGES.items():
        target = targets.get(target_name)
        if not target:
            failures.append(f"{label} is missing required target {target_name}")
            continue
        actual_dependencies = tuple(
            sorted(target_dependency_id(dependency) for dependency in target["dependencies"])
        )
        if actual_dependencies != expected_dependencies:
            failures.append(
                f"{label} {target_name} dependency relationship drifted:\n"
                f"  expected: {stable_json(expected_dependencies)}\n"
                f"  actual:   {stable_json(actual_dependencies)}"
            )


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="buttonheist-manifest-drift.") as temp_dir:
        cache_root = Path(temp_dir)
        root = dump_package(ROOT_PACKAGE, cache_root / "root")
        buttonheist = dump_package(BUTTONHEIST_PACKAGE, cache_root / "buttonheist")

    failures: list[str] = []

    compare_equal("Swift tools version", root["toolsVersion"], buttonheist["toolsVersion"], failures)
    compare_equal("public products", product_summary(root), product_summary(buttonheist), failures)
    check_package_dependencies(root, buttonheist, failures)
    check_targets(root, buttonheist, failures)
    check_relationships("root Package.swift", root, failures)
    check_relationships("ButtonHeist/Package.swift", buttonheist, failures)

    if failures:
        print("Package manifest drift detected:", file=sys.stderr)
        for failure in failures:
            print(f"\n- {failure}", file=sys.stderr)
        print(
            "\nAllowed differences: root paths include the ButtonHeist/ prefix; "
            "ButtonHeist/Package.swift adds -warnings-as-errors and local-only test targets; "
            "AccessibilitySnapshotBH is a remote exact pin at the root and a local submodule path "
            "in ButtonHeist/Package.swift.",
            file=sys.stderr,
        )
        raise SystemExit(1)

    print("Package manifest drift guard passed.")
    print(
        "Allowed differences: root paths include the ButtonHeist/ prefix; "
        "ButtonHeist/Package.swift adds -warnings-as-errors and local-only test targets; "
        "AccessibilitySnapshotBH is root remote exact vs nested local path."
    )


if __name__ == "__main__":
    main()
