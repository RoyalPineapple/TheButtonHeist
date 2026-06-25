import Foundation

extension HeistPlanSourceParser {
    mutating func parseElementTargetAction(
        _ actionName: String,
        makeCommand: (ElementTargetExpr) -> HeistActionCommand
    ) throws -> HeistActionCommand {
        try expectSymbol("(")
        let target = try parseTargetExpr()
        try rejectActionLevelOrdinalIfPresent(actionName: actionName, target: target)
        try expectSymbol(")")
        return makeCommand(target)
    }

    mutating func rejectActionLevelOrdinalIfPresent(
        actionName: String,
        target: ElementTargetExpr
    ) throws {
        guard consumeSymbol(",") else { return }
        let token = currentToken
        if consumeIdentifier("ordinal") != nil {
            try expectSymbol(":")
            _ = try parseInteger()
            throw error(
                token,
                "Ordinal belongs to the target. Use \(actionName)(.target(\(renderTargetCorrection(target)), ordinal: 0))."
            )
        }
        throw error(token, "\(actionName)(...) accepts a single ElementTargetExpr")
    }

    func renderTargetCorrection(_ target: ElementTargetExpr) -> String {
        switch target {
        case .predicate(let predicate, _):
            return renderPredicateCorrection(predicate)
        case .target(let target):
            return renderConcreteTargetCorrection(target)
        case .ref(let reference):
            return reference.rawValue
        }
    }

    func renderConcreteTargetCorrection(_ target: ElementTarget) -> String {
        switch target {
        case .predicate(let predicate, _):
            return renderPredicateCorrection(ElementPredicateTemplate(predicate))
        }
    }

    func renderPredicateCorrection(_ predicate: ElementPredicateTemplate) -> String {
        if predicate.traits.isEmpty, predicate.excludeTraits.isEmpty {
            switch (predicate.label, predicate.identifier, predicate.value) {
            case (.some(let label), nil, nil):
                return ".label(\(renderStringMatchCallArgument(label)))"
            case (nil, .some(let identifier), nil):
                return ".identifier(\(renderStringMatchCallArgument(identifier)))"
            case (nil, nil, .some(let value)):
                return ".value(\(renderStringMatchCallArgument(value)))"
            default:
                break
            }
        }
        var fields: [String] = []
        if let label = predicate.label { fields.append("label: \(renderStringMatchFieldArgument(label))") }
        if let identifier = predicate.identifier { fields.append("identifier: \(renderStringMatchFieldArgument(identifier))") }
        if let value = predicate.value { fields.append("value: \(renderStringMatchFieldArgument(value))") }
        if !predicate.traits.isEmpty {
            fields.append("traits: [\(predicate.traits.map { ".\($0.rawValue)" }.joined(separator: ", "))]")
        }
        if !predicate.excludeTraits.isEmpty {
            fields.append("excludeTraits: [\(predicate.excludeTraits.map { ".\($0.rawValue)" }.joined(separator: ", "))]")
        }
        return ".element(\(fields.joined(separator: ", ")))"
    }

    func renderStringMatchCallArgument(_ match: StringMatch<StringExpr>) -> String {
        switch match {
        case .exact(let string):
            return renderStringCorrection(string)
        case .contains(let string):
            return ".contains(\(renderStringCorrection(string)))"
        case .prefix(let string):
            return ".prefix(\(renderStringCorrection(string)))"
        case .suffix(let string):
            return ".suffix(\(renderStringCorrection(string)))"
        }
    }

    func renderStringMatchFieldArgument(_ match: StringMatch<StringExpr>) -> String {
        switch match {
        case .exact(let string):
            return renderStringCorrection(string)
        case .contains(let string):
            return ".contains(\(renderStringCorrection(string)))"
        case .prefix(let string):
            return ".prefix(\(renderStringCorrection(string)))"
        case .suffix(let string):
            return ".suffix(\(renderStringCorrection(string)))"
        }
    }

    func renderStringCorrection(_ string: StringExpr) -> String {
        switch string {
        case .literal(let value):
            return quote(value)
        case .ref(let reference):
            return reference.rawValue
        }
    }

