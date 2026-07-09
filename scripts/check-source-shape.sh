#!/usr/bin/env bash
# Guard source-level API shape that Swift's API diff reports too late.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

python3 - "$REPO_ROOT" <<'PY'
import json
import pathlib
import re
import sys

repo_root = pathlib.Path(sys.argv[1])
source_roots = [
    repo_root / "ButtonHeist/Sources",
    repo_root / "ButtonHeistCLI/Sources",
    repo_root / "ButtonHeistMCP/Sources",
]
dsl_facade_path = repo_root / "ButtonHeist/Sources/ButtonHeistDSL/ButtonHeistDSL.swift"


def source_key(relative_path, declaration):
    return f"{relative_path}::{' '.join(declaration.split())}"


# These are unavoidable untyped system boundaries. Keys include the exact file
# and declaration so a second use in the same file is still rejected.
any_allowlist = {
    source_key(
        "ButtonHeist/Sources/TheInsideJob/Lifecycle/StartupConfiguration.swift",
        "static func value(from object: Any) -> InfoPlistValue {",
    ): "Foundation property-list objects are dynamically typed",
    source_key(
        "ButtonHeist/Sources/TheButtonHeist/Storage/PrivateStorage.swift",
        "private typealias FoundationFileAttributeDictionary = [FileAttributeKey: Any]",
    ): "FileManager's file-attribute dictionary is dynamically typed",
    source_key(
        "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandArguments.swift",
        "private static func expectedDescription(for type: Any.Type, fallback: String) -> String {",
    ): "DecodingError.typeMismatch exposes Any.Type",
}

# Each declaration documents its lock, queue, or actor ownership at the source.
unchecked_sendable_allowlist = {
    source_key(
        "ButtonHeist/Sources/TheButtonHeist/TheHandoff/DeviceDiscovery.swift",
        "final class NWDeviceDiscoveryBrowser: DeviceDiscoveryBrowsing, @unchecked Sendable {",
    ),
    source_key(
        "ButtonHeist/Sources/TheButtonHeist/TheHandoff/NetworkBoundary/DeviceConnectionFailures.swift",
        "final class TLSFailureTracker: @unchecked Sendable {",
    ),
    source_key(
        "ButtonHeist/Sources/TheInsideJob/TheTripwire/AccessibilityNotificationObserver.swift",
        "final class AccessibilityNotificationObserver: @unchecked Sendable {",
    ),
    source_key(
        "ButtonHeist/Sources/TheInsideJob/TheTripwire/AccessibilityNotificationObserver.swift",
        "private final class AccessibilityNotificationCallbackState: @unchecked Sendable {",
    ),
    source_key(
        "ButtonHeist/Sources/TheInsideJob/TheTripwire/AccessibilityNotificationBus.swift",
        "final class AccessibilityNotificationBus: @unchecked Sendable {",
    ),
    source_key(
        "ButtonHeist/Sources/TheInsideJob/TheTripwire/AccessibilityNotificationBus.swift",
        "final class AccessibilityNotificationHeistScope: @unchecked Sendable {",
    ),
    source_key(
        "ButtonHeist/Sources/TheInsideJob/TheTripwire/AccessibilityNotificationBus.swift",
        "final class AccessibilityNotificationActionWindow: @unchecked Sendable {",
    ),
    source_key(
        "ButtonHeist/Sources/TheInsideJob/Support/TaskTracker.swift",
        "final class TaskTracker: @unchecked Sendable {",
    ),
    source_key(
        "ButtonHeist/Sources/TheInsideJob/InsideJobLifecycleState.swift",
        "struct InsideJobRuntimeResources: Equatable, @unchecked Sendable {",
    ),
    source_key(
        "ButtonHeist/Sources/TheInsideJob/InsideJobLifecycleState.swift",
        "struct InsideJobStartAttempt: Equatable, @unchecked Sendable {",
    ),
    source_key(
        "ButtonHeist/Sources/TheInsideJob/InsideJobLifecycleState.swift",
        "struct InsideJobTransportStartRequest: Equatable, @unchecked Sendable {",
    ),
    source_key(
        "ButtonHeist/Sources/TheInsideJob/InsideJobLifecycleState.swift",
        "enum Effect: Equatable, @unchecked Sendable {",
    ),
    source_key(
        "ButtonHeist/Sources/TheInsideJob/Server/NetworkBoundary/SocketConnectionAdmission.swift",
        "final class ConnectionAdmission: @unchecked Sendable {",
    ),
    source_key(
        "ButtonHeist/Sources/TheInsideJob/Server/TransportEventStream.swift",
        "final class TransportEventStream: @unchecked Sendable {",
    ),
    source_key(
        "ButtonHeist/Sources/TheInsideJob/TheBrains/SettleTimeline.swift",
        "struct SettleRecordedObservation: Equatable, @unchecked Sendable {",
    ),
}

