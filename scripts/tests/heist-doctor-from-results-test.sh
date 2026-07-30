#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_ROOT="$(mktemp -d)"
DOCTOR="$FIXTURE_ROOT/heist-doctor"
CAPTURE="$FIXTURE_ROOT/arguments"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

cat > "$DOCTOR" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$DOCTOR_ARGUMENT_CAPTURE"
EOF
chmod +x "$DOCTOR"

DOCTOR_ARGUMENT_CAPTURE="$CAPTURE" \
    "$REPO_ROOT/scripts/heist-doctor-from-results.sh" \
    --last-pass-dir "$FIXTURE_ROOT/main" \
    --new-fail-dir "$FIXTURE_ROOT/pr" \
    --doctor "$DOCTOR" \
    --format json \
    --step-path '$.body[0]' \
    --no-build

EXPECTED="$FIXTURE_ROOT/expected"
printf '%s\n' \
    --last-pass-dir "$FIXTURE_ROOT/main" \
    --new-fail-dir "$FIXTURE_ROOT/pr" \
    --format json \
    --step-path '$.body[0]' > "$EXPECTED"

cmp "$EXPECTED" "$CAPTURE"
