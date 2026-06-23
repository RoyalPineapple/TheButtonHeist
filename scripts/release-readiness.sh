#!/usr/bin/env bash
# Local release-readiness preflight that composes the smallest release contract checks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

run_step() {
    local label="$1"
    shift
    echo "==> $label"
    "$@"
    echo ""
}

check_generated_project() {
    "$SCRIPT_DIR/generate-project.sh"
    git diff --exit-code -- '*.pbxproj' '*.xcworkspacedata' || {
        echo "Error: generated Xcode project is out of date. Run scripts/generate-project.sh and commit the changes." >&2
        return 1
    }
}

run_step "Release contract and parser pin" "$SCRIPT_DIR/validate-release-contract.sh"
run_step "Package manifest drift guard" "$SCRIPT_DIR/check-package-manifest-drift.sh"
run_step "Generated project check" check_generated_project
run_step "External ButtonHeist import fixture" "$SCRIPT_DIR/check-buttonheist-import-contract.sh"
run_step "Build heist-plan" swift build --package-path ButtonHeist --product heist-plan
run_step "heist-plan compile smoke" "$SCRIPT_DIR/test-heist-plan-compile.sh"
run_step "Installed artifact smoke when available" "$SCRIPT_DIR/installed-artifact-smoke.sh"

echo "Release readiness checks passed."