unsafe_nonisolated_allowlist = {
    source_key(
        "ButtonHeist/Sources/TheInsideJob/TheSafecracker/TheSafecracker+IOHIDEventBuilder.swift",
        declaration,
    )
    for declaration in (
        "nonisolated(unsafe) private var _IOHIDEventCreateDigitizerEvent:",
        "nonisolated(unsafe) private var _IOHIDEventCreateDigitizerFingerEventWithQuality:",
        "nonisolated(unsafe) private var _IOHIDEventAppendEvent:",
        "nonisolated(unsafe) private var _IOHIDEventSetFloatValue:",
        "nonisolated(unsafe) private var ioHIDFunctionsLoaded = false",
    )
}

# These caseless/nested value types are deliberately MainActor-bound because
# their values contain UIKit state. The declaration key keeps the exemption local.
main_actor_swiftlint_allowlist = {
    source_key(path, declaration)
    for path, declaration in (
        ("ButtonHeist/Sources/TheInsideJob/Support/UIScrollView+ProgrammaticScrollSafety.swift", "@MainActor enum ScrollViewHierarchySearch {"),
        ("ButtonHeist/Sources/TheInsideJob/TheSafecracker/TheSafecracker+IOHIDEventBuilder.swift", "@MainActor struct TouchEvent {"),
        ("ButtonHeist/Sources/TheInsideJob/Support/ScreenMetrics.swift", "@MainActor enum ScreenMetrics {"),
        ("ButtonHeist/Sources/TheInsideJob/Support/GeometryValidation.swift", "@MainActor enum GeometryValidation {"),
        ("ButtonHeist/Sources/TheInsideJob/TheSafecracker/SyntheticTouch.swift", "@MainActor struct TouchTarget {"),
        ("ButtonHeist/Sources/TheInsideJob/TheSafecracker/SyntheticTouch.swift", "@MainActor struct SyntheticTouch {"),
        ("ButtonHeist/Sources/TheInsideJob/TheSafecracker/KeyboardBridge.swift", "@MainActor struct KeyboardBridge {"),
        ("ButtonHeist/Sources/TheInsideJob/SafeGeometryHashing.swift", "@MainActor enum CoarseFrameComparison {"),
        ("ButtonHeist/Sources/TheInsideJob/TheStash/Interactivity.swift", "@MainActor enum Interactivity {"),
        ("ButtonHeist/Sources/TheInsideJob/TheBrains/PredicateWait.swift", "@MainActor internal struct PredicateWait {"),
        ("ButtonHeist/Sources/TheInsideJob/TheBrains/SettleTimeline.swift", "@MainActor struct SettleObservationLedger {"),
        ("ButtonHeist/Sources/TheInsideJob/TheBrains/SettleTimeline.swift", "@MainActor enum SettleTimeline {"),
        ("ButtonHeist/Sources/TheInsideJob/TheStash/WireConversion.swift", "@MainActor enum WireConversion {"),
        ("ButtonHeist/Sources/TheInsideJob/TheBrains/Navigation.swift", "@MainActor enum ScrollableTarget {"),
        ("ButtonHeist/Sources/TheInsideJob/TheBrains/SettleSession.swift", "@MainActor struct SettleSession {"),
        ("ButtonHeist/Sources/TheInsideJob/TheBrains/SettleSession.swift", "@MainActor struct SemanticQuietSettleSession {"),
        ("ButtonHeist/Sources/TheInsideJob/TheBrains/Navigation+ScrollContainers.swift", "@MainActor struct ScrollPlan {"),
        ("ButtonHeist/Sources/TheInsideJob/TheBrains/Navigation+ScrollContainers.swift", "@MainActor enum ContainerScrollResolution {"),
        ("ButtonHeist/Sources/TheInsideJob/TheBrains/ActionCapabilityDiagnostic.swift", "@MainActor enum ActionCapabilityDiagnostic {"),
        ("ButtonHeist/Sources/TheInsideJob/TheBrains/ScreenClassifier.swift", "@MainActor enum ScreenClassifier {"),
    )
}

