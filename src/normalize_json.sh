#!/usr/bin/env bash
# Normalization helper for vttctl
# This file is intended to be sourced by `vttctl.sh` and provides
# a single function: normalize_json <json-string-or-stdin>
# It emits a compact JSON object with canonical fields:
# running,http,active,version,world,system,systemVersion,timestamp

# Normalize arbitrary JSON into canonical status schema.
# Emits a compact JSON object with these fields:
#   running (string|boolean), http (number), active (bool), version (string|null),
#   world (string|null), system (string|null), systemVersion (string|null), timestamp (RFC3339 UTC string)
function normalize_json() {
    local input="${1:-}"
    if [[ -z "${input}" ]]; then
        # read from stdin if no arg provided
        input=$(cat || true)
    fi

    # ensure no debug artifacts remain (noop if missing)
    rm -f /tmp/vttctl_raw_status.json 2>/dev/null || true

    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "${input}" | jq -c --arg ts "${ts}" '
        # httpnum defaults to 200 when http field is missing
        def httpnum: (if has("http") then (try (.http|tonumber) catch 0) else 200 end);
        def runraw: (if has("running") then (.running|tostring) else "" end);
        def runlow: (if runraw=="" then "" else (runraw|ascii_downcase) end);
        {
            # If running is absent or ambiguous (unknown/error), infer from http code; otherwise keep original
            running: (if (runlow == "" or runlow == "unknown" or runlow == "error") then (if httpnum >= 200 and httpnum < 400 then "ok" else "error" end) else (.running) end),
            http: (if has("http") then (.http|try tonumber catch .http) else 200 end),
            active: (.active // false),
            version: (.version // null),
            world: (.world // null),
            system: (.system // null),
            systemVersion: (.systemVersion // null),
            timestamp: (.timestamp // $ts)
        }'
}

export -f normalize_json 2>/dev/null || true
