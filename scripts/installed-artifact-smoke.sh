#!/usr/bin/env bash
# Smoke test installed or release-staged Button Heist artifacts.
#
# Default local behavior:
#   - If Button Heist is not installed, print SKIP and exit 0.
#   - If an install is found, fail on incomplete or broken artifacts.
#
# CI/release behavior:
#   - Pass --require-installed and either --prefix or release archives.

set -euo pipefail

PREFIX="${BUTTONHEIST_INSTALL_PREFIX:-}"
CLI_ARCHIVE="${BUTTONHEIST_CLI_ARCHIVE:-}"
MCP_ARCHIVE="${BUTTONHEIST_MCP_ARCHIVE:-}"
EXPECTED_VERSION="${BUTTONHEIST_EXPECTED_VERSION:-}"
SUPPORTED_THEPLANS_TRIPLE="arm64-apple-macosx"
THEPLANS_TRIPLE="${BUTTONHEIST_THEPLANS_TRIPLE:-$SUPPORTED_THEPLANS_TRIPLE}"
COMMAND_TIMEOUT="${BUTTONHEIST_INSTALLED_SMOKE_TIMEOUT:-60}"
MCP_TIMEOUT="${BUTTONHEIST_MCP_SMOKE_TIMEOUT:-5}"
REQUIRE_INSTALLED=false
EXPLICIT_PREFIX=false

TMP_DIR=""
RUN_TMP=""
PREFIX_CANDIDATES=()

usage() {
    cat <<'EOF'
Usage: scripts/installed-artifact-smoke.sh [options]

Options:
  --prefix DIR             Installed prefix containing bin/ and lib/.
  --cli-archive PATH       Release CLI archive to stage before smoking.
  --mcp-archive PATH       Release MCP archive to stage before smoking.
  --expected-version VER   Expected buttonheist --version output.
  --theplans-triple TRIPLE Installed ThePlans artifact triple. Defaults to arm64-apple-macosx.
                         Homebrew distribution is Apple Silicon / arm64 only.
  --timeout SECONDS        Timeout for CLI/heist-plan invocations. Defaults to 60.
  --mcp-timeout SECONDS    Timeout for buttonheist-mcp launch smoke. Defaults to 5.
  --require-installed      Fail instead of skipping when no install is found.
  -h, --help               Show this help.

Without --prefix or archives, the script looks for a Homebrew install first,
then falls back to Button Heist tools on PATH.
EOF
}

log() {
    printf '==> %s\n' "$*"
}

ok() {
    printf '[ok] %s\n' "$*"
}

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

skip() {
    printf 'SKIP: %s\n' "$*" >&2
    exit 0
}

cleanup() {
    if [[ -n "$RUN_TMP" ]]; then
        rm -rf "$RUN_TMP"
    fi
    if [[ -n "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)
            PREFIX="${2:-}"
            [[ -n "$PREFIX" ]] || fail "--prefix requires a value"
            EXPLICIT_PREFIX=true
            shift 2
            ;;
        --cli-archive)
            CLI_ARCHIVE="${2:-}"
            [[ -n "$CLI_ARCHIVE" ]] || fail "--cli-archive requires a value"
            shift 2
            ;;
        --mcp-archive)
            MCP_ARCHIVE="${2:-}"
            [[ -n "$MCP_ARCHIVE" ]] || fail "--mcp-archive requires a value"
            shift 2
            ;;
        --expected-version)
            EXPECTED_VERSION="${2:-}"
            [[ -n "$EXPECTED_VERSION" ]] || fail "--expected-version requires a value"
            shift 2
            ;;
        --theplans-triple)
            THEPLANS_TRIPLE="${2:-}"
            [[ -n "$THEPLANS_TRIPLE" ]] || fail "--theplans-triple requires a value"
            shift 2
            ;;
        --timeout)
            COMMAND_TIMEOUT="${2:-}"
            [[ -n "$COMMAND_TIMEOUT" ]] || fail "--timeout requires a value"
            shift 2
            ;;
        --mcp-timeout)
            MCP_TIMEOUT="${2:-}"
            [[ -n "$MCP_TIMEOUT" ]] || fail "--mcp-timeout requires a value"
            shift 2
            ;;
        --require-installed)
            REQUIRE_INSTALLED=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown option: $1"
            ;;
    esac