    mutating func parseTypeTextAction() throws -> HeistActionCommand {
        try expectSymbol("(")
        let text = try parseStringExpr()
        var target: ElementTargetExpr?
        if consumeSymbol(",") {
            try expectIdentifier("into")
            try expectSymbol(":")
            target = try parseTargetExpr()
        }
        try expectSymbol(")")
        return .typeText(text: text, target: target)
    }

    mutating func parseCustomAction() throws -> HeistActionCommand {
        try expectSymbol("(")
        let actionName = try parseStringLiteral()
        try expectSymbol(",")
        try expectIdentifier("on")
        try expectSymbol(":")
        let target = try parseTargetExpr()
        try expectSymbol(")")
        return .customAction(name: actionName, target: target)
    }

    mutating func parseRotorAction() throws -> HeistActionCommand {
        try expectSymbol("(")
        let rotorName = try parseStringLiteral()
        try expectSymbol(",")
        try expectIdentifier("on")
        try expectSymbol(":")
        let target = try parseTargetExpr()
        var direction = RotorDirection.next
        if consumeSymbol(",") {
            try expectIdentifier("direction")
            try expectSymbol(":")
            direction = try parseEnumCase(RotorDirection.self, role: "rotor direction")
        }
        try expectSymbol(")")
        return .rotor(selection: .named(rotorName), target: target, direction: direction)
    }

    mutating func parseSetPasteboardAction() throws -> HeistActionCommand {
        try expectSymbol("(")
        let text = try parseStringLiteral()
        try expectSymbol(")")
        return .setPasteboard(SetPasteboardTarget(text: text))
    }

    mutating func parseEditAction() throws -> HeistActionCommand {
        try expectSymbol("(")
        let action = try parseEnumCase(EditAction.self, role: "edit action")
        try expectSymbol(")")
        return .editAction(EditActionTarget(action: action))
    }

    mutating func parseDismissKeyboardAction() throws -> HeistActionCommand {
        try expectSymbol("(")
        try expectSymbol(")")
        return .dismissKeyboard
    }

    mutating func parseMechanicalTap() throws -> HeistActionCommand {
        try expectSymbol("(")
        let selection: GesturePointSelection
        if tokenIsIdentifier(currentToken, "ScreenPoint") {
            selection = .coordinate(try parseScreenPoint())
        } else {
            let target = try parseConcreteElementTarget()
            if consumeSymbol(",") {
                try expectIdentifier("at")
                try expectSymbol(":")
                selection = .elementUnitPoint(target, try parseUnitPoint())
            } else {
                selection = .element(target)
            }
        }
        try expectSymbol(")")
        return .mechanicalTap(TapTarget(selection: selection))
    }

    mutating func parseMechanicalLongPress() throws -> HeistActionCommand {
        try expectSymbol("(")
        let selection: GesturePointSelection
        var duration = GestureDuration.longPressDefault
        if tokenIsIdentifier(currentToken, "ScreenPoint") {
            selection = .coordinate(try parseScreenPoint())
        } else {
            let target = try parseConcreteElementTarget()
            if currentToken.isSymbol(","), lookaheadIdentifier(1, "at") {
                try expectSymbol(",")
                try expectIdentifier("at")
                try expectSymbol(":")
                selection = .elementUnitPoint(target, try parseUnitPoint())
            } else {
                selection = .element(target)
            }
        }
        if consumeSymbol(",") {
            try expectIdentifier("duration")
            try expectSymbol(":")
            duration = try parseGestureDuration()
        }
        try expectSymbol(")")
        return .mechanicalLongPress(LongPressTarget(selection: selection, duration: duration))
    }

    mutating func parseMechanicalSwipe() throws -> HeistActionCommand {
        try expectSymbol("(")
        let selection: SwipeGestureSelection
        if lookaheadLabel("from") {
            try expectIdentifier("from")
            try expectSymbol(":")
            let start = try parseScreenPoint()
            try expectSymbol(",")
            if lookaheadLabel("to") {
                try expectIdentifier("to")
                try expectSymbol(":")
                selection = .point(start: .coordinate(start), destination: .coordinate(try parseScreenPoint()))
            } else {
                let direction = try parseEnumCase(SwipeDirection.self, role: "swipe direction")
                selection = .point(start: .coordinate(start), destination: .direction(direction))
            }
        } else {
            let target = try parseConcreteElementTarget()
            try expectSymbol(",")
            if lookaheadLabel("from") {
                try expectIdentifier("from")
                try expectSymbol(":")
                let start = try parseUnitPoint()
                try expectSymbol(",")
                try expectIdentifier("to")
                try expectSymbol(":")
                selection = .unitElement(target, start: start, end: try parseUnitPoint())
            } else {
                selection = .elementDirection(target, try parseEnumCase(SwipeDirection.self, role: "swipe direction"))
            }
        }
        try expectSymbol(")")
        return .mechanicalSwipe(SwipeTarget(selection: selection))
    }

