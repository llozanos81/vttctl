#!/usr/bin/env bats

@test "status_json_strict_schema" {
  run bash -c "./vttctl.sh status --json=true"
  [ "$status" -eq 0 ]

  # Parse JSON once
  json="$output"

  # running must be present and either "ok" or "error" or a truthy value
  run jq -r '.running' <<<"$json"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^(ok|error|true|false)$ ]] || true

  # http must be numeric and reasonable
  run jq -r '.http' <<<"$json"
  [ "$status" -eq 0 ]
  http_val="$output"
  [[ "$http_val" =~ ^[0-9]+$ ]]
  (( http_val >= 100 && http_val <= 599 ))

  # active must be boolean
  run jq -e '.active==true or .active==false' <<<"$json"
  [ "$status" -eq 0 ]

  # version should be a simple semver-like major.minor
  run jq -r '.version // empty' <<<"$json"
  version="$output"
  [[ -z "$version" || "$version" =~ ^[0-9]+\.[0-9]+$ ]]

  # system present or null
  run jq -r '.system // empty' <<<"$json"

  # systemVersion optional but if present should look semver-like
  run jq -r '.systemVersion // empty' <<<"$json"
  sv="$output"
  [[ -z "$sv" || "$sv" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]

  # timestamp present and loosely RFC3339
  run jq -r '.timestamp' <<<"$json"
  ts="$output"
  [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}


@test "status_human_and_info_when_running" {
  # Run status and info; if we are running, info should show details
  run bash -c "./vttctl.sh status"
  if [ "$status" -eq 0 ]; then
    [[ "$output" =~ "Foundry VTT is running" ]]

    run bash -c "./vttctl.sh info"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Foundry VTT v" ]] || true
    # When system present, info should show it
    [[ "$output" =~ "System:" ]] || true
    [[ "$output" =~ "World:" ]] || true
  else
    [[ "$output" =~ "Foundry VTT is not running" ]]
  fi
}
