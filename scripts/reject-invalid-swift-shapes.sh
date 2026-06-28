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

RAW_LOGGER_ALLOWED_LINES=(
  'ButtonHeist/Sources/TheScore/ButtonHeistLog.swift:LINE:        Logger(subsystem: channel.subsystem.rawValue, category: channel.category)'
  'ButtonHeist/Sources/TheButtonHeist/TheHandoff/TheHandoff+Discovery.swift:LINE:private let handoffDiscoveryLogger = Logger(subsystem: "com.buttonheist.thehandoff", category: "discovery")'
  'ButtonHeist/Sources/TheButtonHeist/TheHandoff/USBDeviceDiscovery.swift:LINE:private let logger = Logger(subsystem: "com.buttonheist.thehandoff", category: "usb-discovery")'
  'ButtonHeist/Sources/TheInsideJob/TheInsideJob.swift:LINE:let insideJobLogger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "server")'
  'ButtonHeist/Sources/TheButtonHeist/TheHandoff/TheHandoff+Connection.swift:LINE:private let handoffConnectionLogger = Logger(subsystem: "com.buttonheist.thehandoff", category: "connection")'
  'ButtonHeist/Sources/TheInsideJob/TheStash/WireConversion.swift:LINE:private let wireConversionLogger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "wireConversion")'
  'ButtonHeist/Sources/TheInsideJob/Lifecycle/AutoStart.swift:LINE:private let autoStartLogger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "autostart")'
  'ButtonHeist/Sources/TheInsideJob/Lifecycle/AccessibilityArming.swift:LINE:private let accessibilityArmingLogger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "accessibility")'
  'ButtonHeist/Sources/TheButtonHeist/TheHandoff/DeviceDiscovery.swift:LINE:private let logger = Logger(subsystem: "com.buttonheist.thehandoff", category: "discovery")'
  'ButtonHeist/Sources/TheButtonHeist/TheHandoff/HandoffDiscoveryLifecycle.swift:LINE:private let discoveryLogger = Logger(subsystem: "com.buttonheist.thehandoff", category: "discovery")'
  'ButtonHeist/Sources/TheInsideJob/Server/SimpleSocketServer+ClientState.swift:LINE:private let clientStateLogger = Logger(subsystem: "com.buttonheist.thehandoff", category: "server")'
  'ButtonHeist/Sources/TheInsideJob/Server/TheMuscleAdmission+Authentication.swift:LINE:let muscleAuthenticationLogger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "auth")'
  'ButtonHeist/Sources/TheButtonHeist/TheHandoff/DeviceConnection.swift:LINE:let deviceConnectionLogger = Logger(subsystem: "com.buttonheist.thehandoff", category: "connection")'
  'ButtonHeist/Sources/TheButtonHeist/TheHandoff/DiscoveredDevice+Reachability.swift:LINE:private let reachabilityLogger = Logger(subsystem: "com.buttonheist.thehandoff", category: "reachability")'
  'ButtonHeist/Sources/TheButtonHeist/TheHandoff/HandoffServerMessageRouter.swift:LINE:private let serverMessageLogger = Logger(subsystem: "com.buttonheist.thehandoff", category: "server-message")'
  'ButtonHeist/Sources/TheInsideJob/Server/SimpleSocketServer+ConnectionAcceptance.swift:LINE:private let connectionLogger = Logger(subsystem: "com.buttonheist.thehandoff", category: "server")'
  'ButtonHeist/Sources/TheInsideJob/Server/SocketListenerStartup.swift:LINE:private let listenerLogger = Logger(subsystem: "com.buttonheist.thehandoff", category: "server")'
  'ButtonHeist/Sources/TheInsideJob/Server/BonjourAdvertisement.swift:LINE:private let logger = Logger(subsystem: "com.buttonheist.thehandoff", category: "transport")'
  'ButtonHeist/Sources/TheInsideJob/Server/TheMuscleSession.swift:LINE:private let sessionLogger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "auth")'
  'ButtonHeist/Sources/TheInsideJob/Server/SimpleSocketServer+Sending.swift:LINE:private let sendLogger = Logger(subsystem: "com.buttonheist.thehandoff", category: "server")'
  'ButtonHeist/Sources/TheInsideJob/Server/SimpleSocketServer+Receiving.swift:LINE:private let receiveLogger = Logger(subsystem: "com.buttonheist.thehandoff", category: "server")'
  'ButtonHeist/Sources/TheInsideJob/Server/TheMuscle.swift:LINE:private let muscleLogger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "auth")'
  'ButtonHeist/Sources/TheInsideJob/Server/TransportEventStream.swift:LINE:private let logger = Logger(subsystem: "com.buttonheist.thehandoff", category: "transport")'
)
raw_logger_matches="$(git_grep '\bLogger[[:space:]]*\(' "${EXISTING_SOURCE_PATHS[@]}")"
raw_logger_matches="$(filter_allowed_normalized_lines "$raw_logger_matches" "${RAW_LOGGER_ALLOWED_LINES[@]}")"
report_matches "direct raw Logger construction outside tracked logger factory and legacy sites" "$raw_logger_matches"

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
report_matches \
  "raw known failure code construction" \
  "$(git_grep '\b(FailureCode|KnownFailureCode)[[:space:]]*\([[:space:]]*rawValue:[[:space:]]*"'$KNOWN_FAILURE_PREFIX "${EXISTING_PATHS[@]}")"

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

if [[ "$status" -ne 0 ]]; then
  cat <<'EOF'

Only typed Swift models, typed Codable fixtures, concrete enums/structs, and
narrow typed bridge helpers are accepted here.
EOF
fi

exit "$status"