other_swiftlint_allowlist = {
    source_key(
        "ButtonHeistCLI/Sources/Session/JSONLinesSession.swift",
        "swiftlint:disable:next agent_no_task_detached :: guard let line = await Task.detached(operation: { Swift.readLine() }).value else {",
    ),
    source_key(
        "ButtonHeist/Sources/ButtonHeistDSL/ButtonHeistDSL.swift",
        "swiftlint:disable identifier_name :: public func RunHeist(_ name: String) -> HeistInvocationContent {",
    ),
    source_key(
        "ButtonHeist/Sources/ThePlans/Model/HeistContent.swift",
        "swiftlint:disable identifier_name :: public func RunHeist(_ name: String) -> HeistInvocationContent {",
    ),
    source_key(
        "ButtonHeist/Sources/TheInsideJob/TheSafecracker/TheSafecracker+IOHIDEventBuilder.swift",
        "swiftlint:disable:next function_parameter_count :: private func IOHIDEventCreateDigitizerEvent(",
    ),
    source_key(
        "ButtonHeist/Sources/TheInsideJob/TheSafecracker/TheSafecracker+IOHIDEventBuilder.swift",
        "swiftlint:disable:next function_parameter_count :: private func IOHIDEventCreateDigitizerFingerEventWithQuality(",
    ),
}

