#!/usr/bin/env bash
# Reject retired dynamic/compatibility shapes in Swift code.

set -euo pipefail

CODE_PATHS=(
  ButtonHeist/Sources
  ButtonHeist/Tests
  ButtonHeistCLI/Sources
  ButtonHeistCLI/Tests
  ButtonHeistMCP/Sources
  ButtonHeistMCP/Tests
  Project.swift
  Package.swift
)

SOURCE_PATHS=(
  ButtonHeist/Sources
  ButtonHeistCLI/Sources
  ButtonHeistMCP/Sources
)

TOOL_SOURCE_PATHS=(
  ButtonHeist/Sources/HeistDoctorTool
  ButtonHeist/Sources/HeistPlanTool
)

FENCE_SOURCE_PATHS=(
  ButtonHeist/Sources/TheButtonHeist/TheFence
)

EXISTING_PATHS=()
for path in "${CODE_PATHS[@]}"; do
  if [[ -e "$path" ]]; then
    EXISTING_PATHS+=("$path")
  fi
done

EXISTING_SOURCE_PATHS=()
for path in "${SOURCE_PATHS[@]}"; do
  if [[ -e "$path" ]]; then
    EXISTING_SOURCE_PATHS+=("$path")
  fi
done

EXISTING_TOOL_SOURCE_PATHS=()
for path in "${TOOL_SOURCE_PATHS[@]}"; do
  if [[ -e "$path" ]]; then
    EXISTING_TOOL_SOURCE_PATHS+=("$path")
  fi
done

EXISTING_FENCE_SOURCE_PATHS=()
for path in "${FENCE_SOURCE_PATHS[@]}"; do
  if [[ -e "$path" ]]; then
    EXISTING_FENCE_SOURCE_PATHS+=("$path")
  fi
done

CHECKS=(
  'retired plan-source request type::\bHeistPlanSourceRequest\b'
  'retired inline plan-source field::\binlineButtonHeistSource\b'
  'retired inline admission compatibility flag::\bacceptsInlineButtonHeistSource\b'
  'untyped JSON dictionary::\[String:[[:space:]]*Any\]'
  'type-erased hash key::\bAnyHashable\b'
  'metatype-as-data expectation::\bAny\.Type\b'
  'Foundation dynamic JSON traversal::\bJSONSerialization\.(jsonObject|data)\b'
  'type-erased Encodable payload::\bany[[:space:]]+Encodable\b'
  'visible Any bridge::\bas Any\b'
  'retired action kind initializer surface::\bactionKind\b'
)

status=0

git_grep() {
  local pattern="$1"
  shift

  if [[ "$#" -eq 0 ]]; then
    return 0
  fi

  git grep -n -E "$pattern" -- "$@" || true
}

report_matches() {
  local label="$1"
  local matches="$2"

  if [[ -n "$matches" ]]; then
    echo "::error::Invalid Swift pipeline shape rejected: $label"
    printf '%s\n' "$matches"
    status=1
  fi
}

filter_allowed_normalized_lines() {
  local matches="$1"
  shift

  local filtered=""
  local match normalized allowed is_allowed
  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    normalized="$(printf '%s\n' "$match" | sed -E 's/^([^:]+):[0-9]+:/\1:LINE:/')"
    is_allowed=0
    for allowed in "$@"; do
      if [[ "$normalized" == "$allowed" ]]; then
        is_allowed=1
        break
      fi
    done
    if [[ "$is_allowed" -eq 0 ]]; then
      filtered+="${match}"$'\n'
    fi
  done <<< "$matches"

  printf '%s' "$filtered"
}

filter_allowed_paths() {
  local matches="$1"
  shift

  local filtered=""
  local match path allowed is_allowed
  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    path="${match%%:*}"
    is_allowed=0
    for allowed in "$@"; do
      if [[ "$path" =~ $allowed ]]; then
        is_allowed=1
        break
      fi
    done
    if [[ "$is_allowed" -eq 0 ]]; then
      filtered+="${match}"$'\n'
    fi
  done <<< "$matches"

  printf '%s' "$filtered"
}

for check in "${CHECKS[@]}"; do
  label="${check%%::*}"
  pattern="${check#*::}"
  report_matches "$label" "$(git_grep "$pattern" "${EXISTING_PATHS[@]}")"
done

