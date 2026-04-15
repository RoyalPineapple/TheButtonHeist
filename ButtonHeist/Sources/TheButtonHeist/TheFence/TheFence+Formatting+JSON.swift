import Foundation
import os.log

import TheScore

private let logger = Logger(subsystem: "com.buttonheist.thefence", category: "formatting")

extension FenceResponse {

    // MARK: - JSON Encoding

    public func jsonDict() -> [String: Any]? {
        switch self {
        case .ok(let message):
            return ["status": "ok", "message": message]
        case .error(let message):
            return ["status": "error", "message": message]
        case .help(let commands):
            return ["status": "ok", "commands": commands]
        case .status(let connected, let deviceName):
            var payload: [String: Any] = ["status": "ok", "connected": connected]
            if let deviceName { payload["device"] = deviceName }
            return payload
        case .devices(let devices):
            return devicesJsonDict(devices)
        case .interface(let interface, let detail, let filteredFrom, let explore):
            return interfaceJsonDict(interface, detail: detail, filteredFrom: filteredFrom, explore: explore)
        case .action(let result, let expectation):
            return actionWithExpectationJsonDict(result, expectation: expectation)
        case .screenshot(let path, let width, let height):
            return ["status": "ok", "path": path, "width": width, "height": height]
        case .screenshotData(let pngData, let width, let height):
            return ["status": "ok", "pngData": pngData, "width": width, "height": height]
        case .recording(let path, let payload):
            return recordingJsonDict(path: path, payload: payload)
        case .recordingData(let payload):
            return recordingDataJsonDict(payload)
        case .batch(let results, let completedSteps, let failedIndex, let totalTimingMs, let checked, let met, let stepSummaries, let netDelta):
            return batchJsonDict(
                results: results, completedSteps: completedSteps, failedIndex: failedIndex,
                totalTimingMs: totalTimingMs, checked: checked, met: met,
                stepSummaries: stepSummaries, netDelta: netDelta
            )
        case .sessionState(let payload):
            return payload
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
        case .sessionLog, .archiveResult, .heistStarted, .heistStopped, .heistPlayback:
            return bookKeeperJsonDict(self)
        }
    }

