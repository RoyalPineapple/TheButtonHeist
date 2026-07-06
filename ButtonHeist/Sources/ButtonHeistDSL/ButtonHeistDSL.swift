import ThePlans

// MARK: - Authoring Root

public typealias HeistPlan = ThePlans.HeistPlan
public typealias HeistContent = ThePlans.HeistContent
public typealias HeistBuilder = ThePlans.HeistBuilder
public typealias HeistPlanBuildError = ThePlans.HeistPlanBuildError

// MARK: - Values And References

public typealias HeistReferenceName = ThePlans.HeistReferenceName
public typealias HeistArgument = ThePlans.HeistArgument
public typealias StringExpr = ThePlans.StringExpr
public typealias StringMatch = ThePlans.StringMatch
public typealias StringMatchPayload = ThePlans.StringMatchPayload

// MARK: - Targets And Predicates

public typealias HeistTrait = ThePlans.HeistTrait
public typealias ElementTarget = ThePlans.ElementTarget
public typealias ElementTargetExpr = ThePlans.ElementTargetExpr
public typealias ElementPredicate = ThePlans.ElementPredicate
public typealias ElementPredicateTemplate = ThePlans.ElementPredicateTemplate
public typealias ElementPredicateCheck = ThePlans.ElementPredicateCheck
public typealias AccessibilityPredicate = ThePlans.AccessibilityPredicate
public typealias AccessibilityPredicateExpr = ThePlans.AccessibilityPredicateExpr
public typealias StatePredicateExpr = ThePlans.StatePredicateExpr
public typealias ChangePredicateExpr = ThePlans.ChangePredicateExpr
public typealias ChangeScopePredicateExpr = ThePlans.ChangeScopePredicateExpr
public typealias ElementDeltaPredicate = ThePlans.ElementDeltaPredicate
public typealias ElementDeltaPredicateExpr = ThePlans.ElementDeltaPredicateExpr
public typealias ElementUpdatePredicate = ThePlans.ElementUpdatePredicate
public typealias ElementUpdatePredicateExpr = ThePlans.ElementUpdatePredicateExpr

// MARK: - Actions

public typealias Activate = ThePlans.Activate
public typealias Increment = ThePlans.Increment
public typealias Decrement = ThePlans.Decrement
public typealias TypeText = ThePlans.TypeText
public typealias ClearText = ThePlans.ClearText
public typealias CustomAction = ThePlans.CustomAction
public typealias Rotor = ThePlans.Rotor
public typealias SetPasteboard = ThePlans.SetPasteboard
public typealias TakeScreenshot = ThePlans.TakeScreenshot
public typealias Edit = ThePlans.Edit
public typealias DismissKeyboard = ThePlans.DismissKeyboard
public typealias ScreenActions = ThePlans.ScreenActions
public typealias Mechanical = ThePlans.Mechanical

public typealias EditAction = ThePlans.EditAction
public typealias RotorDirection = ThePlans.RotorDirection
public typealias RotorSelection = ThePlans.RotorSelection
public typealias GestureDuration = ThePlans.GestureDuration
public typealias ScreenPoint = ThePlans.ScreenPoint
public typealias UnitPoint = ThePlans.UnitPoint
public typealias SwipeDirection = ThePlans.SwipeDirection

// MARK: - Control Flow

public typealias WaitFor = ThePlans.WaitFor
public typealias RepeatUntil = ThePlans.RepeatUntil
public typealias If = ThePlans.If
public typealias Case = ThePlans.Case
public typealias Else = ThePlans.Else
public typealias Warn = ThePlans.Warn
public typealias Fail = ThePlans.Fail
public typealias ForEach = ThePlans.ForEach
public typealias HeistDef = ThePlans.HeistDef
public typealias HeistInvocationContent = ThePlans.HeistInvocationContent
public typealias HeistDefinitionPath = ThePlans.HeistDefinitionPath
public typealias HeistInvocationPath = ThePlans.HeistInvocationPath

public let immediateTimeout = ThePlans.immediateTimeout
public let defaultWaitTimeout = ThePlans.defaultWaitTimeout
public let defaultActionExpectationTimeout = ThePlans.defaultActionExpectationTimeout

// MARK: - Invocation

// RunHeist is the canonical authoring spelling emitted by the DSL renderer.
// swiftlint:disable identifier_name
public func RunHeist(_ name: String) -> HeistInvocationContent {
    ThePlans.RunHeist(name)
}

public func RunHeist(_ path: HeistInvocationPath) -> HeistInvocationContent {
    ThePlans.RunHeist(path)
}

public func RunHeist(_ name: String, _ input: String) -> HeistInvocationContent {
    ThePlans.RunHeist(name, input)
}

public func RunHeist(_ path: HeistInvocationPath, _ input: String) -> HeistInvocationContent {
    ThePlans.RunHeist(path, input)
}

public func RunHeist(_ name: String, _ input: StringExpr) -> HeistInvocationContent {
    ThePlans.RunHeist(name, input)
}

public func RunHeist(_ path: HeistInvocationPath, _ input: StringExpr) -> HeistInvocationContent {
    ThePlans.RunHeist(path, input)
}

@_disfavoredOverload
public func RunHeist(_ name: String, _ input: ElementTarget) -> HeistInvocationContent {
    ThePlans.RunHeist(name, input)
}

@_disfavoredOverload
public func RunHeist(_ path: HeistInvocationPath, _ input: ElementTarget) -> HeistInvocationContent {
    ThePlans.RunHeist(path, input)
}

public func RunHeist(_ name: String, _ input: ElementTargetExpr) -> HeistInvocationContent {
    ThePlans.RunHeist(name, input)
}

public func RunHeist(_ path: HeistInvocationPath, _ input: ElementTargetExpr) -> HeistInvocationContent {
    ThePlans.RunHeist(path, input)
}
// swiftlint:enable identifier_name
