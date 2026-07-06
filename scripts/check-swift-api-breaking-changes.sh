#!/usr/bin/env bash
# Check public Swift API compatibility against the latest release tag.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

BASELINE_TAG="${BUTTONHEIST_SWIFT_API_BASELINE_TAG:-}"

if [[ -z "$BASELINE_TAG" ]]; then
    git fetch --quiet --force --tags origin +refs/heads/main:refs/remotes/origin/main
    BASELINE_TAG="$(git tag --merged origin/main --sort=-v:refname 'v*' | head -1 || true)"
fi

if [[ -z "$BASELINE_TAG" ]]; then
    echo "No release tag found on origin/main; skipping Swift API breakage check."
    exit 0
fi

echo "Checking Swift API breakage against $BASELINE_TAG"
PUBLIC_PRODUCTS=(
    ThePlans
    TheScore
    ButtonHeistDSL
    TheInsideJob
    ButtonHeistTesting
    ButtonHeist
)
INTENTIONAL_BREAKAGES=(
    "struct ElementMatches has been removed"
    "constructor ForEach.init(_:parameter:content:) has been removed"
    "constructor ForEach.init(_:limit:parameter:_:) has been removed"
    "struct HeistExecutionReportSummaryFacts has been removed"
    "constructor HeistReceiptRecordingMode.init(environmentValue:) has return type change from TheScore.HeistReceiptRecordingMode to TheScore.HeistReceiptRecordingMode?"
    "var HeistActionEvidence.ResultEvidence.dispatchResult has been removed"
    "var HeistActionEvidence.ResultEvidence.expectationResult has been removed"
    "var HeistActionEvidence.ResultEvidence.reportedResult has been removed"
    "var HeistActionEvidence.ResultEvidence.traceResult has been removed"
    "var HeistActionEvidence.ResultEvidence.expectation has been removed"
    "constructor HeistWaitEvidence.init(outcome:actionResult:expectation:baselineSummary:finalSummary:warning:) has been removed"
    "typealias ElementMatches has been removed"
    "struct FailureCode has removed conformance to RawRepresentable"
    "var FailureCode.knownCode has declared type change from ButtonHeist.KnownFailureCode? to ButtonHeist.KnownFailureCode"
    "accessor FailureCode.knownCode.Get() has return type change from ButtonHeist.KnownFailureCode? to ButtonHeist.KnownFailureCode"
    "var FailureCode.kind has declared type change from ButtonHeist.DiagnosticFailureKind? to ButtonHeist.DiagnosticFailureKind"
    "accessor FailureCode.kind.Get() has return type change from ButtonHeist.DiagnosticFailureKind? to ButtonHeist.DiagnosticFailureKind"
    "var FailureCode.phase has declared type change from ButtonHeist.FailurePhase? to ButtonHeist.FailurePhase"
    "accessor FailureCode.phase.Get() has return type change from ButtonHeist.FailurePhase? to ButtonHeist.FailurePhase"
    "var FailureCode.retryable has declared type change from Swift.Bool? to Swift.Bool"
    "accessor FailureCode.retryable.Get() has return type change from Swift.Bool? to Swift.Bool"
    "enumelement KnownFailureCode.tlsCertificateMismatch has been removed"
    "enumelement KnownFailureCode.tlsMissingFingerprint has been removed"
    "constructor FailureCode.init(boundaryRawValue:) has been removed"
    "constructor FailureCode.init(rawValue:) has been removed"
    "typealias FailureCode.RawValue has been removed"
    "var TheFence.CommandArgumentEnvelope.argumentValues has been removed"
    "enumelement FenceResponse.announcements has been added as a new enum case"
    "enumelement TheFence.Command.getAnnouncements has been added as a new enum case"
    "enumelement AccessibilityPredicate.announcement has been added as a new enum case"
    "enumelement AccessibilityPredicateContract.PredicateWireType.announcement has been added as a new enum case"
    "enumelement AccessibilityPredicateContract.announcement has been added as a new enum case"
    "enumelement AccessibilityPredicateExpr.announcement has been added as a new enum case"
    "enumelement ClientMessage.getAnnouncements has been added as a new enum case"
    "enumelement ClientWireMessageType.getAnnouncements has been added as a new enum case"
    "enumelement ServerWireMessageType.announcements has been added as a new enum case"
    "enumelement ServerMessage.announcements has been added as a new enum case"
    "var RuntimeKnobEnvironmentKey.buttonHeistPostScrollLayoutFrames has been removed"
    "var RuntimeKnobEnvironmentKey.buttonHeistTripwirePulseFramesPerSecond has been removed"
    "var RuntimeKnobEnvironmentKey.buttonHeistMaxScrollsPerContainer has been removed"
    "var RuntimeKnobEnvironmentKey.buttonHeistMaxScrollsPerDiscovery has been removed"
    "var RuntimeKnobEnvironmentKey.buttonHeistScrollSubtreeElementBudget has been removed"
    "var RuntimeKnobEnvironmentKey.visibleElementBudget has been removed"
    "var RuntimeKnobEnvironmentKey.buttonHeistVisibleElementBudget has been removed"
    "var RuntimeKnobEnvironmentKey.buttonHeistTotalNodeBudget has been removed"
)

