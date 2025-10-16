#!/usr/bin/env bats

# Tests for docker-entrypoint.sh

setup() {
    # Load the script
    load '../FoundryVTT/docker-entrypoint.sh'
    # Disable set -e for testing
    set +e
}

@test "constants are defined" {
    [ -n "$VTT_DIR" ]
    [ -n "$USERDATA_DIR" ]
    [ -n "$OPTIONS_FILE" ]
    [ -n "$FIRSTBOOT_FILE" ]
}

@test "validate_tools succeeds when jq and base64 are available" {
    run validate_tools
    [ "$status" -eq 0 ]
}

@test "validate_variables fails when FQDN is missing" {
    unset FQDN
    run validate_variables
    [ "$status" -eq 1 ]
    [ "$output" = "Error: FQDN environment variable is not set." ]
}

@test "validate_variables succeeds when all vars are set" {
    export FQDN="example.com"
    export PROXY_PORT="3000"
    export UPNP="false"
    run validate_variables
    [ "$status" -eq 0 ]
}

@test "setup_environment fails when VARS is empty" {
    export VARS=""
    run setup_environment
    [ "$status" -eq 1 ]
    [ "$output" = "Error: VARS environment variable is not set or empty." ]
}

@test "setup_environment succeeds with valid base64" {
    export VARS="$(echo -n 'FQDN=test.com' | base64)"
    run setup_environment
    [ "$status" -eq 0 ]
    [ "$FQDN" = "test.com" ]
}