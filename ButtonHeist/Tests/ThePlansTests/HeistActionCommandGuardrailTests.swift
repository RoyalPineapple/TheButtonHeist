import Foundation
import Testing
@_spi(ButtonHeistInternals) import ThePlans

@Test func `action command contract table covers every wire command type`() throws {
    let coveredTypes = actionCommandContractCases.map(\.wireType.rawValue).sorted()
    let allTypes = HeistActionCommandType.allCases.map(\.rawValue).sorted()

    #expect(coveredTypes == allTypes)
}

@Test func `action command wire durability report target and canonical source contracts stay aligned`() throws {
    for testCase in actionCommandContractCases {
        let data = try JSONEncoder().encode(testCase.command)
        let encoded = try JSONDecoder().decode(EncodedCommandType.self, from: data)

        #expect(testCase.command.wireType == testCase.wireType)
        #expect(encoded.type == testCase.wireType.rawValue)
        #expect(try JSONDecoder().decode(HeistActionCommand.self, from: data) == testCase.command)
        #expect(testCase.command.durableHeistActionFailure == testCase.durabilityFailure)
        #expect(testCase.command.reportTarget == testCase.reportTarget)

        let plan = try HeistPlan(body: [.action(try ActionStep(command: testCase.command))])
        if let canonicalLine = testCase.canonicalLine {
            let expectedSource = canonicalPlanSource(canonicalLine)
            #expect(try plan.canonicalSwiftDSL() == expectedSource)
            #expect(try HeistPlanSourceCompiler().compile(expectedSource) == plan)
        } else {
            let expectedFailure = try #require(testCase.durabilityFailure)
            #expect(throws: HeistCanonicalSwiftDSLError.unsupportedAction(expectedFailure)) {
                _ = try plan.canonicalSwiftDSL()
            }
        }
    }
}

@Test func `wait timeout contract matrix covers DSL expectations and runtime payloads`() throws {
    let waitCases: [(String, HeistPlan, WaitStep)] = [
        (
            "WaitFor default",
            try HeistPlan {
                WaitFor(.present(.label("Home")))
            },
            WaitStep(predicate: .present(.label("Home")), timeout: 0)
        ),
        (
            "WaitFor explicit",
            try HeistPlan {
                WaitFor(.present(.label("Home")), timeout: .seconds(5))
            },
            WaitStep(predicate: .present(.label("Home")), timeout: 5)
        ),
        (
            "WaitFor over cap",
            try HeistPlan {
                WaitFor(.present(.label("Home")), timeout: .seconds(45))
            },
            WaitStep(predicate: .present(.label("Home")), timeout: 45)
        ),
        (
            "expect default predicate",
            try HeistPlan {
                Activate(.label("Pay")).expect()
            },
            WaitStep(predicate: .changed(.elements), timeout: 1)
        ),
        (
            "expect default timeout",
            try HeistPlan {
                Activate(.label("Pay")).expect(.present(.label("Receipt")))
            },
            WaitStep(predicate: .present(.label("Receipt")), timeout: 1)
        ),
        (
            "expect explicit timeout",
            try HeistPlan {
                Activate(.label("Pay")).expect(.present(.label("Receipt")), timeout: .seconds(3))
            },
            WaitStep(predicate: .present(.label("Receipt")), timeout: 3)
        ),
        (
            "expect over cap",
            try HeistPlan {
                Activate(.label("Pay")).expect(.present(.label("Receipt")), timeout: .seconds(45))
            },
            WaitStep(predicate: .present(.label("Receipt")), timeout: 45)
        ),
    ]

    for (name, plan, expectedWait) in waitCases {
        let actualWait = try #require(plan.onlyWaitStep, "Missing wait step for \(name)")
        #expect(actualWait == expectedWait, "\(name)")
    }

    let predicate = AccessibilityPredicate.present(.label("Home"))
    let waitTargetCases: [(String, WaitTarget, Double?, Double)] = [
        ("default runtime timeout", WaitTarget(predicate: predicate), nil, 10),
        ("explicit runtime timeout", WaitTarget(predicate: predicate, timeout: 12), 12, 12),
        ("over cap runtime timeout", WaitTarget(predicate: predicate, timeout: 45), 45, 30),
        // Low-level WaitTarget currently does not validate negatives; executable WaitStep plans do.
        ("negative runtime payload gap", WaitTarget(predicate: predicate, timeout: -1), -1, -1),
    ]

    for (name, target, timeout, resolvedTimeout) in waitTargetCases {
        #expect(target.timeout == timeout, "\(name)")
        #expect(target.resolvedTimeout == resolvedTimeout, "\(name)")
    }
}

@Test func `negative wait timeouts are rejected at executable plan boundaries`() {
    #expect(throws: HeistPlanRuntimeSafetyError.self) {
        _ = try HeistPlan {
            WaitFor(.present(.label("Home")), timeout: .seconds(-1))
        }
    }

    #expect(throws: HeistPlanRuntimeSafetyError.self) {
        _ = try HeistPlan {
            Activate(.label("Pay")).expect(.present(.label("Receipt")), timeout: .seconds(-1))
        }
    }

    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(WaitStep.self, from: Data("""
        {
          "predicate": { "type": "present", "element": { "label": "Home" } },
          "timeout": -1
        }
        """.utf8))
    }
}

private struct EncodedCommandType: Decodable {
    let type: String
}

private struct ActionCommandContractCase {
    let wireType: HeistActionCommandType
    let command: HeistActionCommand
    let durabilityFailure: String?
    let reportTarget: ElementTarget?
    let canonicalLine: String?
}

