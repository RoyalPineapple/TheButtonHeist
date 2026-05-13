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
while IFS= read -r -d '' path; do
    pbxproj_paths+=("$path")
done < <(
    find . \
        -name 'project.pbxproj' \
        -not -path './Tuist/.build/*' \
        -not -path './submodules/*' \
        -not -path './.context/*' \
        -print0
)

if [[ ${#pbxproj_paths[@]} -eq 0 ]]; then
    pbxproj_status=0
else
    set +e
    python3 scripts/clean-pbxproj.py "$@" "${pbxproj_paths[@]}"
    pbxproj_status=$?
    set -e
fi

if [[ "$check_only" == false ]]; then
    # Tuist also emits workspace-level schemes that this repo intentionally does
    # not track. Remove only the known generated names, and only when they are
    # not already in the git index.
    for scheme in ButtonHeist-Workspace.xcscheme "Generate Project.xcscheme"; do
        scheme_path="ButtonHeist.xcworkspace/xcshareddata/xcschemes/$scheme"
        if [[ -f "$scheme_path" ]] && ! git ls-files --error-unmatch "$scheme_path" >/dev/null 2>&1; then
            rm -f "$scheme_path"
        fi
    done

    if [[ -d ButtonHeist.xcworkspace/xcshareddata/xcschemes ]]; then
        rmdir ButtonHeist.xcworkspace/xcshareddata/xcschemes 2>/dev/null || true
    fi
fi

exit "$pbxproj_status"