PACKAGE_PUBLIC_PRODUCTS=()
while IFS= read -r product; do
    PACKAGE_PUBLIC_PRODUCTS+=("$product")
done < <(grep -E '^[[:space:]]*[.]library[(]name:[[:space:]]*"[^"]+"' Package.swift \
    | sed -E 's/.*name:[[:space:]]*"([^"]+)".*/\1/')

if [[ "${PUBLIC_PRODUCTS[*]}" != "${PACKAGE_PUBLIC_PRODUCTS[*]}" ]]; then
    echo "Error: Swift API check products do not match Package.swift library products."
    echo "Configured: ${PUBLIC_PRODUCTS[*]}"
    echo "Package.swift: ${PACKAGE_PUBLIC_PRODUCTS[*]}"
    exit 2
fi

MODE="${BUTTONHEIST_SWIFT_API_BREAKAGE_MODE:-strict}"
case "$MODE" in
    strict|report) ;;
    *)
        echo "Error: BUTTONHEIST_SWIFT_API_BREAKAGE_MODE must be 'strict' or 'report', got '$MODE'"
        exit 2
        ;;
esac

OUTPUT_FILE="$(mktemp)"
trap 'rm -f "$OUTPUT_FILE"' EXIT

set +e
swift package diagnose-api-breaking-changes "$BASELINE_TAG" \
    --products "${PUBLIC_PRODUCTS[@]}" 2>&1 | tee "$OUTPUT_FILE"
status=${PIPESTATUS[0]}
set -e

if [[ "$status" -eq 0 ]]; then
    exit 0
fi

if [[ "$MODE" == "report" ]]; then
    echo "Swift API breakage reported in non-blocking mode."
    echo "Run with BUTTONHEIST_SWIFT_API_BREAKAGE_MODE=strict to fail on this diagnostic."
    exit 0
fi

detected_breakages=()
while IFS= read -r breakage; do
    [[ -n "$breakage" ]] || continue
    detected_breakages+=("$breakage")
done < <(grep -F "API breakage:" "$OUTPUT_FILE" | sed 's/^.*API breakage: //')
if [[ "${#detected_breakages[@]}" -eq 0 ]]; then
    exit "$status"
fi

unexpected_breakages=()
for breakage in "${detected_breakages[@]}"; do
    allowed=0
    for intentional in "${INTENTIONAL_BREAKAGES[@]}"; do
        if [[ "$breakage" == "$intentional" ]]; then
            allowed=1
            break
        fi
    done
    if [[ "$allowed" -eq 0 ]]; then
        unexpected_breakages+=("$breakage")
    fi
done

if [[ "${#unexpected_breakages[@]}" -eq 0 ]]; then
    echo "Only intentional Swift API breakage detected:"
    printf '  - %s\n' "${detected_breakages[@]}"
    exit 0
fi

echo "Unexpected Swift API breakage detected:"
printf '  - %s\n' "${unexpected_breakages[@]}"
exit "$status"
