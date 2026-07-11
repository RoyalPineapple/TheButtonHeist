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
        case .within(let container, let target):
            return ".within(container: \(container), \(renderTargetCorrection(target)))"
        }
    }

    func renderConcreteTargetCorrection(_ target: ElementTarget) -> String {
        switch target {
        case .predicate(let predicate, _):
            return renderPredicateCorrection(ElementPredicateTemplate(predicate))
        case .within(let container, let target):
            return ".within(container: \(container), \(renderConcreteTargetCorrection(target)))"
        }
    }

    func renderPredicateCorrection(_ predicate: ElementPredicateTemplate) -> String {
        if predicate.checks.count == 1 {
            switch predicate.checks[0] {
            case .label(let match):
                return ".label(\(renderStringMatchCallArgument(match)))"
            case .identifier(let match):
                return ".identifier(\(renderStringMatchCallArgument(match)))"
            case .value(let match):
                return ".value(\(renderStringMatchCallArgument(match)))"
            case .hint(let match):
                return ".hint(\(renderStringMatchCallArgument(match)))"
            case .actions(let actions):
                return ".actions(\(renderActionArrayCorrection(actions)))"
            case .customContent(let match):
                return ".customContent(\(renderCustomContentCorrection(match)))"
            case .rotors(let matches):
                return ".rotors(\(renderStringMatchArrayCorrection(matches)))"
            case .exclude(let check):
                return ".exclude(\(renderPredicateCheckCorrection(check)))"
            case .traits:
                break
            }
        }
        let fields = predicate.checks.map(renderPredicateCheckCorrection)
        return ".element(\(fields.joined(separator: ", ")))"
    }

    func renderPredicateCheckCorrection(_ check: ElementPredicateCheck<StringExpr>) -> String {
        switch check {
        case .label(let match):
            return ".label(\(renderStringMatchCallArgument(match)))"
        case .identifier(let match):
            return ".identifier(\(renderStringMatchCallArgument(match)))"
        case .value(let match):
            return ".value(\(renderStringMatchCallArgument(match)))"
        case .hint(let match):
            return ".hint(\(renderStringMatchCallArgument(match)))"
        case .traits(let traits):
            return ".traits(\(renderTraitArrayCorrection(traits)))"
        case .actions(let actions):
            return ".actions(\(renderActionArrayCorrection(actions)))"
        case .customContent(let match):
            return ".customContent(\(renderCustomContentCorrection(match)))"
        case .rotors(let matches):
            return ".rotors(\(renderStringMatchArrayCorrection(matches)))"
        case .exclude(let check):
            return ".exclude(\(renderPredicateCheckCorrection(check)))"
        }
    }

    func renderTraitArrayCorrection(_ traits: Set<HeistTrait>) -> String {
        "[\(traits.canonicalHeistTraitArray.map { ".\($0.rawValue)" }.joined(separator: ", "))]"
    }

    func renderActionArrayCorrection(_ actions: Set<ElementAction>) -> String {
        "[\(actions.canonicalElementActionArray.map(renderActionCorrection).joined(separator: ", "))]"
    }

    func renderActionCorrection(_ action: ElementAction) -> String {
        switch action {
        case .activate:
            return ".activate"
        case .typeText:
            return ".typeText"
        case .increment:
            return ".increment"
        case .decrement:
            return ".decrement"
        case .custom(let name):
            return ".custom(\(quote(name)))"
        }
    }

    func renderCustomContentCorrection(_ match: CustomContentMatch<StringExpr>) -> String {
        let fields = [
            match.label.map { "label: \(renderStringMatchFieldArgument($0))" },
            match.value.map { "value: \(renderStringMatchFieldArgument($0))" },
            match.isImportant.map { "isImportant: \($0)" },
        ].compactMap { $0 }
        return ".init(\(fields.joined(separator: ", ")))"
    }

    func renderStringMatchArrayCorrection(_ matches: [StringMatch<StringExpr>]) -> String {
        "[\(matches.map(renderStringMatchCallArgument).joined(separator: ", "))]"
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
        case .isEmpty:
            return ".isEmpty"
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
        case .isEmpty:
            return ".isEmpty"
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
        var replacingExisting = false
        var sawTarget = false
        var sawReplacingExisting = false
        while consumeSymbol(",") {
            let token = currentToken
            if lookaheadLabel("into") {
                try expectIdentifier("into")
                try expectSymbol(":")
                guard !sawTarget else {
                    throw error(token, "TypeText(...) accepts into only once")
                }
                target = try parseTargetExpr()
                sawTarget = true
            } else if lookaheadLabel("replacingExisting") {
                try expectIdentifier("replacingExisting")
                try expectSymbol(":")
                guard !sawReplacingExisting else {
                    throw error(token, "TypeText(...) accepts replacingExisting only once")
                }
                replacingExisting = try parseBoolLiteral()
                sawReplacingExisting = true
            } else {
                throw error(token, "TypeText(...) accepts labeled arguments into: and replacingExisting:")
            }
        }
        try expectSymbol(")")
        return .typeText(text: text, target: target, replacingExisting: replacingExisting)
    }

    mutating func parseClearTextAction() throws -> HeistActionCommand {
        try expectSymbol("(")
        let target = try parseTargetExpr()
        try expectSymbol(")")
        return .typeText(text: .literal(""), target: target, replacingExisting: true)
    }

    mutating func parseCustomAction() throws -> HeistActionCommand {
        try expectSymbol("(")
        let actionNameToken = currentToken
        let actionName = try parseStringLiteral()
        do {
            try CustomActionTarget.validate(actionName: actionName)
        } catch let validationError {
            throw error(actionNameToken, String(describing: validationError))
        }
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

    mutating func parseTakeScreenshotAction() throws -> HeistActionCommand {
        try expectSymbol("(")
        try expectSymbol(")")
        return .takeScreenshot
    }

    mutating func parseDismissAction() throws -> HeistActionCommand {
        try expectSymbol("(")
        try expectSymbol(")")
        return .dismiss
    }

    mutating func parseMagicTapAction() throws -> HeistActionCommand {
        try expectSymbol("(")
        try expectSymbol(")")
        return .magicTap
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
        case .within(let container, let target):
            return .within(
                try container.resolve(in: .empty),
                try concreteElementTarget(from: target)
            )
        }
    }

    mutating func concreteElementTarget(from expr: ElementTargetExpr) throws -> ElementTarget {
        switch expr {
        case .target(let target):
            return target
        case .predicate(let predicate, let ordinal):
            return .predicate(try concretePredicate(from: predicate), ordinal: ordinal)
        case .ref(let reference):
            throw error(previous, "mechanical actions require a concrete ElementTarget, not target ref '\(reference)'")
        case .within(let container, let target):
            return .within(
                try container.resolve(in: .empty),
                try concreteElementTarget(from: target)
            )
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
        var repeatedContent: RepeatActionUntilContent?
        while consumeSymbol(".") {
            let chainToken = currentToken
            let chain = try parseIdentifier()
            guard repeatedContent == nil else {
                throw error(chainToken, "unsupported action chain after '.until'")
            }
            switch chain {
            case "expect":
                try expectSymbol("(")
                let predicate: AccessibilityPredicateExpr
                let timeout: Double?
                if currentToken.isSymbol(")") {
                    predicate = .change(.elements())
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
            case "until":
                try expectSymbol("(")
                let predicate = try parseAccessibilityPredicateExpr()
                let timeout = try parseTrailingTimeout(defaultValue: defaultWaitTimeout) ?? defaultWaitTimeout
                try expectSymbol(")")
                repeatedContent = content.until(predicate, timeout: timeout)
            default:
                throw error(chainToken, "unsupported action chain '.\(chain)'")
            }
        }
        if let repeatedContent {
            if let diagnostic = repeatedContent.heistBuildDiagnostics.first {
                throw error(previous, diagnostic.message)
            }
            guard let step = repeatedContent.heistSteps.first, repeatedContent.heistSteps.count == 1 else {
                throw error(previous, "action .until statement did not produce exactly one step")
            }
            return step
        }
        if let diagnostic = content.heistBuildDiagnostics.first {
            throw error(previous, diagnostic.message)
        }
        guard let step = content.heistSteps.first, content.heistSteps.count == 1 else {
            throw error(previous, "action statement did not produce exactly one step")
        }
        return step
    }

}
