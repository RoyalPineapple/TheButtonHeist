#!/usr/bin/env bash
# Guard source-level house rules that the compiler and API diff do not own.

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


def source_key(path, line):
    return f"{path}::{' '.join(line.split())}"


any_allowlist = {
    source_key("ButtonHeist/Sources/TheInsideJob/Lifecycle/StartupConfiguration.swift", "static func value(from object: Any) -> InfoPlistValue {"),
    source_key("ButtonHeist/Sources/TheButtonHeist/Storage/PrivateStorage.swift", "private typealias FoundationFileAttributeDictionary = [FileAttributeKey: Any]"),
    source_key("ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandArguments.swift", "private static func expectedDescription(for type: Any.Type, fallback: String) -> String {"),
}

unchecked_sendable_allowlist = {
    source_key(path, declaration)
    for path, declaration in (
        ("ButtonHeist/Sources/TheInsideJob/TheTripwire/AccessibilityNotificationObserver.swift", "final class AccessibilityNotificationObserver: @unchecked Sendable {"),
        ("ButtonHeist/Sources/TheInsideJob/TheTripwire/AccessibilityNotificationObserver.swift", "private final class AccessibilityNotificationCallbackState: @unchecked Sendable {"),
        ("ButtonHeist/Sources/TheInsideJob/TheTripwire/AccessibilityNotificationBus.swift", "final class AccessibilityNotificationBus: @unchecked Sendable {"),
        ("ButtonHeist/Sources/TheInsideJob/TheTripwire/AccessibilityNotificationBus.swift", "final class AccessibilityNotificationHeistScope: @unchecked Sendable {"),
        ("ButtonHeist/Sources/TheInsideJob/TheTripwire/AccessibilityNotificationBus.swift", "final class AccessibilityNotificationActionWindow: @unchecked Sendable {"),
        ("ButtonHeist/Sources/TheInsideJob/Support/TaskTracker.swift", "final class TaskTracker: @unchecked Sendable {"),
        ("ButtonHeist/Sources/TheInsideJob/InsideJobLifecycleState.swift", "struct InsideJobRuntimeResources: Equatable, @unchecked Sendable {"),
        ("ButtonHeist/Sources/TheInsideJob/InsideJobLifecycleState.swift", "struct InsideJobStartAttempt: Equatable, @unchecked Sendable {"),
        ("ButtonHeist/Sources/TheInsideJob/InsideJobLifecycleState.swift", "struct InsideJobTransportStartRequest: Equatable, @unchecked Sendable {"),
        ("ButtonHeist/Sources/TheInsideJob/InsideJobLifecycleState.swift", "enum Effect: Equatable, @unchecked Sendable {"),
        ("ButtonHeist/Sources/TheInsideJob/Server/NetworkBoundary/SocketConnectionAdmission.swift", "final class ConnectionAdmission: @unchecked Sendable {"),
        ("ButtonHeist/Sources/TheInsideJob/Server/TransportEventStream.swift", "final class TransportEventStream: @unchecked Sendable {"),
        ("ButtonHeist/Sources/TheInsideJob/TheBrains/SettleTimeline.swift", "struct SettleRecordedObservation: Equatable, @unchecked Sendable {"),
    )
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

swiftlint_allowlist = {
    source_key(path, line)
    for path, line in (
        ("ButtonHeistCLI/Sources/Session/JSONLinesSession.swift", "// swiftlint:disable:next agent_no_task_detached"),
        ("ButtonHeist/Sources/ButtonHeistDSL/ButtonHeistDSL.swift", "// swiftlint:disable identifier_name"),
        ("ButtonHeist/Sources/ThePlans/Model/HeistContent.swift", "// swiftlint:disable identifier_name"),
        ("ButtonHeist/Sources/TheInsideJob/TheSafecracker/TheSafecracker+IOHIDEventBuilder.swift", "// swiftlint:disable:next function_parameter_count"),
        ("ButtonHeist/Sources/TheInsideJob/TheBrains/SettleTimeline.swift", "// swiftlint:disable:next agent_unchecked_sendable_no_comment"),
        ("ButtonHeist/Sources/TheInsideJob/TheTripwire/AccessibilityNotificationObserver.swift", "// swiftlint:disable:next agent_unchecked_sendable_no_comment"),
        ("ButtonHeist/Sources/TheInsideJob/TheSafecracker/TheSafecracker+IOHIDEventBuilder.swift", "@MainActor struct TouchEvent { // swiftlint:disable:this agent_main_actor_value_type"),
        ("ButtonHeist/Sources/TheInsideJob/TheSafecracker/SyntheticTouch.swift", "@MainActor struct TouchTarget { // swiftlint:disable:this agent_main_actor_value_type"),
        ("ButtonHeist/Sources/TheInsideJob/TheSafecracker/SyntheticTouch.swift", "@MainActor struct SyntheticTouch { // swiftlint:disable:this agent_main_actor_value_type"),
        ("ButtonHeist/Sources/TheInsideJob/Support/UIScrollView+ProgrammaticScrollSafety.swift", "@MainActor enum ScrollViewHierarchySearch { // swiftlint:disable:this agent_main_actor_value_type"),
        ("ButtonHeist/Sources/TheInsideJob/Support/ScreenMetrics.swift", "@MainActor enum ScreenMetrics { // swiftlint:disable:this agent_main_actor_value_type"),
        ("ButtonHeist/Sources/TheInsideJob/Support/GeometryValidation.swift", "@MainActor enum GeometryValidation { // swiftlint:disable:this agent_main_actor_value_type"),
        ("ButtonHeist/Sources/TheInsideJob/TheSafecracker/KeyboardBridge.swift", "@MainActor struct KeyboardBridge { // swiftlint:disable:this agent_main_actor_value_type"),
        ("ButtonHeist/Sources/TheInsideJob/TheBrains/PredicateWait.swift", "@MainActor internal struct PredicateWait { // swiftlint:disable:this agent_main_actor_value_type"),
        ("ButtonHeist/Sources/TheInsideJob/TheBrains/SettleTimeline.swift", "@MainActor struct SettleObservationLedger { // swiftlint:disable:this agent_main_actor_value_type"),
        ("ButtonHeist/Sources/TheInsideJob/TheBrains/SettleTimeline.swift", "@MainActor enum SettleTimeline { // swiftlint:disable:this agent_main_actor_value_type"),
        ("ButtonHeist/Sources/TheInsideJob/SafeGeometryHashing.swift", "@MainActor enum CoarseFrameComparison { // swiftlint:disable:this agent_main_actor_value_type"),
        ("ButtonHeist/Sources/TheInsideJob/TheStash/Interactivity.swift", "@MainActor enum Interactivity { // swiftlint:disable:this agent_main_actor_value_type"),
        ("ButtonHeist/Sources/TheInsideJob/TheBrains/SettleSession.swift", "@MainActor struct SettleSession { // swiftlint:disable:this agent_main_actor_value_type"),
        ("ButtonHeist/Sources/TheInsideJob/TheBrains/SettleSession.swift", "@MainActor struct SemanticQuietSettleSession { // swiftlint:disable:this agent_main_actor_value_type"),
        ("ButtonHeist/Sources/TheInsideJob/TheBrains/Navigation+ScrollContainers.swift", "@MainActor struct ScrollPlan { // swiftlint:disable:this agent_main_actor_value_type"),
        ("ButtonHeist/Sources/TheInsideJob/TheBrains/Navigation+ScrollContainers.swift", "@MainActor enum ContainerScrollResolution { // swiftlint:disable:this agent_main_actor_value_type"),
        ("ButtonHeist/Sources/TheInsideJob/TheBrains/Navigation.swift", "@MainActor enum ScrollableTarget { // swiftlint:disable:this agent_main_actor_value_type"),
        ("ButtonHeist/Sources/TheInsideJob/TheBrains/ActionCapabilityDiagnostic.swift", "@MainActor enum ActionCapabilityDiagnostic { // swiftlint:disable:this agent_main_actor_value_type"),
        ("ButtonHeist/Sources/TheInsideJob/TheBrains/ScreenClassifier.swift", "@MainActor enum ScreenClassifier { // swiftlint:disable:this agent_main_actor_value_type"),
        ("ButtonHeist/Sources/TheInsideJob/TheStash/WireConversion.swift", "@MainActor enum WireConversion { // swiftlint:disable:this agent_main_actor_value_type"),
        ("ButtonHeist/Sources/TheInsideJob/Support/TaskTracker.swift", "final class TaskTracker: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment"),
        ("ButtonHeist/Sources/TheInsideJob/InsideJobLifecycleState.swift", "struct InsideJobRuntimeResources: Equatable, @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment"),
        ("ButtonHeist/Sources/TheInsideJob/InsideJobLifecycleState.swift", "struct InsideJobStartAttempt: Equatable, @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment"),
        ("ButtonHeist/Sources/TheInsideJob/InsideJobLifecycleState.swift", "struct InsideJobTransportStartRequest: Equatable, @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment"),
        ("ButtonHeist/Sources/TheInsideJob/InsideJobLifecycleState.swift", "enum Effect: Equatable, @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment"),
        ("ButtonHeist/Sources/TheInsideJob/Server/NetworkBoundary/SocketConnectionAdmission.swift", "final class ConnectionAdmission: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment"),
        ("ButtonHeist/Sources/TheInsideJob/Server/TransportEventStream.swift", "final class TransportEventStream: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment"),
        ("ButtonHeist/Sources/TheInsideJob/TheTripwire/AccessibilityNotificationBus.swift", "final class AccessibilityNotificationBus: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment"),
        ("ButtonHeist/Sources/TheInsideJob/TheTripwire/AccessibilityNotificationBus.swift", "final class AccessibilityNotificationHeistScope: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment"),
        ("ButtonHeist/Sources/TheInsideJob/TheTripwire/AccessibilityNotificationBus.swift", "final class AccessibilityNotificationActionWindow: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment"),
    )
}

access_pattern = re.compile(r"^\s*(public|package)\b")
top_level_typealias_pattern = re.compile(r"^\s*(public|package)\s+typealias\b")
top_level_selector_shortcut_pattern = re.compile(
    r"^\s*(public|package)\s+func\s+(predicateCandidates|minimumUniquePredicate)\b"
)
declaration_name_pattern = re.compile(r"\b(?:func|var|let|typealias)\s+`?([A-Za-z_][A-Za-z0-9_]*)`?")
compatibility_name_pattern = re.compile(
    r"(^legacy|^compat(?!ible)|^compatibility|^deprecated|Legacy|Compat(?!ible)|Compatibility|Deprecated)"
)
explicit_access_files = {
    "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceParameter.swift",
    "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceParameter+Schema.swift",
    "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceParameter+Decoding.swift",
    "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceParameter+Factories.swift",
    "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceParameterBlocks.swift",
    "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+ParameterSpec.swift",
    "ButtonHeist/Sources/ThePlans/Model/ElementPropertyKind.swift",
    "ButtonHeist/Sources/ThePlans/Model/ElementPropertyMatches.swift",
    "ButtonHeist/Sources/ThePlans/Model/ElementPropertyChange.swift",
    "ButtonHeist/Sources/ThePlans/Model/ElementUpdatePredicate+AnyChange.swift",
    "ButtonHeist/Sources/ThePlans/Model/ElementUpdatePredicate+Codable.swift",
    "ButtonHeist/Sources/ThePlans/Model/ElementUpdatePredicate+Description.swift",
    "ButtonHeist/Sources/ThePlans/Model/ElementUpdatePredicate.swift",
}
for stem, suffixes in (
    ("ElementInflation", ("", "+State", "+Resolution", "+Reveal", "+Geometry", "+Failures", "+FirstResponder")),
    ("PredicateWait", ("", "+Reducer", "+ObservationStream", "+Polling", "+Evidence", "+Receipts")),
    ("TheBrains+HeistExecution", ("", "+Accumulator", "+InvocationExecution", "+Receipts", "+Failures")),
    ("TheBrains+RepeatUntil", ("State", "PredicateEvaluation", "Receipts", "Failures")),
):
    explicit_access_files.update(
        f"ButtonHeist/Sources/TheInsideJob/TheBrains/{stem}{suffix}.swift"
        for suffix in suffixes
    )
explicit_access_declaration_pattern = re.compile(
    r"^\s*(?:@MainActor\s+)?(?:static\s+)?(?:final\s+)?(?:struct|enum|class|actor|protocol|func)\b"
)
explicit_access_pattern = re.compile(
    r"^\s*(?:@MainActor\s+)?(?:public|package|internal|private|fileprivate)\b"
)
string_literal_pattern = re.compile(r'"(?:\\.|[^"\\])*"')
swiftlint_disable_pattern = re.compile(r"//\s*swiftlint:disable(?::(?:next|this))?(?:\s|$)")


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


def strip_strings(lines):
    result = []
    in_multiline = False
    for line in lines:
        output = []
        index = 0
        while index < len(line):
            delimiter = line.find('"""', index)
            if in_multiline:
                if delimiter == -1:
                    index = len(line)
                else:
                    in_multiline = False
                    index = delimiter + 3
            elif delimiter == -1:
                output.append(string_literal_pattern.sub('""', line[index:]))
                index = len(line)
            else:
                output.append(string_literal_pattern.sub('""', line[index:delimiter]))
                in_multiline = True
                index = delimiter + 3
        result.append("".join(output))
    return result


def collect_declaration(lines, start):
    parts = []
    for line in lines[start:start + 16]:
        stripped = line.strip()
        if not stripped:
            continue
        parts.append(stripped)
        if "{" in stripped or "=" in stripped:
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
        if character in "([{":
            depth += 1
        elif character in ")]}":
            depth = max(0, depth - 1)
        elif depth == 0 and character in "={":
            return text[:index]
    return text


def is_tuple_type(text):
    text = text.strip()
    if not text.startswith("("):
        return False
    close_index = matching_paren(text, 0)
    if close_index is None or text[close_index + 1:].lstrip().startswith("->"):
        return False
    content = text[1:close_index]
    return "," in content or ":" in content


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


def is_dsl_facade_alias(path, declaration):
    if path != dsl_facade_path:
        return False
    match = re.match(
        r"^public\s+typealias\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*ThePlans\.([A-Za-z_][A-Za-z0-9_]*)$",
        declaration.strip(),
    )
    return bool(match and match.group(1) == match.group(2))


def requires_explicit_access(relative_path):
    return relative_path in explicit_access_files


violations = []
for source_root in source_roots:
    for path in sorted(source_root.rglob("*.swift")):
        raw_lines = path.read_text().splitlines()
        lines = strip_comments(raw_lines)
        token_lines = strip_strings(lines)
        relative_path = str(path.relative_to(repo_root))
        depth = 0
        protocol_depths = []
        extension_depths = []
        pending_deprecated = None

        for index, line in enumerate(lines):
            stripped = line.strip()
            token_line = token_lines[index]
            line_number = index + 1
            display_line = raw_lines[index].strip()
            line_key = source_key(relative_path, line)
            protocol_depths = [owner for owner in protocol_depths if depth > owner]
            extension_depths = [owner for owner in extension_depths if depth > owner]

            if swiftlint_disable_pattern.search(raw_lines[index]):
                directive_key = source_key(relative_path, raw_lines[index])
                if directive_key not in swiftlint_allowlist:
                    violations.append((path, line_number, "unallowlisted swiftlint:disable", display_line))
            if re.search(r"\bAny\b", token_line) and line_key not in any_allowlist:
                violations.append((path, line_number, "unallowlisted Any type", display_line))
            if "@unchecked Sendable" in token_line and line_key not in unchecked_sendable_allowlist:
                violations.append((path, line_number, "unallowlisted @unchecked Sendable", display_line))
            if "nonisolated(unsafe)" in token_line and line_key not in unsafe_nonisolated_allowlist:
                violations.append((path, line_number, "unallowlisted nonisolated(unsafe)", display_line))

            if stripped.startswith("@available") and "deprecated" in stripped:
                pending_deprecated = (line_number, display_line)
                continue
            spi_extension = re.match(
                r"^\s*@_spi\([^)]*\)\s+(?:public|package|internal|private|fileprivate)\s+extension\b",
                line,
            )
            if stripped.startswith("@") and not spi_extension and " swiftlint:disable:this " not in raw_lines[index]:
                continue

            if (
                requires_explicit_access(relative_path)
                and depth <= 1
                and not protocol_depths
                and not extension_depths
                and explicit_access_declaration_pattern.match(line)
                and not explicit_access_pattern.match(line)
            ):
                violations.append((path, line_number, "implicit access in owner-scoped pipeline file", display_line))

            if depth == 0 and top_level_typealias_pattern.match(line):
                declaration = collect_declaration(lines, index)
                if not is_dsl_facade_alias(path, declaration):
                    violations.append((path, line_number, "exported top-level typealias outside canonical ButtonHeistDSL facade", display_line))
            if depth == 0 and top_level_selector_shortcut_pattern.match(line):
                violations.append((path, line_number, "exported top-level minimum predicate selector shortcut", display_line))

            if access_pattern.match(line):
                declaration = collect_declaration(lines, index)
                declaration_name = declaration_name_pattern.search(declaration)
                return_type = function_return_type(declaration)
                stored_type = property_type(declaration)
                if pending_deprecated is not None:
                    violations.append((path, line_number, "exported compatibility/legacy helper", display_line))
                    pending_deprecated = None
                if declaration_name and compatibility_name_pattern.search(declaration_name.group(1)):
                    violations.append((path, line_number, "exported compatibility/legacy helper name", display_line))
                if return_type and is_tuple_type(return_type):
                    violations.append((path, line_number, "exported tuple return type", display_line))
                if stored_type and is_tuple_type(stored_type):
                    violations.append((path, line_number, "exported tuple property type", display_line))
            elif stripped:
                pending_deprecated = None

            if re.match(r"^\s*(?:public|package|internal|private|fileprivate)?\s*protocol\b", line):
                protocol_depths.append(depth)
            if re.match(
                r"^\s*(?:@_spi\([^)]*\)\s+)?(?:public|package|internal|private|fileprivate)\s+extension\b",
                line,
            ):
                extension_depths.append(depth)
            depth = max(0, depth + token_line.count("{") - token_line.count("}"))

if violations:
    for path, line_number, reason, line in violations:
        print(f"{path.relative_to(repo_root)}:{line_number}: {reason}: {line}", file=sys.stderr)
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
            print(f"{path.relative_to(repo_root)}: invalid JSON fixture: {error}", file=sys.stderr)
            sys.exit(1)

if fixture_violations:
    for path, trail, observed in fixture_violations:
        print(
            f"{path.relative_to(repo_root)}: raw StringMatch fixture value at {trail}: {observed!r}; "
            'use {"mode":"exact","value":...}',
            file=sys.stderr,
        )
    sys.exit(1)
PY