    private func bookKeeperJsonDict(_ response: FenceResponse) -> [String: Any] {
        switch response {
        case .sessionLog(let manifest):
            return sessionLogJsonDict(manifest)
        case .archiveResult(let path, let manifest):
            var dict = sessionLogJsonDict(manifest)
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
        case .ok, .error, .help, .status, .devices, .interface, .action,
             .screenshot, .screenshotData, .recording, .recordingData, .batch,
             .sessionState, .targets:
            return ["status": "ok"]
        }
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

    private func sessionLogJsonDict(_ manifest: SessionManifest) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        var dict: [String: Any] = [
            "status": "ok",
            "formatVersion": manifest.formatVersion,
            "sessionId": manifest.sessionId,
            "startTime": formatter.string(from: manifest.startTime),
            "commandCount": manifest.commandCount,
            "errorCount": manifest.errorCount,
            "artifactCount": manifest.artifacts.count,
        ]
        if let endTime = manifest.endTime {
            dict["endTime"] = formatter.string(from: endTime)
        }
        dict["artifacts"] = manifest.artifacts.map { artifact -> [String: Any] in
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

    private func interfaceJsonDict(
        _ interface: Interface, detail: InterfaceDetail, filteredFrom: Int?,
        explore: ExploreResult? = nil
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "status": "ok",
            "detail": detail.rawValue,
            "interface": interfaceDictionary(interface, detail: detail),
        ]
        if let filteredFrom { dict["filteredFrom"] = filteredFrom }
        if let explore {
            dict["explore"] = [
                "elementCount": explore.elementCount,
                "scrollCount": explore.scrollCount,
                "containersExplored": explore.containersExplored,
                "explorationTime": explore.explorationTime,
            ] as [String: Any]
        }
        return dict
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
        results: [[String: Any]], completedSteps: Int, failedIndex: Int?,
        totalTimingMs: Int, checked: Int, met: Int,
        stepSummaries: [BatchStepSummary], netDelta: InterfaceDelta?
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "status": failedIndex == nil ? "ok" : "partial",
            "results": results,
            "completedSteps": completedSteps,
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
        if let netDelta {
            dict["netDelta"] = deltaDictionary(netDelta)
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
        if let value = result.value { payload["value"] = value }
        if result.animating == true { payload["animating"] = true }
        if let delta = result.interfaceDelta {
            payload["delta"] = deltaDictionary(delta)
        }

        if let screenName = result.screenName { payload["screenName"] = screenName }
        if let screenId = result.screenId { payload["screenId"] = screenId }

        if let explore = result.exploreResult {
            payload["explore"] = [
                "elementCount": explore.elementCount,
                "scrollCount": explore.scrollCount,
                "containersExplored": explore.containersExplored,
                "explorationTime": String(format: "%.2f", explore.explorationTime),
            ] as [String: Any]
        }

        if !result.success {
            payload["errorClass"] = Self.actionErrorClass(result)
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
            "elements": interface.elements.map { elementDictionary($0, detail: detail) }
        ]
        if detail == .full, let tree = interface.tree {
            payload["tree"] = tree.map(elementNodeDictionary)
        }
        payload["screenDescription"] = interface.screenDescription
        if let screenId = interface.screenId { payload["screenId"] = screenId }
        payload["navigation"] = navigationDictionary(interface.navigation)
        return payload
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
        if let label = element.label { payload["label"] = label }
        if let value = element.value { payload["value"] = value }
        if let identifier = element.identifier { payload["identifier"] = identifier }

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

        // Geometry and extended fields only in full detail
        if detail == .full {
            payload["frameX"] = element.frameX
            payload["frameY"] = element.frameY
            payload["frameWidth"] = element.frameWidth
            payload["frameHeight"] = element.frameHeight
            payload["activationPointX"] = element.activationPointX
            payload["activationPointY"] = element.activationPointY
            if let hint = element.hint { payload["hint"] = hint }
        }
        return payload
    }

    private static func customContentEntry(_ item: HeistCustomContent) -> [String: String] {
        var entry: [String: String] = [:]
        if !item.label.isEmpty { entry["label"] = item.label }
        if !item.value.isEmpty { entry["value"] = item.value }
        return entry
    }

    private func elementNodeDictionary(_ node: ElementNode) -> [String: Any] {
        switch node {
        case .element(let order):
            return ["element": ["order": order]]
        case .container(let group, let children):
            return [
                "container": [
                    "_0": groupDictionary(group),
                    "children": children.map(elementNodeDictionary)
                ]
            ]
        }
    }

    private func groupDictionary(_ group: Group) -> [String: Any] {
        var payload: [String: Any] = [
            "type": group.type.rawValue,
            "frameX": group.frameX,
            "frameY": group.frameY,
            "frameWidth": group.frameWidth,
            "frameHeight": group.frameHeight
        ]
        if let label = group.label { payload["label"] = label }
        if let value = group.value { payload["value"] = value }
        if let identifier = group.identifier { payload["identifier"] = identifier }
        return payload
    }

    /// Delta dictionaries are always summary-level — geometry changes are filtered out.
    /// Callers who need full geometry should use `get_interface --detail full`.
    private func deltaDictionary(_ delta: InterfaceDelta) -> [String: Any] {
        var payload: [String: Any] = [
            "kind": delta.kind.rawValue,
            "elementCount": delta.elementCount,
        ]
        if let added = delta.added {
            payload["added"] = added.map { elementDictionary($0, detail: .summary) }
        }
        if let removed = delta.removed {
            payload["removed"] = removed
        }
        if let updated = delta.updated {
            // Omit geometry changes (frame/activationPoint) — layout shifts are structural noise
            let filtered: [ElementUpdate] = updated.compactMap { update in
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
        if let newInterface = delta.newInterface {
            payload["newInterface"] = interfaceDictionary(newInterface, detail: .summary)
        }
        return payload
    }
}