access_pattern = re.compile(r"^\s*(public|package)\b")
top_level_typealias_pattern = re.compile(r"^\s*(public|package)\s+typealias\b")
top_level_selector_shortcut_pattern = re.compile(
    r"^\s*(public|package)\s+func\s+(predicateCandidates|minimumUniquePredicate)\b"
)
declaration_name_pattern = re.compile(r"\b(?:func|var|let|typealias)\s+`?([A-Za-z_][A-Za-z0-9_]*)`?")
api_declaration_pattern = re.compile(
    r"^\s*(?:(?:public|package|internal|private|fileprivate)\s+)?"
    r"(?:(?:static|class|mutating|nonmutating|final|required|convenience)\s+)*"
    r"(?:func|init|subscript|var|let|typealias)\b"
)
compatibility_name_pattern = re.compile(
    r"(^legacy|^compat(?!ible)|^compatibility|^deprecated|Legacy|Compat(?!ible)|Compatibility|Deprecated)"
)
explicit_access_required_files = {
    repo_root / "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceParameter.swift",
    repo_root / "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceParameter+Schema.swift",
    repo_root / "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceParameter+Decoding.swift",
    repo_root / "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceParameter+Factories.swift",
    repo_root / "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceParameterBlocks.swift",
    repo_root / "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+ParameterSpec.swift",
    repo_root / "ButtonHeist/Sources/ThePlans/Model/ElementPropertyKind.swift",
    repo_root / "ButtonHeist/Sources/ThePlans/Model/ElementPropertyMatches.swift",
    repo_root / "ButtonHeist/Sources/ThePlans/Model/ElementPropertyChange.swift",
    repo_root / "ButtonHeist/Sources/ThePlans/Model/ElementUpdatePredicate+AnyChange.swift",
    repo_root / "ButtonHeist/Sources/ThePlans/Model/ElementUpdatePredicate+Codable.swift",
    repo_root / "ButtonHeist/Sources/ThePlans/Model/ElementUpdatePredicate+Description.swift",
    repo_root / "ButtonHeist/Sources/ThePlans/Model/ElementUpdatePredicate.swift",
    repo_root / "ButtonHeist/Sources/TheInsideJob/TheBrains/ElementInflation.swift",
    repo_root / "ButtonHeist/Sources/TheInsideJob/TheBrains/ElementInflation+State.swift",
    repo_root / "ButtonHeist/Sources/TheInsideJob/TheBrains/ElementInflation+Resolution.swift",
    repo_root / "ButtonHeist/Sources/TheInsideJob/TheBrains/ElementInflation+Reveal.swift",
    repo_root / "ButtonHeist/Sources/TheInsideJob/TheBrains/ElementInflation+Geometry.swift",
    repo_root / "ButtonHeist/Sources/TheInsideJob/TheBrains/ElementInflation+Failures.swift",
    repo_root / "ButtonHeist/Sources/TheInsideJob/TheBrains/ElementInflation+FirstResponder.swift",
    repo_root / "ButtonHeist/Sources/TheInsideJob/TheBrains/PredicateWait.swift",
    repo_root / "ButtonHeist/Sources/TheInsideJob/TheBrains/PredicateWait+Reducer.swift",
    repo_root / "ButtonHeist/Sources/TheInsideJob/TheBrains/PredicateWait+ObservationStream.swift",
    repo_root / "ButtonHeist/Sources/TheInsideJob/TheBrains/PredicateWait+Polling.swift",
    repo_root / "ButtonHeist/Sources/TheInsideJob/TheBrains/PredicateWait+Evidence.swift",
    repo_root / "ButtonHeist/Sources/TheInsideJob/TheBrains/PredicateWait+Receipts.swift",
    repo_root / "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistExecution.swift",
    repo_root / "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistExecutionAccumulator.swift",
    repo_root / "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistInvocationExecution.swift",
    repo_root / "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistExecutionReceipts.swift",
    repo_root / "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistExecutionFailures.swift",
    repo_root / "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistRepeatUntilExecution.swift",
    repo_root / "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+RepeatUntilState.swift",
    repo_root / "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+RepeatUntilPredicateEvaluation.swift",
    repo_root / "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+RepeatUntilReceipts.swift",
    repo_root / "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+RepeatUntilFailures.swift",
}
explicit_access_declaration_pattern = re.compile(
    r"^\s*(?:@MainActor\s+)?(?:static\s+)?(?:final\s+)?(?:struct|enum|class|actor|protocol|func)\b"
)
explicit_access_pattern = re.compile(
    r"^\s*(?:@MainActor\s+)?(?:public|package|internal|private|fileprivate)\b"
)
string_literal_pattern = re.compile(r'"(?:\\.|[^"\\])*"')
leading_attribute_pattern = re.compile(
    r"^\s*(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?\s+)+"
)
attribute_only_pattern = re.compile(
    r"^\s*@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?\s*$"
)
swiftlint_disable_pattern = re.compile(
    r"//\s*swiftlint:disable(?::(?:next|this))?(?:\s|$)"
)


def strip_comments(lines):
    stripped_lines = []
    in_block = False
    for line in lines:
        stripped = []
        index = 0
        while index < len(line):
            if in_block:
                end = line.find("*/", index)
                if end == -1:
                    index = len(line)
                else:
                    in_block = False
                    index = end + 2
            elif line.startswith("/*", index):
                in_block = True
                index += 2
            elif line.startswith("//", index):
                break
            else:
                stripped.append(line[index])
                index += 1
        stripped_lines.append("".join(stripped))
    return stripped_lines


def strip_string_literals(lines):
    stripped_lines = []
    in_multiline_string = False
    for line in lines:
        stripped = []
        index = 0
        while index < len(line):
            delimiter = line.find('"""', index)
            if in_multiline_string:
                if delimiter == -1:
                    index = len(line)
                else:
                    in_multiline_string = False
                    index = delimiter + 3
            elif delimiter == -1:
                stripped.append(string_literal_pattern.sub('""', line[index:]))
                index = len(line)
            else:
                stripped.append(string_literal_pattern.sub('""', line[index:delimiter]))
                in_multiline_string = True
                index = delimiter + 3
        stripped_lines.append("".join(stripped))
    return stripped_lines


