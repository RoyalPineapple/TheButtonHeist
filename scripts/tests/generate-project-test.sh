#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURE_ROOT="$(mktemp -d)"
TUIST_LOG="$FIXTURE_ROOT/tuist.log"
CLEAN_LOG="$FIXTURE_ROOT/clean.log"

trap 'rm -rf "$FIXTURE_ROOT"' EXIT

cat > "$FIXTURE_ROOT/tuist" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_TUIST_LOG"
if [[ "${1:-}" == "generate" ]]; then
    exit "${FAKE_GENERATE_STATUS:-0}"
fi
EOF
cat > "$FIXTURE_ROOT/clean" <<'EOF'
#!/usr/bin/env bash
echo clean >> "$FAKE_CLEAN_LOG"
EOF
chmod +x "$FIXTURE_ROOT/tuist" "$FIXTURE_ROOT/clean"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

run_generator() {
    FAKE_TUIST_LOG="$TUIST_LOG" \
    FAKE_CLEAN_LOG="$CLEAN_LOG" \
    BUTTONHEIST_TUIST_BIN="$FIXTURE_ROOT/tuist" \
    BUTTONHEIST_GENERATED_PROJECT_CLEANER="$FIXTURE_ROOT/clean" \
        "$REPO_ROOT/scripts/generate-project.sh" "$@"
}

run_generator --skip-install --no-binary-cache
[[ "$(cat "$TUIST_LOG")" == "generate --no-open --no-binary-cache" ]] \
    || fail "skip-install generation arguments drifted: $(cat "$TUIST_LOG")"
[[ "$(cat "$CLEAN_LOG")" == "clean" ]] || fail "generation did not invoke the canonical cleaner"

: > "$TUIST_LOG"
: > "$CLEAN_LOG"
run_generator
[[ "$(sed -n '1p' "$TUIST_LOG")" == "install" ]] || fail "default generation skipped install"
[[ "$(sed -n '2p' "$TUIST_LOG")" == "generate --no-open" ]] || fail "default generation arguments drifted"

: > "$TUIST_LOG"
: > "$CLEAN_LOG"
set +e
FAKE_GENERATE_STATUS=9 run_generator --skip-install
status=$?
set -e
[[ "$status" -eq 9 ]] || fail "generation did not preserve Tuist failure status"
[[ "$(cat "$CLEAN_LOG")" == "clean" ]] || fail "failed generation did not invoke the canonical cleaner"

echo "PASS: canonical project generation owns install, generation, and cleanup"