done

if [[ "$THEPLANS_TRIPLE" != "$SUPPORTED_THEPLANS_TRIPLE" ]]; then
    fail "installed Button Heist artifacts are arm64-only; unsupported ThePlans triple: $THEPLANS_TRIPLE"
fi

case "$COMMAND_TIMEOUT" in
    ''|*[!0-9.]*)
        fail "--timeout must be numeric"
        ;;
esac
case "$MCP_TIMEOUT" in
    ''|*[!0-9.]*)
        fail "--mcp-timeout must be numeric"
        ;;
esac

require_tool() {
    command -v "$1" >/dev/null 2>&1 || fail "missing required tool: $1"
}

resolve_path() {
    local path="$1"
    python3 - "$path" <<'PY' 2>/dev/null || printf '%s\n' "$path"
import pathlib
import sys

print(pathlib.Path(sys.argv[1]).resolve())
PY
}

append_unique_prefix() {
    local candidate="$1"
    [[ -n "$candidate" ]] || return 0
    local resolved
    resolved="$(cd "$candidate" 2>/dev/null && pwd -P)" || return 0
    local existing
    if (( ${#PREFIX_CANDIDATES[@]} > 0 )); then
        for existing in "${PREFIX_CANDIDATES[@]}"; do
            [[ "$existing" != "$resolved" ]] || return 0
        done
    fi
    PREFIX_CANDIDATES+=("$resolved")
}

find_installed_prefix() {
    local tool path resolved
    PREFIX_CANDIDATES=()

    if command -v brew >/dev/null 2>&1; then
        append_unique_prefix "$(brew --prefix buttonheist 2>/dev/null || true)"
    fi

    for tool in buttonheist heist-plan buttonheist-mcp; do
        path="$(command -v "$tool" 2>/dev/null || true)"
        [[ -n "$path" ]] || continue
        append_unique_prefix "$(dirname "$path")/.."
        resolved="$(resolve_path "$path")"
        append_unique_prefix "$(dirname "$resolved")/.."
    done

    if (( ${#PREFIX_CANDIDATES[@]} > 0 )); then
        for candidate in "${PREFIX_CANDIDATES[@]}"; do
            if [[ -x "$candidate/bin/buttonheist" \
                || -x "$candidate/bin/heist-plan" \
                || -x "$candidate/bin/buttonheist-mcp" ]]; then
                printf '%s\n' "$candidate"
                return 0
            fi
        done
    fi

    return 1
}

stage_release_archives() {
    [[ -n "$CLI_ARCHIVE" && -n "$MCP_ARCHIVE" ]] \
        || fail "--cli-archive and --mcp-archive must be provided together"
    [[ -f "$CLI_ARCHIVE" ]] || fail "CLI archive not found: $CLI_ARCHIVE"
    [[ -f "$MCP_ARCHIVE" ]] || fail "MCP archive not found: $MCP_ARCHIVE"

    TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/buttonheist-installed-smoke.XXXXXX")"
    local cli_unpack="$TMP_DIR/cli"
    local mcp_unpack="$TMP_DIR/mcp"
    PREFIX="$TMP_DIR/install"

    mkdir -p "$cli_unpack" "$mcp_unpack" "$PREFIX/bin" "$PREFIX/lib"
    tar -xzf "$CLI_ARCHIVE" -C "$cli_unpack"
    tar -xzf "$MCP_ARCHIVE" -C "$mcp_unpack"

    [[ -x "$cli_unpack/buttonheist" ]] || fail "$CLI_ARCHIVE is missing executable buttonheist"
    [[ -x "$cli_unpack/heist-plan" ]] || fail "$CLI_ARCHIVE is missing executable heist-plan"
    [[ -d "$cli_unpack/ThePlans" ]] || fail "$CLI_ARCHIVE is missing ThePlans compiler artifacts"
    [[ -x "$mcp_unpack/buttonheist-mcp" ]] || fail "$MCP_ARCHIVE is missing executable buttonheist-mcp"

    cp "$cli_unpack/buttonheist" "$PREFIX/bin/"
    cp "$cli_unpack/heist-plan" "$PREFIX/bin/"
    cp "$mcp_unpack/buttonheist-mcp" "$PREFIX/bin/"
    chmod +x "$PREFIX/bin/buttonheist" "$PREFIX/bin/heist-plan" "$PREFIX/bin/buttonheist-mcp"
    if [[ -e "$cli_unpack/ButtonHeistFrameworks" ]]; then
        cp -R "$cli_unpack/ButtonHeistFrameworks" "$PREFIX/bin/"
    fi
    cp -R "$cli_unpack/ThePlans" "$PREFIX/lib/"
}

run_with_timeout() {
    local timeout="$1"
    shift
    python3 - "$timeout" "$@" <<'PY'
import shlex
import subprocess
import sys

timeout = float(sys.argv[1])
cmd = sys.argv[2:]
try:
    completed = subprocess.run(
        cmd,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
except FileNotFoundError:
    print(f"command not found: {cmd[0]}", file=sys.stderr)
    sys.exit(127)
except subprocess.TimeoutExpired as error:
    if error.stdout:
        sys.stdout.write(error.stdout)
    if error.stderr:
        sys.stderr.write(error.stderr)
    rendered = " ".join(shlex.quote(part) for part in cmd)
    print(f"timed out after {timeout:g}s: {rendered}", file=sys.stderr)
    sys.exit(124)

sys.stdout.write(completed.stdout)
sys.stderr.write(completed.stderr)
sys.exit(completed.returncode)
PY
}

run_checked() {
    local label="$1"
    local timeout="$2"
    shift 2

    local output
    if output="$(run_with_timeout "$timeout" "$@" 2>&1)"; then
        ok "$label"
    else
        local status=$?
        printf '%s\n' "$output" >&2
        fail "$label failed with exit status $status"
    fi
}

require_file() {
    local path="$1"
    [[ -f "$path" ]] || fail "missing installed artifact: $path"
}

require_dir() {
    local path="$1"
    [[ -d "$path" ]] || fail "missing installed artifact directory: $path"
}

if [[ -n "$CLI_ARCHIVE" || -n "$MCP_ARCHIVE" ]]; then
    require_tool tar
    require_tool python3
    stage_release_archives
    EXPLICIT_PREFIX=true
elif [[ -z "$PREFIX" ]]; then
    require_tool python3
    if ! PREFIX="$(find_installed_prefix)"; then
        if [[ "$REQUIRE_INSTALLED" == true ]]; then
            fail "Button Heist install not found; pass --prefix or --cli-archive/--mcp-archive"
        fi
        skip "Button Heist tools are not installed; pass --require-installed to fail instead"
    fi
else
    require_tool python3
    EXPLICIT_PREFIX=true
fi

PREFIX="$(cd "$PREFIX" 2>/dev/null && pwd -P)" \
    || fail "install prefix does not exist: $PREFIX"

BUTTONHEIST="$PREFIX/bin/buttonheist"
HEIST_PLAN="$PREFIX/bin/heist-plan"
BUTTONHEIST_MCP="$PREFIX/bin/buttonheist-mcp"
THEPLANS_BUILD_DIR="$PREFIX/lib/ThePlans/$THEPLANS_TRIPLE/release"

missing=()
[[ -x "$BUTTONHEIST" ]] || missing+=("$BUTTONHEIST")
[[ -x "$HEIST_PLAN" ]] || missing+=("$HEIST_PLAN")
[[ -x "$BUTTONHEIST_MCP" ]] || missing+=("$BUTTONHEIST_MCP")

if [[ "${#missing[@]}" -gt 0 ]]; then
    if [[ "$REQUIRE_INSTALLED" == true || "$EXPLICIT_PREFIX" == true ]]; then
        printf 'Missing installed tools under %s:\n' "$PREFIX" >&2
        printf '  %s\n' "${missing[@]}" >&2
        exit 1
    fi
    skip "Button Heist installed tools are incomplete under $PREFIX"
fi

log "Smoking installed artifacts under $PREFIX"

RUN_TMP="$(mktemp -d "${TMPDIR:-/tmp}/buttonheist-installed-smoke-run.XXXXXX")"
SMOKE_HOME="$RUN_TMP/home"
PLAN_TMP="$RUN_TMP/plan"
mkdir -p "$SMOKE_HOME" "$PLAN_TMP"

version_output="$(run_with_timeout 10 "$BUTTONHEIST" --version 2>&1)" \
    || fail "buttonheist --version failed: $version_output"
version="$(printf '%s\n' "$version_output" | sed -n '1p' | tr -d '[:space:]')"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || fail "buttonheist --version did not print MAJOR.MINOR.PATCH: $version_output"
if [[ -n "$EXPECTED_VERSION" && "$version" != "$EXPECTED_VERSION" ]]; then
    fail "buttonheist --version printed $version, expected $EXPECTED_VERSION"
fi
ok "buttonheist --version ($version)"

run_checked "buttonheist-mcp launch/help smoke" "$MCP_TIMEOUT" \
    env HOME="$SMOKE_HOME" CFFIXED_USER_HOME="$SMOKE_HOME" \
        BUTTONHEIST_STORAGE_DIR="$RUN_TMP/storage" "$BUTTONHEIST_MCP" --help

require_dir "$THEPLANS_BUILD_DIR"
require_dir "$THEPLANS_BUILD_DIR/Modules"
require_dir "$THEPLANS_BUILD_DIR/ThePlans.build"
require_file "$THEPLANS_BUILD_DIR/Modules/ThePlans.swiftinterface"
require_file "$THEPLANS_BUILD_DIR/Modules/ThePlans.private.swiftinterface"
require_file "$THEPLANS_BUILD_DIR/ThePlans.build/ThePlans.swiftinterface"
require_file "$THEPLANS_BUILD_DIR/ThePlans.build/ThePlans.private.swiftinterface"
require_file "$THEPLANS_BUILD_DIR/description.json"
if [[ -e "$THEPLANS_BUILD_DIR/Modules/ThePlans.swiftmodule" ]]; then
    fail "installed ThePlans Modules directory must not rely on binary ThePlans.swiftmodule: $THEPLANS_BUILD_DIR/Modules/ThePlans.swiftmodule"
fi
if ! find "$THEPLANS_BUILD_DIR/ThePlans.build" -type f -name '*.swift.o' -print -quit | grep -q .; then
    fail "missing ThePlans Swift object files under $THEPLANS_BUILD_DIR/ThePlans.build"
fi
ok "installed ThePlans swiftinterface and compiler artifacts"

SOURCE="$PLAN_TMP/Plan.swift"
OUTPUT="$PLAN_TMP/installed-smoke.heist"

cat > "$SOURCE" <<'SWIFT'
import ThePlans

func makeHeist() throws -> HeistPlan {
    try HeistPlan("installedArtifactSmoke") {
        Warn("compiled from installed artifacts")
    }
}
SWIFT

compile_output="$(
    cd "$PLAN_TMP"
    run_with_timeout "$COMMAND_TIMEOUT" \
        env -u HEIST_THEPLANS_BUILD_DIR HEIST_SOURCE_COMPILER_TRACE=1 \
        "$HEIST_PLAN" compile "$SOURCE" --entry makeHeist --output "$OUTPUT" 2>&1
)" || {
    status=$?
    printf '%s\n' "$compile_output" >&2
    fail "heist-plan compile failed with exit status $status"
}

resolved_theplans_build_dir="$(resolve_path "$THEPLANS_BUILD_DIR")"
theplans_trace_found=false
for trace_path in \
    "$THEPLANS_BUILD_DIR" \
    "$resolved_theplans_build_dir" \
    "${THEPLANS_BUILD_DIR#/private}" \
    "${resolved_theplans_build_dir#/private}"; do
    if [[ "$compile_output" == *"using built ThePlans artifacts at $trace_path"* ]]; then
        theplans_trace_found=true
        break
    fi
done
if [[ "$theplans_trace_found" != true ]]; then
    printf '%s\n' "$compile_output" >&2
    fail "heist-plan compile did not report using installed ThePlans artifacts at $THEPLANS_BUILD_DIR"
fi
[[ -d "$OUTPUT" ]] || fail "heist-plan compile did not create .heist package: $OUTPUT"
require_file "$OUTPUT/manifest.json"
require_file "$OUTPUT/plan.json"
ok "heist-plan compile"

run_checked "heist-plan validate" "$COMMAND_TIMEOUT" "$HEIST_PLAN" validate "$OUTPUT"

log "Installed artifact smoke passed"