def collect_declaration(lines, start):
    parts = []
    callable_declaration = False
    for line in lines[start:start + 24]:
        stripped = line.strip()
        if not stripped:
            continue
        parts.append(stripped)
        declaration = " ".join(parts)
        callable_match = re.search(r"\b(?:func|init|subscript)\b", declaration)
        callable_declaration = callable_declaration or bool(callable_match)
        if callable_declaration and callable_match:
            open_index = declaration.find("(", callable_match.end())
            if open_index != -1 and matching_paren(declaration, open_index) is not None:
                break
        elif "{" in stripped or "=" in stripped:
            break
    return " ".join(parts)


def matching_paren(text, open_index):
    depth = 0
    for index in range(open_index, len(text)):
        if text[index] == "(":
            depth += 1
        elif text[index] == ")":
            depth -= 1
            if depth == 0:
                return index
    return None


def before_boundary(text):
    depth = 0
    for index, character in enumerate(text):
        if depth == 0 and character in "={":
            return text[:index]
        if character in "([{":
            depth += 1
        elif character in ")]}":
            depth = max(0, depth - 1)
    return text


def is_tuple_group(text, open_index):
    close_index = matching_paren(text, open_index)
    if close_index is None:
        return False
    if text[close_index + 1:].lstrip().startswith("->"):
        return False

    content = text[open_index + 1:close_index]
    depth = 0
    has_comma = False
    has_top_level_arrow = False
    index = 0
    while index < len(content):
        character = content[index]
        if character in "([{":
            depth += 1
        elif character in ")]}":
            depth = max(0, depth - 1)
        elif depth == 0:
            if content.startswith("->", index):
                has_top_level_arrow = True
                index += 1
            elif character == ",":
                has_comma = True
        index += 1
    return has_comma and not has_top_level_arrow


def contains_tuple_type(text):
    return any(
        is_tuple_group(text, index)
        for index, character in enumerate(text)
        if character == "("
    )


def split_top_level(text, delimiter):
    parts = []
    start = 0
    depth = 0
    for index, character in enumerate(text):
        if character in "([{<":
            depth += 1
        elif character in ")]}>":
            depth = max(0, depth - 1)
        elif depth == 0 and character == delimiter:
            parts.append(text[start:index])
            start = index + 1
    parts.append(text[start:])
    return parts


def top_level_suffix(text, delimiter):
    parts = split_top_level(text, delimiter)
    return None if len(parts) == 1 else delimiter.join(parts[1:])


def function_parameter_types(declaration):
    match = re.search(r"\b(?:func|init|subscript)\b", declaration)
    if not match:
        return []

    open_index = declaration.find("(", match.end())
    if open_index == -1:
        return []
    close_index = matching_paren(declaration, open_index)
    if close_index is None:
        return []

    parameter_types = []
    for parameter in split_top_level(declaration[open_index + 1:close_index], ","):
        parameter_type = top_level_suffix(parameter, ":")
        if parameter_type is not None:
            parameter_types.append(split_top_level(parameter_type, "=")[0])
    return parameter_types


def function_return_type(declaration):
    match = re.search(r"\b(?:func|subscript)\b", declaration)
    if not match:
        return None

    open_index = declaration.find("(", match.end())
    if open_index == -1:
        return None
    close_index = matching_paren(declaration, open_index)
    if close_index is None:
        return None

    tail = before_boundary(declaration[close_index + 1:])
    arrow_index = tail.find("->")
    return None if arrow_index == -1 else tail[arrow_index + 2:]


def property_type(declaration):
    match = re.search(r"\b(?:let|var)\s+`?[A-Za-z_][A-Za-z0-9_]*`?\s*:", declaration)
    return None if not match else before_boundary(declaration[match.end():])


def typealias_type(declaration):
    match = re.search(r"\btypealias\s+`?[A-Za-z_][A-Za-z0-9_]*`?[^=]*=", declaration)
    return None if not match else before_boundary(declaration[match.end():])


