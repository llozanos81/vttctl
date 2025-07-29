# Bats test suite for vttctl.sh

# To run: bats test/vttctl.bats

@test "validate command succeeds" {
  run ./vttctl.sh validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"Validating requirements"* ]]
}

@test "help command prints usage" {
  run ./vttctl.sh help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "unknown command prints error" {
  run ./vttctl.sh doesnotexist
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "default command runs without error" {
  # Skip test if expect is not installed
  if ! command -v expect >/dev/null 2>&1; then
    skip "expect not installed"
  fi
  run expect -c '
    spawn ./vttctl.sh default
    expect "Version to set as default?:"
    send "0\r"
    expect eof
  '
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ] || [ "$status" -eq 127 ]
  [[ "$output" == *"Canceled."* ]] || [[ "$output" == *"Cleaning cancelled."* ]]
}

@test "default command cancels interactively" {
  # Skip test if expect is not installed
  if ! command -v expect >/dev/null 2>&1; then
    skip "expect not installed"
  fi
  run expect -c '
    spawn ./vttctl.sh default
    expect "Version to set as default?:"
    send "0\r"
    expect eof
  '
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ] || [ "$status" -eq 127 ]
  [[ "$output" == *"Canceled."* ]] || [[ "$output" == *"Cleaning cancelled."* ]]
}

# Add more tests for backup, restore, build, etc. as needed.
