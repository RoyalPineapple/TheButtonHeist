def require($condition; $message):
    if $condition then . else error($message) end;

($manifest[0].mutations | map(.id)) as $required
| require(type == "object"; "critical mutation result must be an object")
| require(.schemaVersion == 1; "critical mutation result schemaVersion must be 1")
| require(.commit == $commit; "critical mutation result commit does not match requested commit")
| require(.results | type == "array"; "critical mutation results must be an array")
| require(
    [.results[].id] == $required;
    "critical mutation results must contain every reviewed mutation exactly once in manifest order"
)
| require(
    all(.results[]; .outcome == "detected" and .diagnosticMatches > 0);
    "every critical mutation must be detected by its named behavioral diagnostic"
)
| require(
    .score == {detected: ($required | length), total: ($required | length)};
    "critical mutation score must match the complete reviewed inventory"
)
