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
    "enum HeistStepAdmissionCandidate has been changed to a struct"
    "enumelement HeistStepAdmissionCandidate.action has been removed"
    "enumelement HeistStepAdmissionCandidate.wait has been removed"
    "enumelement HeistStepAdmissionCandidate.conditional has been removed"
    "enumelement HeistStepAdmissionCandidate.forEachElement has been removed"
    "enumelement HeistStepAdmissionCandidate.forEachString has been removed"
    "enumelement HeistStepAdmissionCandidate.repeatUntil has been removed"
    "enumelement HeistStepAdmissionCandidate.warn has been removed"
    "enumelement HeistStepAdmissionCandidate.fail has been removed"
    "enumelement HeistStepAdmissionCandidate.heist has been removed"
    "enumelement HeistStepAdmissionCandidate.invoke has been removed"
    "enumelement AccessibilityNotificationKind.layoutChanged has been added as a new enum case"
    "enumelement AccessibilityNotificationKind.elementChanged has been removed"
    "enumelement AccessibilityNotificationKind.valueChanged has been added as a new enum case"
    "enumelement AccessibilityNotificationKind.unknown has been added as a new enum case"
    "constructor AccessibilityTrace.ElementsChanged.init(elementCount:edits:captureEdge:interactionDigest:transient:) has been removed"
    "constructor AccessibilityTrace.ScreenChanged.init(elementCount:captureEdge:newInterface:interactionDigest:transient:) has been removed"
    "enumelement ElementAction.typeText has been added as a new enum case"
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
    "func TraitSetMatch.include(_:) has been removed"
    "func TraitSetMatch.exclude(_:) has been removed"
    "func TraitSetMatch.match(include:exclude:) has been removed"
    "func ActionSetMatch.include(_:) has been removed"
    "func ActionSetMatch.exclude(_:) has been removed"
    "func ActionSetMatch.match(include:exclude:) has been removed"
    "func ElementFrameMatch.exact(x:y:width:height:) has been removed"
    "func ElementFrameMatch.match(x:y:width:height:) has been removed"
    "func ElementPointMatch.exact(x:y:) has been removed"
    "func ElementPointMatch.match(x:y:) has been removed"
    "func CustomContentMatch.match(label:value:isImportant:) has been removed"
    "func RotorSetMatch.include(_:) has been removed"
    "func RotorSetMatch.exclude(_:) has been removed"
    "func RotorSetMatch.match(include:exclude:) has been removed"
    "var HeistActionEvidence.ResultEvidence.dispatchResult has been removed"
    "var HeistActionEvidence.ResultEvidence.expectationResult has been removed"
    "var HeistActionEvidence.ResultEvidence.reportedResult has been removed"
    "var HeistActionEvidence.ResultEvidence.traceResult has been removed"
    "var HeistActionEvidence.ResultEvidence.expectation has been removed"
    "var HeistActionCommand.runtimeActionType has been removed"
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
    "enumelement FenceError.ambiguousDeviceTarget has been added as a new enum case"
    "enum FenceCommandReference has been removed"
    "enumelement FenceResponse.announcements has been added as a new enum case"
    "enumelement TheFence.Command.getAnnouncements has been added as a new enum case"
    "enumelement AccessibilityPredicate.announcement has been added as a new enum case"
    "enumelement AccessibilityPredicateContract.PredicateWireType.announcement has been added as a new enum case"
    "enumelement AccessibilityPredicateContract.announcement has been added as a new enum case"
    "enumelement AccessibilityPredicateExpr.announcement has been added as a new enum case"
    "enumelement AccessibilityPredicate.State.existsContainer has been added as a new enum case"
    "enumelement AccessibilityPredicate.State.missingContainer has been added as a new enum case"
    "enumelement AccessibilityPredicateContract.State.container has been added as a new enum case"
    "enumelement ElementTarget.SchemaFieldKind.containerPredicate has been added as a new enum case"
    "enumelement ElementTarget.SchemaFieldKind.nestedElementTarget has been added as a new enum case"
    "enumelement ElementTarget.CodingKeys.container has been added as a new enum case"
    "enumelement ElementTarget.CodingKeys.target has been added as a new enum case"
    "enumelement ElementTarget.within has been added as a new enum case"
    "enumelement ElementTargetExpr.within has been added as a new enum case"
    "enumelement StatePredicateExpr.existsContainer has been added as a new enum case"
    "enumelement StatePredicateExpr.missingContainer has been added as a new enum case"
    "var InterfaceDiscoveryOmittedContainer.type has declared type change from TheScore.ContainerTypeName to ThePlans.AccessibilityContainerKind"
    "accessor InterfaceDiscoveryOmittedContainer.type.Get() has return type change from TheScore.ContainerTypeName to ThePlans.AccessibilityContainerKind"
    "constructor InterfaceDiscoveryOmittedContainer.init(containerName:type:reasonCodes:scrollAxis:viewportWidth:viewportHeight:contentWidth:contentHeight:) has parameter 1 type change from TheScore.ContainerTypeName to ThePlans.AccessibilityContainerKind"
    "enumelement SubtreeSelector.container has declared type change from (TheScore.SubtreeSelector.Type) -> (TheScore.ContainerMatcher, Swift.Int?) -> TheScore.SubtreeSelector to (TheScore.SubtreeSelector.Type) -> (ThePlans.ContainerPredicate, Swift.Int?) -> TheScore.SubtreeSelector"
    "enum ContainerTypeName has been removed"
    "struct ContainerMatcher has been removed"
    "var FenceParameters.containerType has declared type change from ButtonHeist.FenceParameter<TheScore.ContainerTypeName> to ButtonHeist.FenceParameter<ThePlans.AccessibilityContainerKind>"
    "accessor FenceParameters.containerType.Get() has return type change from ButtonHeist.FenceParameter<TheScore.ContainerTypeName> to ButtonHeist.FenceParameter<ThePlans.AccessibilityContainerKind>"
    "enumelement ClientMessage.getAnnouncements has been added as a new enum case"
    "enumelement ClientWireMessageType.getAnnouncements has been added as a new enum case"
    "enumelement ServerWireMessageType.announcements has been added as a new enum case"
    "enumelement ServerMessage.announcements has been added as a new enum case"
    "var AccessibilityNotificationEvidence.code has been removed"
    "var AccessibilityNotificationEvidence.name has been removed"
    "constructor AccessibilityNotificationEvidence.init(sequence:code:name:timestamp:notificationData:associatedElement:) has been removed"
    "var AccessibilityTrace.Transition.screenChangeReason has been removed"
    "constructor AccessibilityTrace.Transition.init(screenChangeReason:transient:accessibilityNotifications:) has been removed"
    "var CapturedAnnouncement.notificationCode has been removed"
    "var CapturedAnnouncement.notificationName has been removed"
    "constructor CapturedAnnouncement.init(sequence:text:timestamp:notificationCode:notificationName:associatedElement:) has been removed"
    "var RuntimeKnobEnvironmentKey.buttonHeistPostScrollLayoutFrames has been removed"
    "var RuntimeKnobEnvironmentKey.buttonHeistTripwirePulseFramesPerSecond has been removed"
    "var RuntimeKnobEnvironmentKey.buttonHeistMaxScrollsPerContainer has been removed"
    "var RuntimeKnobEnvironmentKey.buttonHeistMaxScrollsPerDiscovery has been removed"
    "var RuntimeKnobEnvironmentKey.buttonHeistScrollSubtreeElementBudget has been removed"
    "var RuntimeKnobEnvironmentKey.visibleElementBudget has been removed"
    "var RuntimeKnobEnvironmentKey.buttonHeistVisibleElementBudget has been removed"
    "var RuntimeKnobEnvironmentKey.buttonHeistTotalNodeBudget has been removed"
    "constructor DiscoveredDevice.init(id:name:endpoint:simulatorUDID:installationId:displayDeviceName:instanceId:connectionType:) has parameter 2 type change from Network.NWEndpoint to ButtonHeist.DiscoveredDeviceEndpoint"
    "enumelement ClientMessage.requestScreen has declared type change from (TheScore.ClientMessage.Type) -> TheScore.ClientMessage to (TheScore.ClientMessage.Type) -> (TheScore.ScreenRequestPayload) -> TheScore.ClientMessage"
    "constructor HeistForEachStringEvidence.init(parameter:count:iterationCount:iterationOrdinal:value:failureReason:) has parameter 3 type change from Swift.Int? to Swift.Int"
    "constructor HeistForEachStringEvidence.init(parameter:count:iterationCount:iterationOrdinal:value:failureReason:) has removed default argument from parameter 3"
    "constructor HeistForEachStringEvidence.init(parameter:count:iterationCount:iterationOrdinal:value:failureReason:) has parameter 4 type change from Swift.String? to Swift.String"
    "constructor HeistForEachStringEvidence.init(parameter:count:iterationCount:iterationOrdinal:value:failureReason:) has removed default argument from parameter 4"
    "constructor HeistForEachElementEvidence.init(parameter:matching:limit:matchedCount:iterationCount:iterationOrdinal:targetOrdinal:targetSummary:failureReason:) has parameter 5 type change from Swift.Int? to Swift.Int"
    "constructor HeistForEachElementEvidence.init(parameter:matching:limit:matchedCount:iterationCount:iterationOrdinal:targetOrdinal:targetSummary:failureReason:) has removed default argument from parameter 5"
    "constructor HeistForEachElementEvidence.init(parameter:matching:limit:matchedCount:iterationCount:iterationOrdinal:targetOrdinal:targetSummary:failureReason:) has parameter 6 type change from Swift.Int? to Swift.Int"
    "constructor HeistForEachElementEvidence.init(parameter:matching:limit:matchedCount:iterationCount:iterationOrdinal:targetOrdinal:targetSummary:failureReason:) has removed default argument from parameter 6"
    "constructor HeistForEachElementEvidence.init(parameter:matching:limit:matchedCount:iterationCount:iterationOrdinal:targetOrdinal:targetSummary:failureReason:) has parameter 7 type change from Swift.String? to Swift.String"
    "constructor HeistForEachElementEvidence.init(parameter:matching:limit:matchedCount:iterationCount:iterationOrdinal:targetOrdinal:targetSummary:failureReason:) has removed default argument from parameter 7"
    "constructor RotorTextRange.init(text:startOffset:endOffset:rangeDescription:) has removed default argument from parameter 0"
    "constructor RotorTextRange.init(text:startOffset:endOffset:rangeDescription:) has parameter 1 type change from Swift.Int? to Swift.Int"
    "constructor RotorTextRange.init(text:startOffset:endOffset:rangeDescription:) has removed default argument from parameter 1"
    "constructor RotorTextRange.init(text:startOffset:endOffset:rangeDescription:) has parameter 2 type change from Swift.Int? to Swift.Int"
    "constructor RotorTextRange.init(text:startOffset:endOffset:rangeDescription:) has removed default argument from parameter 2"
    "constructor ActivationTrace.init(axActivateReturned:tapActivationDispatched:tapActivationPoint:tapActivationSucceeded:) has been removed"
    "constructor RequestEnvelope.init(buttonHeistVersion:requestId:message:requestScreenPayload:) has been removed"
    "var RequestEnvelope.explicitScreenRequestPayload has been removed"
    "enumelement HeistStepIntent.action has declared type change from (TheScore.HeistStepIntent.Type) -> (Swift.String, Swift.String?) -> TheScore.HeistStepIntent to (TheScore.HeistStepIntent.Type) -> (ThePlans.HeistActionCommand) -> TheScore.HeistStepIntent"
    "enumelement HeistStepIntent.wait has declared type change from (TheScore.HeistStepIntent.Type) -> (Swift.String, Swift.Double) -> TheScore.HeistStepIntent to (TheScore.HeistStepIntent.Type) -> (ThePlans.AccessibilityPredicateExpr, Swift.Double) -> TheScore.HeistStepIntent"
    "enumelement HeistStepIntent.forEachElement has declared type change from (TheScore.HeistStepIntent.Type) -> (ThePlans.HeistReferenceName, Swift.String, Swift.Int) -> TheScore.HeistStepIntent to (TheScore.HeistStepIntent.Type) -> (ThePlans.HeistReferenceName, ThePlans.ElementPredicate, Swift.Int) -> TheScore.HeistStepIntent"
    "enumelement HeistStepIntent.repeatUntil has declared type change from (TheScore.HeistStepIntent.Type) -> (Swift.String, Swift.Double) -> TheScore.HeistStepIntent to (TheScore.HeistStepIntent.Type) -> (ThePlans.AccessibilityPredicateExpr, Swift.Double) -> TheScore.HeistStepIntent"
    "enumelement HeistStepIntent.invoke has declared type change from (TheScore.HeistStepIntent.Type) -> (Swift.String, Swift.String?) -> TheScore.HeistStepIntent to (TheScore.HeistStepIntent.Type) -> (ThePlans.HeistInvocationPath, ThePlans.HeistArgument) -> TheScore.HeistStepIntent"
    "func HeistExecutionStepResult.passed(path:kind:durationMs:intent:evidence:children:) has generic signature change from  to <Evidence>"
    "func HeistExecutionStepResult.passed(path:kind:durationMs:intent:evidence:children:) has parameter 1 type change from TheScore.HeistExecutionStepKind to TheScore.HeistStepReceiptKind<Evidence>"
    "func HeistExecutionStepResult.passed(path:kind:durationMs:intent:evidence:children:) has parameter 4 type change from TheScore.HeistStepEvidence? to Evidence"
    "func HeistExecutionStepResult.passed(path:kind:durationMs:intent:evidence:children:) has removed default argument from parameter 4"
    "func HeistExecutionStepResult.failed(path:kind:durationMs:intent:evidence:failure:children:) has generic signature change from  to <Evidence>"
    "func HeistExecutionStepResult.failed(path:kind:durationMs:intent:evidence:failure:children:) has parameter 1 type change from TheScore.HeistExecutionStepKind to TheScore.HeistStepReceiptKind<Evidence>"
    "func HeistExecutionStepResult.failed(path:kind:durationMs:intent:evidence:failure:children:) has parameter 4 type change from TheScore.HeistStepEvidence? to Evidence"
    "func HeistExecutionStepResult.failed(path:kind:durationMs:intent:evidence:failure:children:) has removed default argument from parameter 4"
    "func HeistExecutionStepResult.childAborted(path:kind:durationMs:intent:evidence:failure:abortedAtChildPath:children:) has generic signature change from  to <Evidence>"
    "func HeistExecutionStepResult.childAborted(path:kind:durationMs:intent:evidence:failure:abortedAtChildPath:children:) has parameter 1 type change from TheScore.HeistExecutionStepKind to TheScore.HeistStepReceiptKind<Evidence>"
    "func HeistExecutionStepResult.childAborted(path:kind:durationMs:intent:evidence:failure:abortedAtChildPath:children:) has parameter 4 type change from TheScore.HeistStepEvidence to Evidence"
    "func HeistExecutionStepResult.childAborted(path:kind:durationMs:intent:evidence:failure:child:remainingChildren:) has generic signature change from  to <Evidence>"
    "func HeistExecutionStepResult.childAborted(path:kind:durationMs:intent:evidence:failure:child:remainingChildren:) has parameter 1 type change from TheScore.HeistExecutionStepKind to TheScore.HeistStepReceiptKind<Evidence>"
    "func HeistExecutionStepResult.childAborted(path:kind:durationMs:intent:evidence:failure:child:remainingChildren:) has parameter 4 type change from TheScore.HeistStepEvidence to Evidence"
    "func HeistExecutionStepResult.passed(path:kind:durationMs:intent:evidence:children:) has been renamed to func passed(path:receiptKind:durationMs:intent:evidence:children:)"
    "func HeistExecutionStepResult.failed(path:kind:durationMs:intent:evidence:failure:children:) has been renamed to func failed(path:receiptKind:durationMs:intent:evidence:failure:children:)"
    "func HeistExecutionStepResult.childAborted(path:kind:durationMs:intent:evidence:failure:abortedAtChildPath:children:) has been renamed to func childAborted(path:receiptKind:durationMs:intent:evidence:failure:abortedAtChildPath:children:)"
    "func HeistExecutionStepResult.childAborted(path:kind:durationMs:intent:evidence:failure:child:remainingChildren:) has been renamed to func childAborted(path:receiptKind:durationMs:intent:evidence:failure:child:remainingChildren:)"
    "func TheFence.Command.routeToolRequest(named:arguments:) has return type change from Swift.Result<ButtonHeist.FenceOperationRequest, ButtonHeist.FenceOperationRoutingError> to Swift.Result<ButtonHeist.FenceCommandInput, ButtonHeist.FenceOperationRoutingError>"
    "func TheFence.Command.routeCommandEnvelope(_:context:) has return type change from Swift.Result<ButtonHeist.FenceOperationRequest, ButtonHeist.FenceOperationRoutingError> to Swift.Result<ButtonHeist.FenceCommandInput, ButtonHeist.FenceOperationRoutingError>"
    "func TheFence.Command.routeCLICommandEnvelope(_:context:) has return type change from Swift.Result<ButtonHeist.FenceOperationRequest, ButtonHeist.FenceOperationRoutingError> to Swift.Result<ButtonHeist.FenceCommandInput, ButtonHeist.FenceOperationRoutingError>"
    "var SessionFailurePayload.errorCode has been renamed to var code"
    "constructor SessionFailurePayload.init(errorCode:phase:retryable:message:hint:) has been removed"
    "var FenceOperationRequest.arguments has been removed"
    "constructor FenceOperationRequest.init(command:arguments:) has been removed"
    "func minimumUniquePredicate(for:in:) has parameter 1 type change from [(id: TheScore.PredicateSelectionElementId, element: Subject)] to [TheScore.PredicateSelectionSubjectElement<Subject>]"
    "func MinimumPredicateSelector.minimumUniquePredicate(for:in:) has parameter 1 type change from [(id: TheScore.PredicateSelectionElementId, element: Subject)] to [TheScore.PredicateSelectionSubjectElement<Subject>]"
    "var AccessibilityHierarchy.elements has declared type change from [(element: AccessibilitySnapshotModel.AccessibilityElement, traversalIndex: Swift.Int)] to [TheScore.AccessibilityElementTraversalRecord]"
    "accessor AccessibilityHierarchy.elements.Get() has return type change from [(element: AccessibilitySnapshotModel.AccessibilityElement, traversalIndex: Swift.Int)] to [TheScore.AccessibilityElementTraversalRecord]"
    "var Array.elements has declared type change from [(element: AccessibilitySnapshotModel.AccessibilityElement, traversalIndex: Swift.Int)] to [TheScore.AccessibilityElementTraversalRecord]"
    "accessor Array.elements.Get() has return type change from [(element: AccessibilitySnapshotModel.AccessibilityElement, traversalIndex: Swift.Int)] to [TheScore.AccessibilityElementTraversalRecord]"
    "var HeistExecutionStepReportDetail.dispatchedActionResult has been removed"
    "var HeistExecutionStepReportDetail.actionResult has been removed"
    "var HeistExecutionStepReportDetail.traceEvidenceResult has been removed"
    "var HeistExecutionStepReportDetail.expectation has been removed"
    "var HeistExecutionStepReportDetail.actionErrorKind has been removed"
    "constructor HeistExecutionStepReportResults.init(dispatchedActionResult:actionResult:traceEvidenceResult:expectation:actionErrorKind:) has been removed"
    "var HeistExecutionStepReportFacts.actionResult has been removed"
    "var HeistExecutionStepReportFacts.expectation has been removed"
    "var HeistExecutionStepReportFacts.actionErrorKind has been removed"
    "var HeistExecutionStepReportFacts.dispatchedActionResult has been removed"
    "var HeistExecutionStepReportFacts.traceEvidenceResult has been removed"
    "var HeistExecutionStepResult.reportStatus has been removed"
    "var HeistExecutionStepResult.reportStepName has been removed"
    "var HeistExecutionStepResult.dispatchedActionResult has been removed"
    "var HeistExecutionStepResult.reportedActionResult has been removed"
    "var HeistExecutionStepResult.traceEvidenceResult has been removed"
    "constructor ActionResult.init(outcome:method:message:accessibilityTrace:settled:settleTimeMs:subjectEvidence:activationTrace:timing:) has parameter 0 type change from TheScore.ActionResult.Outcome to TheScore.ActionResultOutcome"
    "constructor ActionResult.init(outcome:method:message:accessibilityTrace:settled:settleTimeMs:subjectEvidence:activationTrace:timing:announcement:) has parameter 0 type change from TheScore.ActionResult.Outcome to TheScore.ActionResultOutcome"
    "constructor ActionResult.init(outcome:payload:message:accessibilityTrace:settled:settleTimeMs:subjectEvidence:activationTrace:timing:) has parameter 0 type change from TheScore.ActionResult.Outcome to TheScore.ActionResultOutcome"
    "constructor ActionResult.init(outcome:payload:message:accessibilityTrace:settled:settleTimeMs:subjectEvidence:activationTrace:timing:announcement:) has parameter 0 type change from TheScore.ActionResult.Outcome to TheScore.ActionResultOutcome"
    "enum ActionResult.Outcome has been removed"
    "var ActionResult.success has been removed"
    "var ActionResult.errorKind has been removed"
    "func ButtonHeistTLSPreSharedKey.makeNetworkParameters(token:) has been removed"
    "struct HeistCatalogEntry has removed conformance to Decodable"
    "struct HeistCatalogEntry has removed conformance to Encodable"
    "var HeistCatalogEntry.tags has declared type change from [Swift.String] to [ThePlans.HeistCatalogTag]"
    "accessor HeistCatalogEntry.tags.Get() has return type change from [Swift.String] to [ThePlans.HeistCatalogTag]"
    "var HeistCatalogEntry.nestedRunHeists has declared type change from [Swift.String]? to [ThePlans.HeistInvocationPath]?"
    "accessor HeistCatalogEntry.nestedRunHeists.Get() has return type change from [Swift.String]? to [ThePlans.HeistInvocationPath]?"
    "var HeistCatalogEntry.actionCommands has declared type change from [Swift.String]? to [ThePlans.HeistActionCommandType]?"
    "accessor HeistCatalogEntry.actionCommands.Get() has return type change from [Swift.String]? to [ThePlans.HeistActionCommandType]?"
    "var HeistCatalogEntry.semanticSurfaces has declared type change from [Swift.String]? to [ThePlans.HeistSemanticSurfaceFact]?"
    "accessor HeistCatalogEntry.semanticSurfaces.Get() has return type change from [Swift.String]? to [ThePlans.HeistSemanticSurfaceFact]?"
    "constructor HeistCatalogEntry.init(name:role:parameterKind:requiresArgument:summary:tags:parameterName:nestedRunHeists:actionCommands:waitCount:expectationCount:semanticSurfaces:validationStatus:) has parameter 5 type change from [Swift.String] to [ThePlans.HeistCatalogTag]"
    "constructor HeistCatalogEntry.init(name:role:parameterKind:requiresArgument:summary:tags:parameterName:nestedRunHeists:actionCommands:waitCount:expectationCount:semanticSurfaces:validationStatus:) has parameter 7 type change from [Swift.String]? to [ThePlans.HeistInvocationPath]?"
    "constructor HeistCatalogEntry.init(name:role:parameterKind:requiresArgument:summary:tags:parameterName:nestedRunHeists:actionCommands:waitCount:expectationCount:semanticSurfaces:validationStatus:) has parameter 8 type change from [Swift.String]? to [ThePlans.HeistActionCommandType]?"
    "constructor HeistCatalogEntry.init(name:role:parameterKind:requiresArgument:summary:tags:parameterName:nestedRunHeists:actionCommands:waitCount:expectationCount:semanticSurfaces:validationStatus:) has parameter 11 type change from [Swift.String]? to [ThePlans.HeistSemanticSurfaceFact]?"
    "struct HeistDiscoveryCatalog has removed conformance to Decodable"
    "struct HeistDiscoveryCatalog has removed conformance to Encodable"
    "struct HeistSemanticSurface has removed conformance to Decodable"
    "struct HeistSemanticSurface has removed conformance to Encodable"
    "var HeistSemanticSurface.actionCommands has declared type change from [Swift.String] to [ThePlans.HeistActionCommandType]"
    "accessor HeistSemanticSurface.actionCommands.Get() has return type change from [Swift.String] to [ThePlans.HeistActionCommandType]"
    "var HeistSemanticSurface.targetPredicates has declared type change from [Swift.String] to [ThePlans.HeistTargetPredicateFact]"
    "accessor HeistSemanticSurface.targetPredicates.Get() has return type change from [Swift.String] to [ThePlans.HeistTargetPredicateFact]"
    "var HeistSemanticSurface.waits has declared type change from [Swift.String] to [ThePlans.AccessibilityPredicateExpr]"
    "accessor HeistSemanticSurface.waits.Get() has return type change from [Swift.String] to [ThePlans.AccessibilityPredicateExpr]"
    "var HeistSemanticSurface.expectations has declared type change from [Swift.String] to [ThePlans.AccessibilityPredicateExpr]"
    "accessor HeistSemanticSurface.expectations.Get() has return type change from [Swift.String] to [ThePlans.AccessibilityPredicateExpr]"
    "var HeistSemanticSurface.nestedRunHeists has declared type change from [Swift.String] to [ThePlans.HeistInvocationPath]"
    "accessor HeistSemanticSurface.nestedRunHeists.Get() has return type change from [Swift.String] to [ThePlans.HeistInvocationPath]"
    "var HeistSemanticSurface.expectedEffects has declared type change from [Swift.String] to [ThePlans.AccessibilityPredicateExpr]"
    "accessor HeistSemanticSurface.expectedEffects.Get() has return type change from [Swift.String] to [ThePlans.AccessibilityPredicateExpr]"
    "var HeistSemanticSurface.semanticSurfaces has declared type change from [Swift.String] to [ThePlans.HeistSemanticSurfaceFact]"
    "accessor HeistSemanticSurface.semanticSurfaces.Get() has return type change from [Swift.String] to [ThePlans.HeistSemanticSurfaceFact]"
    "constructor HeistSemanticSurface.init(actionCommands:targetPredicates:waits:expectations:nestedRunHeists:expectedEffects:semanticSurfaces:) has parameter 0 type change from [Swift.String] to [ThePlans.HeistActionCommandType]"
    "constructor HeistSemanticSurface.init(actionCommands:targetPredicates:waits:expectations:nestedRunHeists:expectedEffects:semanticSurfaces:) has parameter 1 type change from [Swift.String] to [ThePlans.HeistTargetPredicateFact]"
    "constructor HeistSemanticSurface.init(actionCommands:targetPredicates:waits:expectations:nestedRunHeists:expectedEffects:semanticSurfaces:) has parameter 2 type change from [Swift.String] to [ThePlans.AccessibilityPredicateExpr]"
    "constructor HeistSemanticSurface.init(actionCommands:targetPredicates:waits:expectations:nestedRunHeists:expectedEffects:semanticSurfaces:) has parameter 3 type change from [Swift.String] to [ThePlans.AccessibilityPredicateExpr]"
    "constructor HeistSemanticSurface.init(actionCommands:targetPredicates:waits:expectations:nestedRunHeists:expectedEffects:semanticSurfaces:) has parameter 4 type change from [Swift.String] to [ThePlans.HeistInvocationPath]"
    "constructor HeistSemanticSurface.init(actionCommands:targetPredicates:waits:expectations:nestedRunHeists:expectedEffects:semanticSurfaces:) has parameter 5 type change from [Swift.String] to [ThePlans.AccessibilityPredicateExpr]"
    "constructor HeistSemanticSurface.init(actionCommands:targetPredicates:waits:expectations:nestedRunHeists:expectedEffects:semanticSurfaces:) has parameter 6 type change from [Swift.String] to [ThePlans.HeistSemanticSurfaceFact]"
    "struct HeistDescription has removed conformance to Decodable"
    "struct HeistDescription has removed conformance to Encodable"
    "var ElementTarget.selectorFieldNames has been removed"
    "enumelement ElementTarget.CodingKeys.label has been removed"
    "enumelement ElementTarget.CodingKeys.identifier has been removed"
    "enumelement ElementTarget.CodingKeys.value has been removed"
    "enumelement ElementTarget.CodingKeys.hint has been removed"
    "enumelement ElementTarget.CodingKeys.traits has been removed"
    "enumelement ElementTarget.CodingKeys.actions has been removed"
    "enumelement ElementTarget.CodingKeys.customContent has been removed"
    "enumelement ElementTarget.CodingKeys.rotors has been removed"
    "func HeistCatalogEntry.encode(to:) has been removed"
    "constructor HeistCatalogEntry.init(from:) has been removed"
    "func HeistDiscoveryCatalog.encode(to:) has been removed"
    "constructor HeistDiscoveryCatalog.init(from:) has been removed"
    "func HeistSemanticSurface.encode(to:) has been removed"
    "constructor HeistSemanticSurface.init(from:) has been removed"
    "func HeistDescription.encode(to:) has been removed"
    "constructor HeistDescription.init(from:) has been removed"
    "constructor ResolvedRepeatUntilStep.init(predicate:timeout:body:elseBody:) has been removed"
    "enumelement AccessibilityContainerKind.none has been added as a new enum case"
    "enumelement ContainerPredicateCheck.scrollable has been added as a new enum case"
    "enumelement ContainerPredicateCheck.actions has been added as a new enum case"
    "enumelement AccessibilityContainerKind.scrollable has been removed"
    "constructor ContainerPredicateFacts.init(type:label:value:identifier:rowCount:columnCount:isModalBoundary:) has been removed"
    "var PublicJSONInputLimits.maxTotalArrayValues has been removed"
    "var PublicJSONInputLimits.maxStringBytes has been removed"
    "var PublicJSONInputPolicy.maxTotalArrayValues has been removed"
    "var PublicJSONInputPolicy.maxStringBytes has been removed"
    "constructor PublicJSONInputPolicy.init(maxBytes:maxNestingDepth:maxTotalObjectKeys:maxTotalArrayValues:maxStringBytes:nullHandling:) has been removed"
    "enumelement PublicJSONInputViolation.arrayValueCount has been removed"
    "enumelement PublicJSONInputViolation.stringBytes has been removed"
    "func TheFence.admit(command:arguments:) has been removed"
    "func ActionResult.success(method:message:accessibilityTrace:settled:settleTimeMs:subjectEvidence:activationTrace:timing:) has been removed"
    "func ActionResult.success(payload:message:accessibilityTrace:settled:settleTimeMs:subjectEvidence:activationTrace:timing:) has been removed"
    "func ActionResult.failure(method:errorKind:message:accessibilityTrace:settled:settleTimeMs:subjectEvidence:activationTrace:timing:) has been removed"
    "func ActionResult.failure(payload:errorKind:message:accessibilityTrace:settled:settleTimeMs:subjectEvidence:activationTrace:timing:) has been removed"
    "constructor ActionResult.init(outcome:method:message:accessibilityTrace:settled:settleTimeMs:subjectEvidence:activationTrace:timing:) has been removed"
    "constructor ActionResult.init(outcome:payload:message:accessibilityTrace:settled:settleTimeMs:subjectEvidence:activationTrace:timing:) has been removed"
    "func predicateCandidates(for:) has been removed"
    "func minimumUniquePredicate(for:in:) has been removed"
    "func ButtonHeistTLSPreSharedKey.makeNetworkParameters(token:) has been renamed to func networkParameters(from:)"
    "func AccessibilityPredicate.Change.screen() has been removed"
    "func AccessibilityPredicate.Change.screen(_:_:) has been removed"
    "func AccessibilityPredicate.ChangeScope.screen(_:_:) has been removed"
    "func ChangePredicateExpr.screen() has been removed"
    "func ChangePredicateExpr.screen(_:_:) has been removed"
    "func ChangeScopePredicateExpr.screen(_:_:) has been removed"
    "constructor HeistSemanticStringMatch.init(_:) has been removed"
    "var HeistExecutionEvidenceRollup.outputNodes has been removed"
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
