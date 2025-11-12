#!/usr/bin/env ash
set -euo pipefail
IFS=$'\n\t'

# Error handling
error_handler() {
    echo "Error: An error occurred during execution. Exiting with code 1."
    exit 1
}

trap error_handler ERR
trap 'echo "Script execution finished."' EXIT

# Docker entrypoint script for FoundryVTT
# Initializes environment, configures options, and starts the application
#
# Usage: This script is run automatically in the FoundryVTT Docker container.
# It expects the following environment variables:
# - VARS: Base64-encoded string of KEY=VALUE pairs for configuration
# - FQDN: Fully Qualified Domain Name for the server
# - PROXY_PORT: Port for the proxy
# - UPNP: UPNP setting (true/false)
# Optional:
# - VTT_DIR: Directory for FoundryVTT files (default: /home/foundry/vtt)
# - USERDATA_DIR: Directory for user data (default: /home/foundry/userdata)
# - FIRSTBOOT_FILE: Path to firstboot file (default: /home/foundry/.firstboot)

# Constants (configurable via env vars)
VTT_DIR="${VTT_DIR:-/home/foundry/vtt}"
USERDATA_DIR="${USERDATA_DIR:-/home/foundry/userdata}"
OPTIONS_FILE="${USERDATA_DIR}/Config/options.json"
FIRSTBOOT_FILE="${FIRSTBOOT_FILE:-/home/foundry/.firstboot}"

# Function to validate required tools
validate_tools() {
    echo " - Validating required tools..."
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: jq is not installed."
        exit 1
    fi

    if ! command -v base64 >/dev/null 2>&1; then
        echo "Error: base64 is not available."
        exit 1
    fi
    echo " - Tools validation complete."
}

# Function to setup environment variables from base64 encoded VARS
setup_environment() {
    echo " - Setting up environment variables..."
    if [ -z "${VARS:-}" ]; then
        echo "Error: VARS environment variable is not set or empty."
        exit 1
    fi

    if ! decoded_str=$(echo "${VARS}" | base64 -d 2>/dev/null); then
        echo "Error: Failed to decode VARS (invalid base64)."
        exit 1
    fi

    echo "Decoded variables: ${decoded_str}"

    while IFS='=' read -r key value; do
        if [ -n "${key}" ] && [ -n "${value}" ]; then
            export "${key}=${value}"
            echo "Exported: ${key}"
        else
            echo "Warning: Skipping invalid variable pair: ${key}=${value}"
        fi
    done <<< "${decoded_str}"
    echo " - Environment setup complete."
}

# Function to validate required environment variables
validate_variables() {
    echo " - Validating required environment variables..."
    if [ -z "${FQDN:-}" ]; then
        echo "Error: FQDN environment variable is not set."
        exit 1
    fi

    if [ -z "${PROXY_PORT:-}" ]; then
        echo "Error: PROXY_PORT environment variable is not set."
        exit 1
    fi

    if [ -z "${UPNP:-}" ]; then
        echo "Error: UPNP environment variable is not set."
        exit 1
    fi

    echo "FQDN=${FQDN}"
    echo "PROXY_PORT=${PROXY_PORT}"
    echo " - Variable validation complete."
}

# Function to update FoundryVTT options.json
update_options() {
    echo " - Updating FoundryVTT options..."
    local default_options='{
  "dataPath": "/home/foundry/userdata",
  "compressStatic": true,
  "fullscreen": false,
  "hostname": null,
  "language": "en.core",
  "port": 30000,
  "proxyPort": null,
  "proxySSL": false,
  "routePrefix": null,
  "updateChannel": "stable",
  "upnp": null
}'

    # Only update if file exists and is valid JSON
    if [ -f "${OPTIONS_FILE}" ] && jq empty "${OPTIONS_FILE}" >/dev/null 2>&1; then
        # Update only the known fields in existing valid JSON
        if ! jq --arg fqdn "${FQDN}" --arg port_str "${PROXY_PORT}" --arg upnp_str "${UPNP}" '.hostname = $fqdn | .proxyPort = ($port_str | tonumber) | .upnp = ($upnp_str == "true")' "${OPTIONS_FILE}" > "${OPTIONS_FILE}.tmp"; then
            echo " - Warning: Failed to update options.json, leaving existing file unchanged"
        else
            mv "${OPTIONS_FILE}.tmp" "${OPTIONS_FILE}"
            echo " - Options update complete."
        fi
    else
        echo " - Options file missing or corrupted, letting FoundryVTT create default configuration"
    fi
}

# Function to start FoundryVTT
start_foundry() {
    echo " - Starting FoundryVTT..."
    cd "${VTT_DIR}"
    export USER=$(whoami)
    echo " - Running FoundryVTT as ${USER}"

    # Detect main file path
    if [ -f resources/app/main.js ]; then
        MAIN_PATH="resources/app/main.js"
    elif [ -f main.js ]; then
        MAIN_PATH="main.js"
    else
        echo "Error: Could not find FoundryVTT main.js entrypoint."
        exit 1
    fi

    echo " - Running pm2 app foundry ..."
    pm2-runtime start --env production --name foundry "${MAIN_PATH}" -- --dataPath="${USERDATA_DIR}" --noupnp="${UPNP}" --port=30000
}

# Main execution
echo "Starting main execution..."
validate_tools
setup_environment
validate_variables

if [ -f "${FIRSTBOOT_FILE}" ]; then
    echo " - Firstboot!"
    rm -rf "${FIRSTBOOT_FILE}"
fi

# Always update options on every container start
update_options

start_foundry
echo "FoundryVTT startup process complete."