def is_dsl_facade_alias(path, declaration):
    if path != dsl_facade_path:
        return False
    match = re.match(
        r"^public\s+typealias\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*ThePlans\.([A-Za-z_][A-Za-z0-9_]*)$",
        declaration.strip(),
    )
    return bool(match and match.group(1) == match.group(2))


def declaration_source_key(repo_root, path, declaration):
    return source_key(str(path.relative_to(repo_root)), declaration)


def swiftlint_directive_key(repo_root, path, raw_lines, code_lines, index):
    raw_line = raw_lines[index]
    directive = raw_line[raw_line.index("swiftlint:disable"):].strip()
    anchor = code_lines[index].strip()
    if not anchor:
        anchor = next((line.strip() for line in code_lines[index + 1:] if line.strip()), "<end-of-file>")
    return declaration_source_key(repo_root, path, f"{directive} :: {anchor}"), anchor


violations = []
for source_root in source_roots:
    for path in sorted(source_root.rglob("*.swift")):
        raw_lines = path.read_text().splitlines()
        lines = strip_comments(raw_lines)
        token_lines = strip_string_literals(lines)
        depth = 0
        protocol_depths = []
        access_qualified_extension_depths = []
        exported_protocol_depths = []
        exported_extension_depths = []
        pending_compatibility_attribute = None

        for index, line in enumerate(lines):
            stripped = line.strip()
            token_line = token_lines[index]
            declaration_line = leading_attribute_pattern.sub("", line)
            line_number = index + 1
            display_line = raw_lines[index].strip()
            protocol_depths = [protocol_depth for protocol_depth in protocol_depths if depth > protocol_depth]
            access_qualified_extension_depths = [
                extension_depth for extension_depth in access_qualified_extension_depths if depth > extension_depth
            ]
            exported_protocol_depths = [
                protocol_depth for protocol_depth in exported_protocol_depths if depth > protocol_depth
            ]
            exported_extension_depths = [
                extension_depth for extension_depth in exported_extension_depths if depth > extension_depth
            ]
            inside_protocol = bool(protocol_depths)
            inside_access_qualified_extension = bool(access_qualified_extension_depths)
            inherits_exported_access = any(
                depth == owner_depth + 1
                for owner_depth in [*exported_protocol_depths, *exported_extension_depths]
            )

            relative_path = str(path.relative_to(repo_root))
            line_key = declaration_source_key(repo_root, path, line)
            if swiftlint_disable_pattern.search(raw_lines[index]):
                directive_key, anchor = swiftlint_directive_key(repo_root, path, raw_lines, lines, index)
                anchor_key = source_key(relative_path, anchor)
                directive = raw_lines[index][raw_lines[index].index("swiftlint:disable"):]
                is_allowed = (
                    directive_key in other_swiftlint_allowlist
                    or (
                        "agent_unchecked_sendable_no_comment" in directive
                        and anchor_key in unchecked_sendable_allowlist
                    )
                    or (
                        "agent_main_actor_value_type" in directive
                        and anchor_key in main_actor_swiftlint_allowlist
                    )
                )
                if not is_allowed:
                    violations.append((path, line_number, "unallowlisted swiftlint:disable", display_line))

            if "@unchecked Sendable" in token_line and line_key not in unchecked_sendable_allowlist:
                violations.append((path, line_number, "unallowlisted @unchecked Sendable", display_line))
            if "nonisolated(unsafe)" in token_line and line_key not in unsafe_nonisolated_allowlist:
                violations.append((path, line_number, "unallowlisted nonisolated(unsafe)", display_line))
            if re.search(r"\bAny\b", token_line) and line_key not in any_allowlist:
                violations.append((path, line_number, "unallowlisted Any type", display_line))

            if stripped.startswith("@available") and any(
                marker in stripped for marker in ("deprecated", "obsoleted:", "renamed:")
            ):
                pending_compatibility_attribute = (line_number, display_line)
                continue
            if attribute_only_pattern.match(line):
                continue

            if (
                path in explicit_access_required_files
                and depth <= 1
                and not inside_protocol
                and not inside_access_qualified_extension
                and explicit_access_declaration_pattern.match(declaration_line)
                and not explicit_access_pattern.match(declaration_line)
            ):
                violations.append((path, line_number, "implicit access in owner-scoped pipeline file", display_line))

            if depth == 0 and top_level_typealias_pattern.match(declaration_line):
                declaration = collect_declaration(lines, index)
                if not is_dsl_facade_alias(path, declaration):
                    violations.append((path, line_number, "exported top-level typealias outside canonical ButtonHeistDSL facade", display_line))
            if depth == 0 and top_level_selector_shortcut_pattern.match(declaration_line):
                violations.append((path, line_number, "exported top-level minimum predicate selector shortcut", display_line))

            explicitly_nonexported = bool(re.match(r"^\s*(?:internal|private|fileprivate)\b", declaration_line))
            is_exported_declaration = bool(
                api_declaration_pattern.match(declaration_line)
                and (
                    access_pattern.match(declaration_line)
                    or (inherits_exported_access and not explicitly_nonexported)
                )
            )
            if is_exported_declaration:
                declaration = collect_declaration(lines, index)
                declaration_name = declaration_name_pattern.search(declaration)
                return_type = function_return_type(declaration)
                stored_type = property_type(declaration)
                alias_type = typealias_type(declaration)
                parameter_types = function_parameter_types(declaration)

                if pending_compatibility_attribute is not None:
                    violations.append((path, line_number, "exported compatibility/legacy helper", display_line))
                    pending_compatibility_attribute = None
                if declaration_name and compatibility_name_pattern.search(declaration_name.group(1)):
                    violations.append((path, line_number, "exported compatibility/legacy helper name", display_line))
                if any(
                    contains_tuple_type(candidate)
                    for candidate in [return_type, stored_type, alias_type, *parameter_types]
                    if candidate is not None
                ):
                    violations.append((path, line_number, "exported tuple API", display_line))
            elif stripped:
                pending_compatibility_attribute = None

            if re.match(r"^\s*(?:public|package|internal|private|fileprivate)?\s*protocol\b", declaration_line):
                protocol_depths.append(depth)
            if re.match(r"^\s*(?:public|package)\s+protocol\b", declaration_line):
                exported_protocol_depths.append(depth)
            if re.match(r"^\s*(?:public|package|internal|private|fileprivate)\s+extension\b", declaration_line):
                access_qualified_extension_depths.append(depth)
            if re.match(r"^\s*(?:public|package)\s+extension\b", declaration_line):
                exported_extension_depths.append(depth)
            depth += token_line.count("{") - token_line.count("}")
            depth = max(0, depth)

