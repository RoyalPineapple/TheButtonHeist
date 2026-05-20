import Foundation
import CoreGraphics
import os.log

import AccessibilitySnapshotModel
import TheScore

private let logger = Logger(subsystem: "com.buttonheist.thefence", category: "formatting")

extension FenceResponse {

    // MARK: - JSON Encoding

    public func jsonDict() -> [String: Any] {
        let dict = unvalidatedJsonDict()
        guard JSONSerialization.isValidJSONObject(dict) else {
            return Self.jsonEncodingFailureDict()
        }
        return dict
    }

    private func unvalidatedJsonDict() -> [String: Any] {
        switch self {
        case .ok(let message):
            return ["status": "ok", "message": message]
        case .error(let message, let details):
            return errorJsonDict(message, details: details)
        case .help(let commands):
            return ["status": "ok", "commands": commands]
        case .status(let connected, let deviceName):
            var payload: [String: Any] = ["status": "ok", "connected": connected]
            if let deviceName { payload["device"] = deviceName }
            return payload
        case .devices(let devices):
            return devicesJsonDict(devices)
        case .interface(let interface, let detail):
            return interfaceJsonDict(interface, detail: detail)
        case .action(let result, let expectation):
            return actionWithExpectationJsonDict(result, expectation: expectation)
        case .screenshot(let path, let payload, let options):
            var dict = screenJsonDict(payload, includePNGData: false, includeInterface: options.includeInterface)
            dict["path"] = path
            return dict
        case .screenshotData(let payload, let options):
            return screenJsonDict(payload, includePNGData: true, includeInterface: options.includeInterface)
        case .recording(let path, let payload):
            return recordingJsonDict(path: path, payload: payload)
        case .recordingData(let payload):
            return recordingDataJsonDict(payload)
        case .batch(let outcomes, let totalTimingMs, let accessibilityTrace):
            return batchJsonDict(
                outcomes: outcomes,
                totalTimingMs: totalTimingMs,
                accessibilityTrace: accessibilityTrace
            )
        case .sessionState(let payload):
            return sessionStateJsonDict(payload)
        case .targets(let targets, let defaultTarget):
            var info: [String: [String: Any]] = [:]
            for (name, target) in targets {
                var entry: [String: Any] = ["device": target.device]
                if target.token != nil { entry["hasToken"] = true }
                info[name] = entry
            }
            var result: [String: Any] = ["status": "ok", "targets": info]
            if let defaultTarget { result["default"] = defaultTarget }
            return result
        case .sessionLog(let snapshot):
            return sessionLogJsonDict(snapshot)
        case .archiveResult(let path, let snapshot):
            var dict = sessionLogJsonDict(snapshot)
            dict["path"] = path
            return dict
        case .heistStarted:
            return ["status": "ok", "recording": true]
        case .heistStopped(let path, let stepCount):
            return ["status": "ok", "path": path, "stepCount": stepCount]
        case .heistPlayback(let completedSteps, let failedIndex, let totalTimingMs, let failure, _):
            var dict: [String: Any] = [
                "status": failedIndex == nil ? "ok" : "error",
                "completedSteps": completedSteps,
                "totalTimingMs": totalTimingMs,
            ]
            if let failedIndex { dict["failedIndex"] = failedIndex }
            if let failure {
                dict["failure"] = playbackFailureDict(failure)
            }
            return dict
        }
    }

    private static func jsonEncodingFailureDict() -> [String: Any] {
        [
            "status": "error",
            "message": "Failed to encode JSON response: response contained non-JSON values",
            "errorCode": "formatting.json_encoding_failed",
            "phase": FailurePhase.client.rawValue,
            "retryable": false,
            "hint": "Report this diagnostic with the command that produced it.",
        ]
    }