TOOLING_PUBLIC_API_GUARD_PATHS=(
  ButtonHeist/Sources/TheButtonHeist/Support/IdleMonitor.swift
  ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandArguments.swift
  ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandCatalog.swift
  ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandRouting.swift
  ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+ParameterSpec.swift
  ButtonHeist/Sources/TheButtonHeist/TheFence/FenceCommandReference.swift
)
EXISTING_TOOLING_PUBLIC_API_GUARD_PATHS=()
for path in "${TOOLING_PUBLIC_API_GUARD_PATHS[@]}"; do
  if [[ -e "$path" ]]; then
    EXISTING_TOOLING_PUBLIC_API_GUARD_PATHS+=("$path")
  fi
done

tooling_plain_public_type_matches="$(
  git_grep \
    '^[[:space:]]*public[[:space:]]+(final[[:space:]]+class|struct|enum)[[:space:]]+(IdleMonitor|FenceCommandDescriptor|FenceCommandProjection|FenceCommandFamily|FenceParameterSpec|FenceParameterKey|MCPExposure|MCPToolAnnotationSpec|CLIExposure|FenceCommandReference|FenceOperationRequest|FenceOperationRoutingError|CommandArgumentEnvelope)\b' \
    "${EXISTING_TOOLING_PUBLIC_API_GUARD_PATHS[@]}"
)"
report_matches "tooling-only catalog/schema/reference type in normal public API" "$tooling_plain_public_type_matches"

tooling_plain_public_extension_matches="$(
  git_grep \
    '^[[:space:]]*public[[:space:]]+extension[[:space:]]+(TheFence[.]Command|FenceParameterKey|FenceParameterSpec([.]ParamType)?|FenceCommandDescriptor)\b' \
    "${EXISTING_TOOLING_PUBLIC_API_GUARD_PATHS[@]}"
)"
report_matches "tooling-only catalog/schema/reference extension in normal public API" "$tooling_plain_public_extension_matches"