if violations:
    for path, line_number, reason, line in violations:
        relative_path = path.relative_to(repo_root)
        print(f"{relative_path}:{line_number}: {reason}: {line}", file=sys.stderr)
    sys.exit(1)

fixture_violations = []
fixture_root = repo_root / "tests/fixtures"


def scan_json_fixture(value, path, trail):
    if isinstance(value, dict):
        for key, child in value.items():
            child_trail = [*trail, key]
            if key == "match" and isinstance(child, str):
                fixture_violations.append((path, ".".join(child_trail), child))
            scan_json_fixture(child, path, child_trail)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            scan_json_fixture(child, path, [*trail, f"[{index}]"])


if fixture_root.exists():
    for path in sorted(fixture_root.rglob("*.json")):
        try:
            scan_json_fixture(json.loads(path.read_text()), path, [])
        except json.JSONDecodeError as error:
            relative_path = path.relative_to(repo_root)
            print(f"{relative_path}: invalid JSON fixture: {error}", file=sys.stderr)
            sys.exit(1)

if fixture_violations:
    for path, trail, observed in fixture_violations:
        relative_path = path.relative_to(repo_root)
        print(
            f"{relative_path}: raw StringMatch fixture value at {trail}: {observed!r}; "
            'use {"mode":"exact","value":...}',
            file=sys.stderr,
        )
    sys.exit(1)
PY