private let actionCommandContractCases: [ActionCommandContractCase] = [
    ActionCommandContractCase(
        wireType: .activate,
        command: .activate(.label("Activate Target")),
        durabilityFailure: nil,
        reportTarget: .label("Activate Target"),
        canonicalLine: #"Activate(.label("Activate Target"))"#
    ),
    ActionCommandContractCase(
        wireType: .increment,
        command: .increment(.label("Stepper")),
        durabilityFailure: nil,
        reportTarget: .label("Stepper"),
        canonicalLine: #"Increment(.label("Stepper"))"#
    ),
    ActionCommandContractCase(
        wireType: .decrement,
        command: .decrement(.label("Stepper")),
        durabilityFailure: nil,
        reportTarget: .label("Stepper"),
        canonicalLine: #"Decrement(.label("Stepper"))"#
    ),
    ActionCommandContractCase(
        wireType: .performCustomAction,
        command: .customAction(name: "Archive", target: .label("Message")),
        durabilityFailure: nil,
        reportTarget: .label("Message"),
        canonicalLine: #"CustomAction("Archive", on: .label("Message"))"#
    ),
    ActionCommandContractCase(
        wireType: .rotor,
        command: .rotor(selection: .named("Headings"), target: .label("Article"), direction: .previous),
        durabilityFailure: nil,
        reportTarget: .label("Article"),
        canonicalLine: #"Rotor("Headings", on: .label("Article"), direction: .previous)"#
    ),
    ActionCommandContractCase(
        wireType: .oneFingerTap,
        command: .mechanicalTap(TapTarget(selection: .element(.label("Tap Target")))),
        durabilityFailure: nil,
        reportTarget: .label("Tap Target"),
        canonicalLine: #"Mechanical.Tap(.label("Tap Target"))"#
    ),
    ActionCommandContractCase(
        wireType: .longPress,
        command: .mechanicalLongPress(LongPressTarget(selection: .element(.label("Press Target")))),
        durabilityFailure: nil,
        reportTarget: .label("Press Target"),
        canonicalLine: #"Mechanical.LongPress(.label("Press Target"))"#
    ),
    ActionCommandContractCase(
        wireType: .swipe,
        command: .mechanicalSwipe(SwipeTarget(selection: .elementDirection(.label("List"), .up))),
        durabilityFailure: nil,
        reportTarget: .label("List"),
        canonicalLine: #"Mechanical.Swipe(.label("List"), .up)"#
    ),
    ActionCommandContractCase(
        wireType: .drag,
        command: .mechanicalDrag(DragTarget(start: .element(.label("Slider")), end: ScreenPoint(x: 200, y: 40))),
        durabilityFailure: nil,
        reportTarget: .label("Slider"),
        canonicalLine: #"Mechanical.Drag(.label("Slider"), to: ScreenPoint(x: 200, y: 40))"#
    ),
    ActionCommandContractCase(
        wireType: .typeText,
        command: .typeText(text: "milk", target: .label("Search")),
        durabilityFailure: nil,
        reportTarget: .label("Search"),
        canonicalLine: #"TypeText("milk", into: .label("Search"))"#
    ),
    ActionCommandContractCase(
        wireType: .editAction,
        command: .editAction(EditActionTarget(action: .paste)),
        durabilityFailure: nil,
        reportTarget: nil,
        canonicalLine: "Edit(.paste)"
    ),
    ActionCommandContractCase(
        wireType: .setPasteboard,
        command: .setPasteboard(SetPasteboardTarget(text: "milk")),
        durabilityFailure: nil,
        reportTarget: nil,
        canonicalLine: #"SetPasteboard("milk")"#
    ),
    ActionCommandContractCase(
        wireType: .takeScreenshot,
        command: .takeScreenshot,
        durabilityFailure: nil,
        reportTarget: nil,
        canonicalLine: "TakeScreenshot()"
    ),
    ActionCommandContractCase(
        wireType: .scroll,
        command: .viewportScroll(ScrollTarget(selection: .element(.label("Scrollable List")), direction: .down)),
        durabilityFailure: "scroll is a viewport debug command, not a durable heist action",
        reportTarget: .label("Scrollable List"),
        canonicalLine: nil
    ),
    ActionCommandContractCase(
        wireType: .scrollToVisible,
        command: .viewportScrollToVisible(.label("Checkout")),
        durabilityFailure: "scroll_to_visible is a viewport debug command, not a durable heist action",
        reportTarget: .label("Checkout"),
        canonicalLine: nil
    ),
    ActionCommandContractCase(
        wireType: .scrollToEdge,
        command: .viewportScrollToEdge(ScrollToEdgeTarget(selection: .element(.label("Scrollable List")), edge: .bottom)),
        durabilityFailure: "scroll_to_edge is a viewport debug command, not a durable heist action",
        reportTarget: .label("Scrollable List"),
        canonicalLine: nil
    ),
    ActionCommandContractCase(
        wireType: .resignFirstResponder,
        command: .dismissKeyboard,
        durabilityFailure: nil,
        reportTarget: nil,
        canonicalLine: "DismissKeyboard()"
    ),
]

private func canonicalPlanSource(_ line: String) -> String {
    """
    HeistPlan {
        \(line)
    }
    """
}

private extension HeistPlan {
    var onlyWaitStep: WaitStep? {
        guard body.count == 1 else { return nil }
        switch body[0] {
        case .wait(let step):
            return step
        case .action(let step):
            return step.expectation
        case .conditional, .forEachElement, .forEachString, .repeatUntil, .warn, .fail, .heist, .invoke:
            return nil
        }
    }
}