SPI_PUBLIC_ALLOWED_LINES=(
  'ButtonHeist/Sources/TheButtonHeist/Support/IdleMonitor.swift:LINE:@_spi(ButtonHeistTooling) public final class IdleMonitor {'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/FenceResponsePresenter.swift:LINE:@_spi(ButtonHeistInternals) public struct FenceResponsePresenter: Sendable {'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/ProjectionProfile.swift:LINE:@_spi(ButtonHeistInternals) public struct ProjectionProfile: Sendable, Equatable {'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandArguments.swift:LINE:    @_spi(ButtonHeistTooling) public struct CommandArgumentEnvelope: Sendable {'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandArguments.swift:LINE:        @_spi(ButtonHeistTooling) public let argumentValues: [String: HeistValue]'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandArguments.swift:LINE:        @_spi(ButtonHeistTooling) public init('
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandCatalog.swift:LINE:@_spi(ButtonHeistTooling) public enum FenceCommandFamily: String, Sendable, CaseIterable {'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandCatalog.swift:LINE:@_spi(ButtonHeistTooling) public struct FenceCommandDescriptor: Sendable, Equatable {'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandCatalog.swift:LINE:@_spi(ButtonHeistTooling) public struct FenceCommandProjection: Sendable, Equatable {'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandCatalog.swift:LINE:@_spi(ButtonHeistTooling) public extension TheFence.Command {'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandRouting.swift:LINE:@_spi(ButtonHeistTooling) public struct FenceOperationRoutingError: Error, LocalizedError, Sendable {'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandRouting.swift:LINE:    @_spi(ButtonHeistTooling) public let message: String'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandRouting.swift:LINE:    @_spi(ButtonHeistTooling) public let details: FailureDetails'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandRouting.swift:LINE:    @_spi(ButtonHeistTooling) public init(message: String, details: FailureDetails = FailureDetails(code: .requestInvalid)) {'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandRouting.swift:LINE:@_spi(ButtonHeistTooling) public struct FenceOperationRequest: Sendable {'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandRouting.swift:LINE:    @_spi(ButtonHeistTooling) public let command: TheFence.Command'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandRouting.swift:LINE:    @_spi(ButtonHeistTooling) public let arguments: TheFence.CommandArgumentEnvelope'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandRouting.swift:LINE:    @_spi(ButtonHeistTooling) public init(command: TheFence.Command, arguments: TheFence.CommandArgumentEnvelope) {'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandRouting.swift:LINE:@_spi(ButtonHeistTooling) public extension TheFence.Command {'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+ParameterSpec.swift:LINE:@_spi(ButtonHeistTooling) public struct FenceParameterSpec: Sendable, Equatable {'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+ParameterSpec.swift:LINE:@_spi(ButtonHeistTooling) public struct FenceParameterKey: RawRepresentable, Hashable, Sendable {'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+ParameterSpec.swift:LINE:@_spi(ButtonHeistTooling) public extension FenceParameterKey {'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+ParameterSpec.swift:LINE:@_spi(ButtonHeistTooling) public enum MCPExposure: Sendable, Equatable {'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+ParameterSpec.swift:LINE:@_spi(ButtonHeistTooling) public struct MCPToolAnnotationSpec: Sendable, Equatable {'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+ParameterSpec.swift:LINE:@_spi(ButtonHeistTooling) public extension FenceParameterSpec.ParamType {'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+ParameterSpec.swift:LINE:@_spi(ButtonHeistTooling) public extension FenceCommandDescriptor {'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+ParameterSpec.swift:LINE:@_spi(ButtonHeistTooling) public extension FenceParameterSpec {'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+ParameterSpec.swift:LINE:@_spi(ButtonHeistTooling) public enum CLIExposure: Sendable, Equatable {'
  'ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence.swift:LINE:    @_spi(ButtonHeistTooling) public func execute(_ request: FenceOperationRequest) async throws -> FenceResponse {'
)
spi_public_matches="$(git_grep '@_spi\([^)]*\)[[:space:]]+public[[:space:]]+' "${EXISTING_SOURCE_PATHS[@]}")"
spi_public_matches="$(filter_allowed_normalized_lines "$spi_public_matches" "${SPI_PUBLIC_ALLOWED_LINES[@]}")"
report_matches "new SPI-public declaration outside explicit allowlist" "$spi_public_matches"

projection_public_internals_matches="$(
  git_grep \
    '^[[:space:]]*(@_spi\([^)]*\)[[:space:]]+)?public[[:space:]]+(struct[[:space:]]+ProjectionLimits\b|enum[[:space:]]+Kind\b|let[[:space:]]+(profile|kind|limits)\b|init[[:space:]]*\([[:space:]]*kind:)' \
    ButtonHeist/Sources/TheButtonHeist/TheFence/ProjectionProfile.swift \
    ButtonHeist/Sources/TheButtonHeist/TheFence/FenceResponsePresenter.swift
)"
report_matches "response projection implementation control in public or SPI API" "$projection_public_internals_matches"

tooling_public_implementation_type_matches="$(
  git_grep \
    '^[[:space:]]*public[[:space:]]+(struct|enum)[[:space:]]+(HeistPlanSourceCompiler|HeistPlanSourceCompilerError|RuntimeKnobEnvironmentKey|RuntimeKnobEnvironment|RuntimeKnobEnvironmentBridge|ButtonHeistRuntimeKnobs|HeistExecutionReportSummaryDTO|HeistExecutionStepReportDTO)\b' \
    ButtonHeist/Sources/ThePlans/HeistPlanSourceCompiler.swift \
    ButtonHeist/Sources/TheScore/ButtonHeistRuntimeKnobs.swift \
    ButtonHeist/Sources/TheScore/HeistExecutionResult+Report.swift
)"
report_matches "tooling-only implementation helper in public API" "$tooling_public_implementation_type_matches"

RAW_LOGGER_ALLOWED_LINES=(
  'ButtonHeist/Sources/TheScore/ButtonHeistLog.swift:LINE:        Logger(subsystem: channel.subsystem.rawValue, category: channel.category)'
)
raw_logger_matches="$(git_grep '\bLogger[[:space:]]*\(' "${EXISTING_SOURCE_PATHS[@]}")"
raw_logger_matches="$(filter_allowed_normalized_lines "$raw_logger_matches" "${RAW_LOGGER_ALLOWED_LINES[@]}")"
report_matches "direct raw Logger construction outside ButtonHeistLog.logger" "$raw_logger_matches"

TUPLE_RETURN_GUARD_PATHS=(
  'ButtonHeist/Sources/ThePlans/HeistCompiler.swift'
  'ButtonHeist/Sources/ThePlans/HeistPlanSourceCompiler.swift'
  'ButtonHeist/Sources/ThePlans/HeistSwiftFileCompiler.swift'
  ':(glob)ButtonHeist/Sources/ThePlans/HeistPlanSource*Parser.swift'
  ':(glob)ButtonHeist/Sources/TheButtonHeist/TheFence/*.swift'
  'ButtonHeistMCP/Sources/main.swift'
)
tuple_return_matches="$(git_grep '[[:space:]]*->[[:space:]]*\([^)]*,[^)]*\)[?]?' "${TUPLE_RETURN_GUARD_PATHS[@]}")"
report_matches "tuple return APIs in parser/compiler/fence/MCP surfaces" "$tuple_return_matches"

GESTURE_PAYLOAD_GUARD_PATHS=(
  ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+RequestPayload+GestureTargets.swift
  ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+RequestPayload+SwipeDragGestures.swift
)
EXISTING_GESTURE_PAYLOAD_GUARD_PATHS=()
for path in "${GESTURE_PAYLOAD_GUARD_PATHS[@]}"; do
  if [[ -e "$path" ]]; then
    EXISTING_GESTURE_PAYLOAD_GUARD_PATHS+=("$path")
  fi
done
gesture_payload_helper_matches="$(git_grep '\b(SwipeInput|DragInput|BoundedUnitPoint|singleObjectPayloadIntent|decodeGestureTarget)\b' "${EXISTING_GESTURE_PAYLOAD_GUARD_PATHS[@]}")"
report_matches "retired gesture-local payload decoder/helper" "$gesture_payload_helper_matches"

gesture_expectation_prefix_matches="$(
  for path in "${EXISTING_GESTURE_PAYLOAD_GUARD_PATHS[@]}"; do
    [[ -f "$path" ]] || continue
    perl -0ne 'while (/prefixed\s*\(\s*"(elementDirection\.element|elementUnitPoints\.element|elementToPoint\.element)"/sg) { my $before = substr($_, 0, $-[0]); my $line = ($before =~ tr/\n//) + 1; my $match = $&; $match =~ s/\s+/ /g; $match =~ s/^\s+|\s+$//g; print "$ARGV:$line:$match\n"; }' "$path"
  done
)"
report_matches "duplicated gesture element-target expectation prefix" "$gesture_expectation_prefix_matches"

compiler_diagnostic_collapse_matches="$(git_grep 'diagnostics\[[0-9]+\]' ButtonHeist/Sources/ThePlans)"
report_matches "compiler diagnostic set collapsed by index" "$compiler_diagnostic_collapse_matches"

UNCHECKED_ADMISSION_ALLOWED_PATHS=(
  '^ButtonHeist/Sources/ThePlans/HeistPlan\+RuntimeValidationAdmission\.swift$'
  '^ButtonHeist/Sources/ThePlans/HeistPlan\+RuntimeValidationTraversal\.swift$'
  '^ButtonHeist/Sources/ThePlans/HeistPlanSourceDiagnostics\.swift$'
)
unchecked_admission_matches="$(git_grep 'uncheckedPlanForRuntimeSafetyValidation[[:space:]]*\(' ButtonHeist/Sources/ThePlans)"
unchecked_admission_matches="$(filter_allowed_paths "$unchecked_admission_matches" "${UNCHECKED_ADMISSION_ALLOWED_PATHS[@]}")"
report_matches "unchecked plan admission outside runtime validation boundary" "$unchecked_admission_matches"

PUBLIC_INTERFACE_RAW_ALLOWED_PATHS=(
  '^ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON\+Interface\.swift$'
)
public_interface_raw_matches="$(git_grep 'PublicInterface[[:space:]]*\([[:space:]]*interface:' "${EXISTING_SOURCE_PATHS[@]}")"
public_interface_raw_matches="$(filter_allowed_paths "$public_interface_raw_matches" "${PUBLIC_INTERFACE_RAW_ALLOWED_PATHS[@]}")"
report_matches "raw Interface to PublicInterface projection outside interface JSON boundary" "$public_interface_raw_matches"

public_command_execute_matches="$(git_grep 'public[[:space:]]+func[[:space:]]+execute[[:space:]]*\([[:space:]]*command:' "${EXISTING_SOURCE_PATHS[@]}")"
report_matches "public command-plus-arguments execution surface" "$public_command_execute_matches"

direct_command_execute_matches="$(git_grep '\.execute[[:space:]]*\([[:space:]]*command:[^)]*arguments:' "${EXISTING_SOURCE_PATHS[@]}")"
report_matches "direct fence command-plus-arguments call site" "$direct_command_execute_matches"

command_boundary_raw_matcher_matches="$(
  git_grep \
    'argumentValues\[[^]]*"(checks|label|identifier|value|traits|excludeTraits)"|schemaStringMatches[[:space:]]*\([[:space:]]*("label"|"identifier"|"value"|[.]label|[.]identifier|[.]value)[[:space:]]*\)|schemaStringArray[[:space:]]*\([[:space:]]*("traits"|"excludeTraits"|[.]traits|[.]excludeTraits)[[:space:]]*\)' \
    "${EXISTING_FENCE_SOURCE_PATHS[@]}"
)"
report_matches "raw command-boundary matcher shortcut outside typed matcher-field boundary" "$command_boundary_raw_matcher_matches"

PUBLIC_RESPONSE_SERIALIZATION_CALL_SITE_PATHS=(
  ButtonHeist/Sources/TheButtonHeist/TheFence/FenceResponsePresenter.swift
  ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+Formatting+JSON.swift
  ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON+Response.swift
  ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON+Action.swift
  ButtonHeist/Sources/TheButtonHeist/TheFence/FenceResponseModels.swift
)
EXISTING_PUBLIC_RESPONSE_SERIALIZATION_CALL_SITE_PATHS=()
for path in "${PUBLIC_RESPONSE_SERIALIZATION_CALL_SITE_PATHS[@]}"; do
  if [[ -e "$path" ]]; then
    EXISTING_PUBLIC_RESPONSE_SERIALIZATION_CALL_SITE_PATHS+=("$path")
  fi
done
public_response_direct_encoder_matches="$(git_grep '\bJSONEncoder[[:space:]]*\(' "${EXISTING_PUBLIC_RESPONSE_SERIALIZATION_CALL_SITE_PATHS[@]}")"
report_matches "public response JSONEncoder bypass outside PublicJSONSerializer" "$public_response_direct_encoder_matches"

PUBLIC_RESPONSE_ENVELOPE_ALLOWED_PATHS=(
  '^ButtonHeist/Sources/TheButtonHeist/TheFence/PublicJSONSerializer\.swift$'
)
public_response_envelope_matches="$(git_grep '\bPublicResponseEnvelope\b' "${EXISTING_FENCE_SOURCE_PATHS[@]}")"
public_response_envelope_matches="$(filter_allowed_paths "$public_response_envelope_matches" "${PUBLIC_RESPONSE_ENVELOPE_ALLOWED_PATHS[@]}")"
report_matches "public response envelope bypass outside PublicJSONSerializer" "$public_response_envelope_matches"

TOOL_STDOUT_ALLOWED_LINES=(
  'ButtonHeist/Sources/HeistDoctorTool/main.swift:LINE:        FileHandle.standardOutput.write(Data((line + "\n").utf8))'
  'ButtonHeist/Sources/HeistPlanTool/main.swift:LINE:        FileHandle.standardOutput.write(data)'
)
tool_stdout_matches="$(git_grep '\bprint[[:space:]]*\(|FileHandle\.standardOutput\.write' "${EXISTING_TOOL_SOURCE_PATHS[@]}")"
tool_stdout_matches="$(filter_allowed_normalized_lines "$tool_stdout_matches" "${TOOL_STDOUT_ALLOWED_LINES[@]}")"
report_matches "direct stdout writes in tools outside local output sinks" "$tool_stdout_matches"

ANY_EXISTENTIAL_ALLOWED_LINES=(
  'ButtonHeist/Sources/TheButtonHeist/Storage/PrivateStorage.swift:LINE:    var foundationAttributes: [FileAttributeKey: Any] {'
)
any_existential_matches="$(git_grep '(:|->|\[[^]]*:)[[:space:]]*Any\b' "${EXISTING_SOURCE_PATHS[@]}")"
any_existential_matches="$(filter_allowed_normalized_lines "$any_existential_matches" "${ANY_EXISTENTIAL_ALLOWED_LINES[@]}")"
report_matches "broad Any existential outside narrow Foundation bridge allowlist" "$any_existential_matches"

public_adapter_matches="$(git_grep '\bPublicAdapter(InputLimits|InputError)\b' "${EXISTING_PATHS[@]}")"
report_matches "retired PublicAdapter naming" "$public_adapter_matches"

public_failure_projection_matches="$(git_grep '\bPublic(ActionFailureProjection|Failure|FailureDetail|FailureDetails)\b' "${EXISTING_PATHS[@]}")"
report_matches "retired public failure projection naming" "$public_failure_projection_matches"

ACTION_PROJECTION_CALL_SITE_PATHS=(
  ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON+Response.swift
  ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON+Action.swift
  ButtonHeist/Sources/TheButtonHeist/TheFence/ReportProjections.swift
  ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+Formatting.swift
  ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+Formatting+Compact+Action.swift
)
EXISTING_ACTION_PROJECTION_CALL_SITE_PATHS=()
for path in "${ACTION_PROJECTION_CALL_SITE_PATHS[@]}"; do
  if [[ -e "$path" ]]; then
    EXISTING_ACTION_PROJECTION_CALL_SITE_PATHS+=("$path")
  fi
done

action_projection_string_method_matches="$(git_grep '\b(let|var)[[:space:]]+method:[[:space:]]*String\b|^[[:space:]]*method:[[:space:]]*String\b' ButtonHeist/Sources/TheButtonHeist/TheFence/ReportProjections.swift)"
report_matches "ActionProjection string method storage" "$action_projection_string_method_matches"

action_projection_method_label_matches="$(git_grep 'ActionProjection[[:space:]]*\([[:space:]]*method:|^[[:space:]]*method:[[:space:]]*[^.]' "${EXISTING_ACTION_PROJECTION_CALL_SITE_PATHS[@]}")"
report_matches "ActionProjection raw method argument label" "$action_projection_method_label_matches"

MCP_VALUE_MAP_ALLOWED_PATHS=(
  '^ButtonHeistMCP/Sources/main\.swift$'
  '^ButtonHeistMCP/Sources/MCPArgumentInputPreflight\.swift$'
  '^ButtonHeistMCP/Tests/ToolRoutingTests\.swift$'
  '^ButtonHeistMCP/Tests/ToolSyncTests\.swift$'
)
mcp_value_map_matches="$(git_grep '\[String:[[:space:]]*Value\]' ButtonHeistMCP/Sources ButtonHeistMCP/Tests)"
mcp_value_map_matches="$(filter_allowed_paths "$mcp_value_map_matches" "${MCP_VALUE_MAP_ALLOWED_PATHS[@]}")"
report_matches "MCP SDK Value string map outside MCP argument boundary" "$mcp_value_map_matches"

property_change_string_projection_matches="$(git_grep 'public var (old|new):[[:space:]]*String\?' ButtonHeist/Sources/TheScore/TreeChangeModels.swift)"
report_matches "PropertyChange string old/new projections" "$property_change_string_projection_matches"

property_change_erased_decode_matches="$(git_grep 'value\(from[[:space:]]+erasedValue|ElementPropertyValue\.self|decodeValue\(' ButtonHeist/Sources/TheScore/TreeChangeModels.swift)"
report_matches "PropertyChange erased value decoding" "$property_change_erased_decode_matches"

property_change_erased_evaluation_matches="$(git_grep 'matchesPropertyValue|matchesTraitPropertyValue|propertyChange\.(oldValue|newValue)' ButtonHeist/Sources/TheScore/AccessibilityPredicate+Evaluation.swift)"
report_matches "PropertyChange erased value evaluation" "$property_change_erased_evaluation_matches"

HEIST_COMPILATION_ALLOWED_PATHS=(
  '^ButtonHeist/Sources/ThePlans/HeistCompiler\.swift$'
  '^ButtonHeist/Sources/ThePlans/HeistPlanSourceDiagnostics\.swift$'
  '^ButtonHeist/Sources/HeistPlanTool/main\.swift$'
  '^ButtonHeistCLI/Sources/Commands/RunHeistCommand\.swift$'
  '^ButtonHeist/Tests/ThePlansTests/HeistCompilerTests\.swift$'
)
heist_compilation_matches="$(git_grep '\bHeistCompilation(SourceLocation|Diagnostic|Result)\b' "${EXISTING_PATHS[@]}")"
heist_compilation_matches="$(filter_allowed_paths "$heist_compilation_matches" "${HEIST_COMPILATION_ALLOWED_PATHS[@]}")"
report_matches "retired HeistCompilation naming outside compiler compatibility boundary" "$heist_compilation_matches"

KNOWN_FAILURE_PREFIX='(request|discovery|setup|connection|transport|auth|session|protocol|tls|client|server|config|formatting|screen)\.'
known_failure_constructor_matches="$(
  for path in "${EXISTING_PATHS[@]}"; do
    if [[ -d "$path" ]]; then
      while IFS= read -r file; do
        perl -0ne 'while (/\b(FailureCode|KnownFailureCode)\s*\(\s*(rawValue|boundaryRawValue):\s*"(request|discovery|setup|connection|transport|auth|session|protocol|tls|client|server|config|formatting|screen)\./sg) { my $before = substr($_, 0, $-[0]); my $line = ($before =~ tr/\n//) + 1; my $match = $&; $match =~ s/\s+/ /g; $match =~ s/^\s+|\s+$//g; print "$ARGV:$line:$match\n"; }' "$file"
      done < <(find "$path" -type f -name '*.swift')
    elif [[ "$path" == *.swift ]]; then
      perl -0ne 'while (/\b(FailureCode|KnownFailureCode)\s*\(\s*(rawValue|boundaryRawValue):\s*"(request|discovery|setup|connection|transport|auth|session|protocol|tls|client|server|config|formatting|screen)\./sg) { my $before = substr($_, 0, $-[0]); my $line = ($before =~ tr/\n//) + 1; my $match = $&; $match =~ s/\s+/ /g; $match =~ s/^\s+|\s+$//g; print "$ARGV:$line:$match\n"; }' "$path"
    fi
  done
)"
report_matches \
  "raw known failure code construction" \
  "$known_failure_constructor_matches"

KNOWN_FAILURE_LITERAL_ALLOWED_PATHS=(
  '^ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence\+FailureDetails\.swift$'
  '^ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence\+FailureTaxonomy\.swift$'
  '^ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON\+Action\.swift$'
  '^ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence\+Connection\.swift$'
  '^ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence\+Formatting\+JSON\.swift$'
  '^ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence\+ScreenHandlers\.swift$'
  '^ButtonHeist/Sources/TheButtonHeist/TheHandoff/HandoffConnectionState\.swift$'
  '^ButtonHeist/Sources/TheButtonHeist/TheHandoff/DeviceConnectionFailures\.swift$'
  '^ButtonHeist/Tests/ButtonHeistTests/TheFenceHandlerTests\.swift$'
)
known_failure_literal_matches="$(git_grep '\berrorCode:[[:space:]]*"'$KNOWN_FAILURE_PREFIX "${EXISTING_PATHS[@]}")"
known_failure_literal_matches="$(filter_allowed_paths "$known_failure_literal_matches" "${KNOWN_FAILURE_LITERAL_ALLOWED_PATHS[@]}")"
report_matches "raw known failure-code literal outside failure taxonomy boundary" "$known_failure_literal_matches"

# No raw FailureDetails/ConnectionFailure call sites are allowed; use FailureCode instead.
failure_raw_initializer_matches="$(
  for path in "${EXISTING_PATHS[@]}"; do
    if [[ -d "$path" ]]; then
      while IFS= read -r file; do
        perl -0ne 'while (/\b(FailureDetails|ConnectionFailure)\s*\([^)]*\berrorCode:/sg) { my $before = substr($_, 0, $-[0]); my $line = ($before =~ tr/\n//) + 1; my $match = $&; $match =~ s/\s+/ /g; $match =~ s/^\s+|\s+$//g; print "$ARGV:$line:$match\n"; }' "$file"
      done < <(find "$path" -type f -name '*.swift')
    elif [[ "$path" == *.swift ]]; then
      perl -0ne 'while (/\b(FailureDetails|ConnectionFailure)\s*\([^)]*\berrorCode:/sg) { my $before = substr($_, 0, $-[0]); my $line = ($before =~ tr/\n//) + 1; my $match = $&; $match =~ s/\s+/ /g; $match =~ s/^\s+|\s+$//g; print "$ARGV:$line:$match\n"; }' "$path"
    fi
  done
)"
report_matches "raw failure-domain initializer outside JSON boundary" "$failure_raw_initializer_matches"

if [[ "$status" -ne 0 ]]; then
  cat <<'EOF'

Only typed Swift models, typed Codable fixtures, concrete enums/structs, and
narrow typed bridge helpers are accepted here.
EOF
fi

exit "$status"
