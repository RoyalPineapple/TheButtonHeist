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
INTENTIONAL_BREAKAGES=(
    "enumelement HeistActionCommandType.dismiss has been added as a new enum case"
    "enumelement HeistActionCommandType.magicTap has been added as a new enum case"
    "enumelement HeistActionCommand.dismiss has been added as a new enum case"
    "enumelement HeistActionCommand.magicTap has been added as a new enum case"
    "enumelement ActionMethod.dismiss has been added as a new enum case"
    "enumelement ActionMethod.magicTap has been added as a new enum case"
    "enumelement RuntimeActionMessage.dismiss has been added as a new enum case"
    "enumelement RuntimeActionMessage.magicTap has been added as a new enum case"
    "enumelement RuntimeActionType.dismiss has been added as a new enum case"
    "enumelement RuntimeActionType.magicTap has been added as a new enum case"
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
    "var FailureDetails.code has declared type change from ButtonHeist.FailureCode to ButtonHeist.KnownFailureCode"
    "accessor FailureDetails.code.Get() has return type change from ButtonHeist.FailureCode to ButtonHeist.KnownFailureCode"
    "var DiagnosticFailure.failureCode has declared type change from ButtonHeist.FailureCode to ButtonHeist.KnownFailureCode"
    "accessor DiagnosticFailure.failureCode.Get() has return type change from ButtonHeist.FailureCode to ButtonHeist.KnownFailureCode"
    "var ConnectionFailure.failureCode has declared type change from ButtonHeist.FailureCode to ButtonHeist.KnownFailureCode"
    "accessor ConnectionFailure.failureCode.Get() has return type change from ButtonHeist.FailureCode to ButtonHeist.KnownFailureCode"
    "constructor FailureDetails.init(code:phase:retryable:hint:) has been removed"
    "constructor ConnectionFailure.init(message:failureCode:phase:retryable:hint:) has been removed"
    "enumelement KnownFailureCode.tlsCertificateMismatch has been removed"
    "enumelement KnownFailureCode.tlsMissingFingerprint has been removed"
    "struct FailureCode has been removed"
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

PUBLIC_PRODUCTS=()
while IFS= read -r product; do
    PUBLIC_PRODUCTS+=("$product")
done < <(grep -E '^[[:space:]]*[.]library[(]name:[[:space:]]*"[^"]+"' Package.swift \
    | sed -E 's/.*name:[[:space:]]*"([^"]+)".*/\1/')

if [[ "${#PUBLIC_PRODUCTS[@]}" -eq 0 ]]; then
    echo "Error: no Swift library products found in Package.swift."
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
