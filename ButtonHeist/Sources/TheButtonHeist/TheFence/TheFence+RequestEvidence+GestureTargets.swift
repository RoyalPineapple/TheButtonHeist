import TheScore

extension TapTarget {
    func heistRecordingProjection() throws -> HeistRecordingProjection {
        try HeistRecordingProjection(
            arguments: heistEvidenceArguments(renaming: ["pointX": "x", "pointY": "y"]),
            elementTarget: selection.elementTarget,
            coordinateOnly: selection.screenPoint != nil
        )
    }
}

extension LongPressTarget {
    func heistRecordingProjection() throws -> HeistRecordingProjection {
        try HeistRecordingProjection(
            arguments: heistEvidenceArguments(renaming: ["pointX": "x", "pointY": "y"]),
            elementTarget: selection.elementTarget,
            coordinateOnly: selection.screenPoint != nil
        )
    }
}

extension SwipeTarget {
    func heistRecordingProjection() throws -> HeistRecordingProjection {
        try HeistRecordingProjection(
            arguments: heistEvidenceArguments(),
            elementTarget: selection.bookKeeperElementTarget,
            coordinateOnly: selection.bookKeeperElementTarget == nil
        )
    }
}

extension DragTarget {
    func heistRecordingProjection() throws -> HeistRecordingProjection {
        try HeistRecordingProjection(
            arguments: heistEvidenceArguments(),
            elementTarget: start.elementTarget,
            coordinateOnly: start.elementTarget == nil
        )
    }
}

extension PinchTarget {
    func heistRecordingProjection() throws -> HeistRecordingProjection {
        try HeistRecordingProjection(
            arguments: heistEvidenceArguments(),
            elementTarget: center.elementTarget,
            coordinateOnly: center.elementTarget == nil
        )
    }
}

extension RotateTarget {
    func heistRecordingProjection() throws -> HeistRecordingProjection {
        try HeistRecordingProjection(
            arguments: heistEvidenceArguments(),
            elementTarget: center.elementTarget,
            coordinateOnly: center.elementTarget == nil
        )
    }
}

extension TwoFingerTapTarget {
    func heistRecordingProjection() throws -> HeistRecordingProjection {
        try HeistRecordingProjection(
            arguments: heistEvidenceArguments(),
            elementTarget: center.elementTarget,
            coordinateOnly: center.elementTarget == nil
        )
    }
}

private extension SwipeGestureSelection {
    var bookKeeperElementTarget: ElementTarget? {
        switch self {
        case .unitElement(let target, _, _, _):
            return target
        case .point(let start, _):
            return start.elementTarget
        }
    }
}