    private func screenJsonDict(
        _ payload: ScreenPayload,
        includePNGData: Bool,
        includeInterface: Bool
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "status": "ok",
            "width": payload.width,
            "height": payload.height,
        ]
        if includePNGData {
            dict["pngData"] = payload.pngData
        }
        if includeInterface {
            dict["interface"] = interfaceDictionary(payload.interface, detail: .full)
        }
        return dict
    }

    private func playbackFailureDict(_ failure: PlaybackFailure) -> [String: Any] {
        var dict: [String: Any] = [
            "command": failure.step.command,
            "error": failure.errorMessage,
        ]
        if let target = failure.step.target {
            var targetDict: [String: Any] = [:]
            if let label = target.label { targetDict["label"] = label }
            if let identifier = target.identifier { targetDict["identifier"] = identifier }
            if let value = target.value { targetDict["value"] = value }
            if let traits = target.traits { targetDict["traits"] = traits.map(\.rawValue) }
            dict["target"] = targetDict
        }
        switch failure {
        case .actionFailed(_, let result, let expectation, let interface):
            dict["actionResult"] = actionJsonDict(result)
            if let expectation, !expectation.met {
                dict["expectation"] = Self.expectationResultDict(expectation)
            }
            if let interface {
                dict["interface"] = interfaceDictionary(interface, detail: .summary)
            }
        case .fenceError(_, _, let interface), .thrown(_, _, let interface):
            if let interface {
                dict["interface"] = interfaceDictionary(interface, detail: .summary)
            }
        }
        return dict
    }

    private func errorJsonDict(_ message: String, details: FailureDetails?) -> [String: Any] {
        var dict: [String: Any] = [
            "status": "error",
            "message": message,
        ]
        if let details {
            dict["errorCode"] = details.errorCode
            dict["phase"] = details.phase.rawValue
            dict["retryable"] = details.retryable
            if let hint = details.hint {
                dict["hint"] = hint
            }
        }
        return dict
    }

    private func sessionLogJsonDict(_ snapshot: SessionLogSnapshot) -> [String: Any] {
        let manifest = snapshot.manifest
        let formatter = ISO8601DateFormatter()
        var dict: [String: Any] = [
            "status": "ok",
            "formatVersion": manifest.formatVersion,
            "sessionId": manifest.sessionId,
            "startTime": formatter.string(from: manifest.startTime),
            "commandCount": snapshot.counts.commandCount,
            "errorCount": snapshot.counts.errorCount,
            "artifactCount": snapshot.artifacts.count,
        ]
        if let endTime = manifest.endTime {
            dict["endTime"] = formatter.string(from: endTime)
        }
        if snapshot.projectionStatus.isDegraded {
            dict["projectionStatus"] = projectionStatusJsonDict(snapshot.projectionStatus)
        }
        dict["artifacts"] = snapshot.artifacts.map { artifact -> [String: Any] in
            var entry: [String: Any] = [
                "type": artifact.type.rawValue,
                "path": artifact.path,
                "size": artifact.size,
                "timestamp": formatter.string(from: artifact.timestamp),
                "command": artifact.command,
            ]
            if !artifact.metadata.isEmpty {
                entry["metadata"] = artifact.metadata
            }
            return entry
        }
        return dict
    }

    private func projectionStatusJsonDict(_ status: SessionLogProjectionStatus) -> [String: Any] {
        var dict: [String: Any] = [
            "degraded": true,
            "malformedLineCount": status.malformedLineCount,
            "malformedArtifactCount": status.malformedArtifactCount,
        ]
        if let firstMalformedLineNumber = status.firstMalformedLineNumber {
            dict["firstMalformedLineNumber"] = firstMalformedLineNumber
        }
        if let firstMalformedLineCause = status.firstMalformedLineCause {
            dict["firstMalformedLineCause"] = firstMalformedLineCause
        }
        return dict
    }

    private func interfaceJsonDict(
        _ interface: Interface, detail: InterfaceDetail
    ) -> [String: Any] {
        [
            "status": "ok",
            "detail": detail.rawValue,
            "interface": interfaceDictionary(interface, detail: detail),
        ]
    }

    private func actionWithExpectationJsonDict(
        _ result: ActionResult, expectation: ExpectationResult?
    ) -> [String: Any] {
        var dict = actionJsonDict(result)
        if let expectation {
            dict["expectation"] = Self.expectationResultDict(expectation)
            if !expectation.met {
                dict["status"] = "expectation_failed"
            }
        }
        return dict
    }

    private func batchJsonDict(
        outcomes: [BatchStepOutcome],
        totalTimingMs: Int,
        accessibilityTrace: AccessibilityTrace?
    ) -> [String: Any] {
        let failedIndex = outcomes.stoppedFailedIndex
        let checked = outcomes.expectationsChecked
        let met = outcomes.expectationsMet
        let stepSummaries = outcomes.stepSummaries
        var dict: [String: Any] = [
            "status": failedIndex == nil ? "ok" : "partial",
            "results": outcomes.jsonResultRows,
            "completedSteps": outcomes.completedStepCount,
            "totalTimingMs": totalTimingMs,
        ]
        if let failedIndex { dict["failedIndex"] = failedIndex }
        if checked > 0 {
            dict["expectations"] = [
                "checked": checked,
                "met": met,
                "allMet": checked == met,
            ]
        }
        if !stepSummaries.isEmpty {
            dict["stepSummaries"] = stepSummaries.enumerated().map { index, summary in
                Self.stepSummaryDict(index: index, summary: summary)
            }
        }
        if let netDelta = accessibilityTrace?.meaningfulCaptureEndpointDelta {
            dict["netDelta"] = deltaDictionary(netDelta)
        }
        return dict
    }

    private func sessionStateJsonDict(_ payload: SessionStatePayload) -> [String: Any] {
        var dict: [String: Any] = [
            "status": "ok",
            "connected": payload.connected,
            "phase": payload.phase.rawValue,
            "isRecording": payload.isRecording,
            "actionTimeoutSeconds": payload.actionTimeoutSeconds,
            "longActionTimeoutSeconds": payload.longActionTimeoutSeconds,
        ]
        if let device = payload.device {
            dict["deviceName"] = device.deviceName
            dict["appName"] = device.appName
            dict["connectionType"] = device.connectionType.rawValue
            if let shortId = device.shortId {
                dict["shortId"] = shortId
            }
        }
        if let failure = payload.lastFailure {
            var failurePayload: [String: Any] = [
                "errorCode": failure.errorCode,
                "phase": failure.phase.rawValue,
                "retryable": failure.retryable,
            ]
            if let message = failure.message {
                failurePayload["message"] = message
            }
            if let hint = failure.hint {
                failurePayload["hint"] = hint
            }
            dict["lastFailure"] = failurePayload
        }
        if let lastAction = payload.lastAction {
            var lastActionPayload: [String: Any] = [
                "method": lastAction.method.rawValue,
                "success": lastAction.success,
                "latency_ms": lastAction.latencyMs,
            ]
            if let message = lastAction.message {
                lastActionPayload["message"] = message
            }
            dict["lastAction"] = lastActionPayload
        }
        return dict
    }

    private static func stepSummaryDict(index: Int, summary: BatchStepSummary) -> [String: Any] {
        var entry: [String: Any] = ["index": index, "command": summary.command]
        if let kind = summary.deltaKind { entry["deltaKind"] = kind }
        if let screen = summary.screenName { entry["screenName"] = screen }
        if let screenId = summary.screenId { entry["screenId"] = screenId }
        if let met = summary.expectationMet { entry["expectationMet"] = met }
        if let count = summary.elementCount { entry["elementCount"] = count }
        if let error = summary.error { entry["error"] = error }
        if let errorCode = summary.errorCode { entry["errorCode"] = errorCode }
        if let phase = summary.phase { entry["phase"] = phase }
        if let nextCommand = summary.nextCommand { entry["nextCommand"] = nextCommand }
        return entry
    }

    private func devicesJsonDict(_ devices: [DiscoveredDevice]) -> [String: Any] {
        let info = devices.map { device -> [String: Any] in
            var payload: [String: Any] = [
                "name": device.name,
                "appName": device.appName,
                "deviceName": device.deviceName,
                "connectionType": device.connectionType.rawValue,
            ]
            if let shortId = device.shortId { payload["shortId"] = shortId }
            if let simulatorUDID = device.simulatorUDID { payload["simulatorUDID"] = simulatorUDID }
            return payload
        }
        return ["status": "ok", "devices": info]
    }

    private func actionJsonDict(_ result: ActionResult) -> [String: Any] {
        var payload: [String: Any] = [
            "status": result.success ? "ok" : "error",
            "method": result.method.rawValue,
        ]
        if let message = result.message { payload["message"] = message }
        if case .value(let value) = result.payload { payload["value"] = value }
        if case .rotor(let search) = result.payload {
            var rotor: [String: Any] = [
                "name": search.rotor,
                "direction": search.direction.rawValue,
            ]
            if let foundElement = search.foundElement {
                rotor["foundElement"] = elementDictionary(foundElement, detail: .summary)
            }
            if let textRange = search.textRange {
                var range: [String: Any] = [
                    "rangeDescription": textRange.rangeDescription,
                ]
                if let text = textRange.text { range["text"] = text }
                if let startOffset = textRange.startOffset { range["startOffset"] = startOffset }
                if let endOffset = textRange.endOffset { range["endOffset"] = endOffset }
                rotor["textRange"] = range
            }
            payload["rotor"] = rotor
        }
        if result.animating == true { payload["animating"] = true }
        if let delta = result.accessibilityDelta {
            payload["delta"] = deltaDictionary(delta)
        }

        if let screenName = result.screenName { payload["screenName"] = screenName }
        if let screenId = result.screenId { payload["screenId"] = screenId }

        if case .explore(let explore) = result.payload {
            payload["explore"] = [
                "elementCount": explore.elementCount,
                "scrollCount": explore.scrollCount,
                "containersExplored": explore.containersExplored,
                "explorationTime": String(format: "%.2f", explore.explorationTime),
            ] as [String: Any]
        }

        if !result.success {
            payload["errorClass"] = Self.actionErrorClass(result)
            if let details = Self.actionFailureDetails(result) {
                payload["errorCode"] = details.errorCode
                payload["phase"] = details.phase.rawValue
                payload["retryable"] = details.retryable
                if let hint = details.hint {
                    payload["hint"] = hint
                }
            }
        }

        return payload
    }

    static func expectationResultDict(_ result: ExpectationResult) -> [String: Any] {
        var dict: [String: Any] = ["met": result.met]
        if let actual = result.actual { dict["actual"] = actual }
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(result.expectation)
            let object = try JSONSerialization.jsonObject(with: data)
            dict["expected"] = object
        } catch {
            logger.warning("Failed to encode expectation result: \(error.localizedDescription)")
        }
        return dict
    }

    private static func actionErrorClass(_ result: ActionResult) -> String {
        (result.errorKind ?? .actionFailed).rawValue
    }

    private func recordingJsonDict(path: String, payload: RecordingPayload) -> [String: Any] {
        var dict: [String: Any] = [
            "status": "ok",
            "path": path,
            "width": payload.width,
            "height": payload.height,
            "duration": payload.duration,
            "frameCount": payload.frameCount,
            "fps": payload.fps,
            "stopReason": payload.stopReason.rawValue,
            "interactionCount": payload.interactionLog?.count ?? 0,
        ]
        if let logDicts = encodeInteractionLog(payload.interactionLog) {
            dict["interactionLog"] = logDicts
        }
        return dict
    }

    private func recordingDataJsonDict(_ payload: RecordingPayload) -> [String: Any] {
        var dict: [String: Any] = [
            "status": "ok",
            "videoData": payload.videoData,
            "width": payload.width,
            "height": payload.height,
            "duration": payload.duration,
            "frameCount": payload.frameCount,
            "fps": payload.fps,
            "stopReason": payload.stopReason.rawValue,
            "interactionCount": payload.interactionLog?.count ?? 0,
        ]
        if let logDicts = encodeInteractionLog(payload.interactionLog) {
            dict["interactionLog"] = logDicts
        }
        return dict
    }

    private func encodeInteractionLog(_ events: [InteractionEvent]?) -> [[String: Any]]? {
        guard let events, !events.isEmpty else { return nil }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(events)
            guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                logger.warning("Interaction log serialized to non-array JSON")
                return nil
            }
            return array
        } catch {
            logger.warning("Failed to encode interaction log: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - JSON Dictionary Helpers

    private func interfaceDictionary(_ interface: Interface, detail: InterfaceDetail = .full) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        var payload: [String: Any] = [
            "timestamp": formatter.string(from: interface.timestamp),
            "tree": interfaceTreeDictionaries(interface, detail: detail)
        ]
        payload["screenDescription"] = interface.screenDescription
        if let screenId = interface.screenId { payload["screenId"] = screenId }
        payload["navigation"] = navigationDictionary(interface.navigation)
        return payload
    }

    private func interfaceTreeDictionaries(_ interface: Interface, detail: InterfaceDetail) -> [[String: Any]] {
        let counter = IndexCounter()
        let elementAnnotations = interface.annotations.elementByPath
        let containerAnnotations = interface.annotations.containerByPath
        return interface.tree.enumerated().map { index, node in
            nodeDictionary(
                node,
                path: TreePath([index]),
                detail: detail,
                counter: counter,
                elementAnnotations: elementAnnotations,
                containerAnnotations: containerAnnotations
            )
        }
    }

    /// Reference-typed leaf counter so a single counter threads through the
    /// `folded()` recursion without needing inout state in the closures.
    private final class IndexCounter {
        var value: Int = 0
    }

    /// Recursive projection over the parser hierarchy. The tree stays
    /// `AccessibilityHierarchy`; Button Heist metadata is attached from capture
    /// annotations at formatting time.
    private func nodeDictionary(
        _ node: AccessibilityHierarchy,
        path: TreePath,
        detail: InterfaceDetail,
        counter: IndexCounter?,
        elementAnnotations: [TreePath: InterfaceElementAnnotation],
        containerAnnotations: [TreePath: InterfaceContainerAnnotation]
    ) -> [String: Any] {
        switch node {
        case .element(let element, _):
            let projected = HeistElement(
                accessibilityElement: element,
                annotation: elementAnnotations[path]
            )
            var payload = elementDictionary(projected, detail: detail)
            if let counter {
                payload["order"] = counter.value
                counter.value += 1
            }
            return ["element": payload]

        case .container(let container, let children):
            var payload = containerDictionary(
                container,
                annotation: containerAnnotations[path],
                detail: detail
            )
            payload["children"] = children.enumerated().map { index, child in
                nodeDictionary(
                    child,
                    path: path.appending(index),
                    detail: detail,
                    counter: counter,
                    elementAnnotations: elementAnnotations,
                    containerAnnotations: containerAnnotations
                )
            }
            return ["container": payload]
        }
    }

    private func navigationDictionary(_ navigation: NavigationContext) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let screenTitle = navigation.screenTitle { payload["screenTitle"] = screenTitle }
        if let backButton = navigation.backButton {
            var entry: [String: Any] = ["heistId": backButton.heistId]
            if let label = backButton.label { entry["label"] = label }
            if let value = backButton.value { entry["value"] = value }
            payload["backButton"] = entry
        }
        if let tabBarItems = navigation.tabBarItems {
            payload["tabBarItems"] = tabBarItems.map { tab in
                var entry: [String: Any] = ["heistId": tab.heistId]
                if let label = tab.label { entry["label"] = label }
                if let value = tab.value { entry["value"] = value }
                if tab.selected { entry["selected"] = true }
                return entry
            }
        }
        return payload
    }

    /// JSON shape for a single element.
    ///
    /// Summary keeps the identity fields (heistId, label, value, identifier,
    /// traits, meaningful actions) and drops the heavy fields. Full adds the
    /// heavy semantic fields (`hint`, `customContent`) and geometry
    /// (`frame*`, `activationPoint*`). The MCP tool description promises
    /// "summary (default, no geometry)" — agents that ask for summary expect
    /// thin payloads suitable for repeated polling, not the full semantic
    /// surface area.
    private func elementDictionary(_ element: HeistElement, detail: InterfaceDetail = .full) -> [String: Any] {
        var payload: [String: Any] = [
            "heistId": element.heistId,
            "traits": element.traits.map(\.rawValue),
        ]
        // Only include non-obvious actions (activate is implied by button trait)
        let meaningfulActions = Self.meaningfulActions(element)
        if !meaningfulActions.isEmpty {
            payload["actions"] = meaningfulActions.map(\.description)
        }
        if let rotors = element.rotors, !rotors.isEmpty {
            payload["rotors"] = rotors.map(\.name)
        }
        if let label = element.label { payload["label"] = label }
        if let value = element.value { payload["value"] = value }
        if let identifier = element.identifier { payload["identifier"] = identifier }

        // Heavy semantic fields and geometry are full-detail only.
        if detail == .full {
            if let hint = element.hint { payload["hint"] = hint }
            if let customContent = element.customContent {
                let important = customContent.filter(\.isImportant)
                let defaultContent = customContent.filter { !$0.isImportant }
                var content: [String: Any] = [:]
                if !important.isEmpty {
                    content["important"] = important.map(Self.customContentEntry)
                }
                if !defaultContent.isEmpty {
                    content["default"] = defaultContent.map(Self.customContentEntry)
                }
                payload["customContent"] = content
            }
            payload["frameX"] = element.frameX
            payload["frameY"] = element.frameY
            payload["frameWidth"] = element.frameWidth
            payload["frameHeight"] = element.frameHeight
            payload["activationPointX"] = element.activationPointX
            payload["activationPointY"] = element.activationPointY
        }
        return payload
    }

    private static func customContentEntry(_ item: HeistCustomContent) -> [String: String] {
        var entry: [String: String] = [:]
        if !item.label.isEmpty { entry["label"] = item.label }
        if !item.value.isEmpty { entry["value"] = item.value }
        return entry
    }

    /// Delta payloads serialize inserted subtrees at summary detail (no
    /// geometry, no heavy semantics) and never carry traversal-order indices.
    private func deltaNodeDictionary(_ insertion: TreeInsertion) -> [String: Any] {
        nodeDictionary(
            insertion.node,
            path: .root,
            detail: .summary,
            counter: nil,
            elementAnnotations: insertion.annotations.elementByPath,
            containerAnnotations: insertion.annotations.containerByPath
        )
    }

    private func containerDictionary(
        _ container: AccessibilityContainer,
        annotation: InterfaceContainerAnnotation?,
        detail: InterfaceDetail
    ) -> [String: Any] {
        var payload: [String: Any] = [:]
        switch container.type {
        case .semanticGroup(let label, let value, let identifier):
            payload["type"] = "semanticGroup"
            if let label { payload["label"] = label }
            if let value { payload["value"] = value }
            if let identifier { payload["identifier"] = identifier }
        case .list:
            payload["type"] = "list"
        case .landmark:
            payload["type"] = "landmark"
        case .dataTable(let rowCount, let columnCount):
            payload["type"] = "dataTable"
            payload["rowCount"] = rowCount
            payload["columnCount"] = columnCount
        case .tabBar:
            payload["type"] = "tabBar"
        case .scrollable(let contentSize):
            payload["type"] = "scrollable"
            payload["contentWidth"] = sanitizedDouble(contentSize.width)
            payload["contentHeight"] = sanitizedDouble(contentSize.height)
        }
        if container.isModalBoundary {
            payload["isModalBoundary"] = true
        }
        if let stableId = annotation?.stableId {
            payload["stableId"] = stableId
        }
        if detail == .full {
            payload["frameX"] = sanitizedDouble(container.frame.origin.x)
            payload["frameY"] = sanitizedDouble(container.frame.origin.y)
            payload["frameWidth"] = sanitizedDouble(container.frame.size.width)
            payload["frameHeight"] = sanitizedDouble(container.frame.size.height)
        }
        return payload
    }

    private func sanitizedDouble(_ value: CGFloat) -> Double {
        value.isFinite ? Double(value) : 0
    }

    /// Delta dictionaries are always summary-level — geometry changes are filtered out.
    /// Callers who need full geometry should use `get_interface --detail full`.
    private func deltaDictionary(_ delta: AccessibilityTrace.Delta) -> [String: Any] {
        var payload: [String: Any] = [
            "kind": delta.kindRawValue,
            "elementCount": delta.elementCount,
        ]
        if let captureEdge = delta.captureEdge {
            payload["captureEdge"] = captureEdgeDictionary(captureEdge)
        }
        let transient = delta.transient
        if !transient.isEmpty {
            payload["transient"] = transient.map { elementDictionary($0, detail: .summary) }
        }
        switch delta {
        case .noChange:
            break
        case .elementsChanged(let casePayload):
            if !casePayload.edits.isEmpty {
                var editsDict: [String: Any] = [:]
                mergeEditDictionary(casePayload.edits, into: &editsDict)
                if !editsDict.isEmpty {
                    payload["edits"] = editsDict
                }
            }
        case .screenChanged(let casePayload):
            payload["newInterface"] = interfaceDictionary(casePayload.newInterface, detail: .summary)
        }
        return payload
    }

    private func captureEdgeDictionary(_ edge: AccessibilityTrace.CaptureEdge) -> [String: Any] {
        [
            "before": captureRefDictionary(edge.before),
            "after": captureRefDictionary(edge.after),
        ]
    }

    private func captureRefDictionary(_ ref: AccessibilityTrace.CaptureRef) -> [String: Any] {
        [
            "sequence": ref.sequence,
            "hash": ref.hash,
        ]
    }

    private func mergeEditDictionary(_ edits: ElementEdits, into payload: inout [String: Any]) {
        if !edits.added.isEmpty {
            payload["added"] = edits.added.map { elementDictionary($0, detail: .summary) }
        }
        if !edits.removed.isEmpty {
            payload["removed"] = edits.removed
        }
        if !edits.updated.isEmpty {
            // Omit geometry changes (frame/activationPoint) — layout shifts are structural noise
            let filtered: [ElementUpdate] = edits.updated.compactMap { update in
                let meaningful = update.changes.filter { !$0.property.isGeometry }
                return meaningful.isEmpty ? nil : ElementUpdate(heistId: update.heistId, changes: meaningful)
            }
            if !filtered.isEmpty {
                payload["updated"] = filtered.map { update -> [String: Any] in
                    [
                        "heistId": update.heistId,
                        "changes": update.changes.map { change -> [String: Any] in
                            var entry: [String: Any] = ["property": change.property.rawValue]
                            if let old = change.old { entry["old"] = old }
                            if let new = change.new { entry["new"] = new }
                            return entry
                        },
                    ]
                }
            }
        }
        if !edits.treeInserted.isEmpty {
            payload["treeInserted"] = edits.treeInserted.map(treeInsertionDictionary)
        }
        if !edits.treeRemoved.isEmpty {
            payload["treeRemoved"] = edits.treeRemoved.map(treeRemovalDictionary)
        }
        if !edits.treeMoved.isEmpty {
            payload["treeMoved"] = edits.treeMoved.map(treeMoveDictionary)
        }
    }

    private func treeInsertionDictionary(_ insertion: TreeInsertion) -> [String: Any] {
        [
            "location": treeLocationDictionary(insertion.location),
            "node": deltaNodeDictionary(insertion),
        ]
    }

    private func treeRemovalDictionary(_ removal: TreeRemoval) -> [String: Any] {
        [
            "ref": treeNodeRefDictionary(removal.ref),
            "location": treeLocationDictionary(removal.location),
        ]
    }

    private func treeMoveDictionary(_ move: TreeMove) -> [String: Any] {
        [
            "ref": treeNodeRefDictionary(move.ref),
            "from": treeLocationDictionary(move.from),
            "to": treeLocationDictionary(move.to),
        ]
    }

    private func treeNodeRefDictionary(_ ref: TreeNodeRef) -> [String: Any] {
        [
            "id": ref.id,
            "kind": ref.kind.rawValue,
        ]
    }

    private func treeLocationDictionary(_ location: TreeLocation) -> [String: Any] {
        var payload: [String: Any] = ["index": location.index]
        if let parentId = location.parentId {
            payload["parentId"] = parentId
        }
        return payload
    }
}
