#!/usr/bin/env bash
# Cleans generated Xcode project files after Tuist runs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

check_only=false
for arg in "$@"; do
    if [[ "$arg" == "--check" ]]; then
        check_only=true
        break
    fi
done

pbxproj_paths=()
for path in \
    ButtonHeist.xcodeproj/project.pbxproj \
    TestApp/TestApp.xcodeproj/project.pbxproj; do
    [[ -f "$path" ]] && pbxproj_paths+=("$path")
done

if [[ ${#pbxproj_paths[@]} -eq 0 ]]; then
    pbxproj_status=0
else
    set +e
    python3 scripts/clean-pbxproj.py "$@" "${pbxproj_paths[@]}"
    pbxproj_status=$?
    set -e
fi

if [[ "$check_only" == false ]]; then
    # Tuist also emits workspace-level schemes that this repo does not use.
    for scheme in ButtonHeist-Workspace.xcscheme "Generate Project.xcscheme"; do
        scheme_path="ButtonHeist.xcworkspace/xcshareddata/xcschemes/$scheme"
        rm -f "$scheme_path"
    done

    if [[ -d ButtonHeist.xcworkspace/xcshareddata/xcschemes ]]; then
        rmdir ButtonHeist.xcworkspace/xcshareddata/xcschemes 2>/dev/null || true
    fi
fi

exit "$pbxproj_status"
