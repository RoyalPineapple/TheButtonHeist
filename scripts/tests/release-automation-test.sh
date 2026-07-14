#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURE_ROOT="$(mktemp -d)"
FAKE_BIN="$FIXTURE_ROOT/bin"
GH_LOG="$FIXTURE_ROOT/gh.log"

cd "$REPO_ROOT"

trap 'rm -rf "$FIXTURE_ROOT"' EXIT
mkdir -p "$FAKE_BIN"

# shellcheck source=scripts/release-contract.sh
source "$REPO_ROOT/scripts/release-contract.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

canonical_version=$(buttonheist_code_version)
release_version=$(tr -d '[:space:]' < "$REPO_ROOT/$BUTTONHEIST_RELEASE_VERSION_FILE")
[[ "$canonical_version" == "$release_version" ]] \
    || fail "canonical code version ($canonical_version) disagrees with release mirror ($release_version)"

cat > "$FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_GH_LOG"

jq_filter=""
while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--jq" ]]; then
        jq_filter="${2:-}"
        break
    fi
    shift
done

if [[ -z "$jq_filter" ]]; then
    echo "fixture CI run"
    exit 0
fi

case "${FAKE_GH_RESULT:-success}:$jq_filter" in
    success:*'conclusion == "success"'*) echo 1 ;;
    success:*) echo 0 ;;
    failure:*'conclusion == "success"'*) echo 0 ;;
    failure:*'status != "completed"'*) echo 0 ;;
    failure:*'conclusion != "success"'*) echo 1 ;;
    failure:*) echo 1 ;;
    *) echo 0 ;;
esac
EOF
chmod +x "$FAKE_BIN/gh"

PATH="$FAKE_BIN:$PATH" \
FAKE_GH_LOG="$GH_LOG" \
FAKE_GH_RESULT=success \
    "$REPO_ROOT/scripts/require-successful-ci-for-commit.sh" \
    --repo RoyalPineapple/TheButtonHeist \
    0123456789abcdef \
    fixture

grep -Fq -- '--branch main --commit 0123456789abcdef' "$GH_LOG" \
    || fail "exact-commit CI guard did not constrain branch and commit"

set +e
output=$(
    PATH="$FAKE_BIN:$PATH" \
    FAKE_GH_LOG="$GH_LOG" \
    FAKE_GH_RESULT=failure \
        "$REPO_ROOT/scripts/require-successful-ci-for-commit.sh" \
        --repo RoyalPineapple/TheButtonHeist \
        fedcba9876543210 \
        fixture 2>&1
)
status=$?
set -e
[[ "$status" -eq 1 ]] || fail "exact-commit CI guard accepted a failed push run: $output"
[[ "$output" == *"Main-branch CI failed"* ]] || fail "failed CI result lacked a useful diagnostic: $output"

echo "PASS: release automation shares canonical version and exact-commit CI ownership"