    mutating func parseMechanicalDrag() throws -> HeistActionCommand {
        try expectSymbol("(")
        let selection: DragGestureSelection
        if lookaheadLabel("from") {
            try expectIdentifier("from")
            try expectSymbol(":")
            let start = try parseScreenPoint()
            try expectSymbol(",")
            try expectIdentifier("to")
            try expectSymbol(":")
            selection = .pointToPoint(start: start, end: try parseScreenPoint())
        } else {
            let target = try parseConcreteElementTarget()
            try expectSymbol(",")
            let start: UnitPoint?
            if lookaheadLabel("from") {
                try expectIdentifier("from")
                try expectSymbol(":")
                start = try parseUnitPoint()
                try expectSymbol(",")
            } else {
                start = nil
            }
            try expectIdentifier("to")
            try expectSymbol(":")
            selection = .elementToPoint(target, start: start, end: try parseScreenPoint())
        }
        try expectSymbol(")")
        return .mechanicalDrag(DragTarget(selection: selection))
    }

    mutating func parseConcreteElementTarget() throws -> ElementTarget {
        let expr = try parseTargetExpr()
        switch expr {
        case .target(let target):
            return target
        case .predicate(let predicate, let ordinal):
            return .predicate(try concretePredicate(from: predicate), ordinal: ordinal)
        case .ref(let reference):
            throw error(previous, "mechanical actions require a concrete ElementTarget, not target ref '\(reference)'")
        }
    }

    mutating func parseXYArguments() throws -> ScreenPoint {
        try expectIdentifier("x")
        try expectSymbol(":")
        let x = try parseNumber()
        try expectSymbol(",")
        try expectIdentifier("y")
        try expectSymbol(":")
        let y = try parseNumber()
        return ScreenPoint(x: x, y: y)
    }

    mutating func parseScreenPoint() throws -> ScreenPoint {
        try expectIdentifier("ScreenPoint")
        try expectSymbol("(")
        let point = try parseXYArguments()
        try expectSymbol(")")
        return point
    }

    mutating func parseUnitPoint() throws -> UnitPoint {
        try expectIdentifier("UnitPoint")
        try expectSymbol("(")
        let point = try parseXYArguments()
        try expectSymbol(")")
        return UnitPoint(x: point.x, y: point.y)
    }

    mutating func parseGestureDuration() throws -> GestureDuration {
        try expectIdentifier("GestureDuration")
        try expectSymbol("(")
        try expectIdentifier("seconds")
        try expectSymbol(":")
        let seconds = try parseNumber()
        try expectSymbol(")")
        return GestureDuration(seconds: seconds)
    }

    mutating func parseActionStep(
        command: HeistActionCommand
    ) throws -> HeistStep {
        var content: any HeistActionContent = ActionContent(command: command)
        while consumeSymbol(".") {
            let chainToken = currentToken
            let chain = try parseIdentifier()
            switch chain {
            case "expect":
                try expectSymbol("(")
                let predicate: AccessibilityPredicateExpr
                let timeout: Double?
                if currentToken.isSymbol(")") {
                    predicate = .changed(.elements)
                    timeout = nil
                } else {
                    predicate = try parseAccessibilityPredicateExpr()
                    timeout = try parseTrailingTimeout(defaultValue: nil)
                }
                try expectSymbol(")")
                content = content.expect(predicate, timeout: timeout)
            case "withoutExpectation":
                try expectSymbol("(")
                let reason = try parseStringLiteral()
                try expectSymbol(")")
                content = content.withoutExpectation(reason)
            default:
                throw error(chainToken, "unsupported action chain '.\(chain)'")
            }
        }
        guard let step = content.heistSteps.first, content.heistSteps.count == 1 else {
            throw error(previous, "action statement did not produce exactly one step")
        }
        return step
    }

}
