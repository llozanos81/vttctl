#!/usr/bin/env bats

@test "diag outputs valid JSON when diagnostics exist" {
  if ! command -v jq >/dev/null 2>&1; then
    skip "jq not installed"
  fi
  if ! command -v docker >/dev/null 2>&1; then
    skip "docker not installed"
  fi

  run ./vttctl.sh diag
  [ "$status" -eq 0 ]
  # verify output is valid JSON
  echo "$output" | jq . >/dev/null
}

@test "diag fails when diagnostics.json is missing in container" {
  if ! command -v docker >/dev/null 2>&1; then
    skip "docker not installed"
  fi

  # find app container
  CONT=$(docker container ls -a --format '{{.ID}} {{.Names}}' | awk '/vtt/ && /app/ {print $1; exit}')
  if [ -z "$CONT" ]; then
    skip "Foundry app container not present"
  fi

  # location inside container
  PATH_IN_CONTAINER="/home/foundry/userdata/Logs/diagnostics.json"

  # ensure file exists
  if ! docker exec "$CONT" test -f "$PATH_IN_CONTAINER" >/dev/null 2>&1; then
    skip "diagnostics.json not present to test removal"
  fi

  # rename the file to simulate missing diagnostics
  docker exec "$CONT" sh -c "mv '$PATH_IN_CONTAINER' '${PATH_IN_CONTAINER}.bak'"
  # run diag - should fail
  run ./vttctl.sh diag
  [ "$status" -ne 0 ]
  [[ "$output" =~ "diagnostics.json not found" ]]

  # restore the file
  docker exec "$CONT" sh -c "mv '${PATH_IN_CONTAINER}.bak' '$PATH_IN_CONTAINER'"
}
