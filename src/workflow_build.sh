#!/bin/bash

# Source common functions
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

build_image() {
    local FORCE_REBUILD="${FORCE_REBUILD:-false}"
    local VTT_HOME="${VTT_HOME:-$(pwd)}"
    local FOUNDRY_JSON="${VTT_HOME}/FoundryVTT/foundryvtt.json"
    local DOCKERFILE_TEMPLATE="${VTT_HOME}/templates/Dockerfile.j2"
    local DOCKERFILE_OUTPUT="${VTT_HOME}/FoundryVTT/Dockerfile"
    local ENV_FILE="${VTT_HOME}/.env"

    # Source .env for DEFAULT_VER
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
    fi

    # Check if foundryvtt.json exists
    if [[ ! -f "${FOUNDRY_JSON}" ]]; then
        log_failure_msg "FoundryVTT configuration file not found: ${FOUNDRY_JSON}"
        return 1
    fi

    # Parse available versions from extracted directories in FoundryVTT/
    local json_content=$(cat "${FOUNDRY_JSON}")
    local available_majors=()
    declare -A major_to_nodejs
    declare -A major_to_alpine

    # First, get all supported majors from json
    if echo "$json_content" | jq -e '.foundryvtt' >/dev/null 2>&1; then
        local count=$(echo "$json_content" | jq '.foundryvtt | length')
        for ((i=0; i<count; i++)); do
            local major_ver=$(echo "$json_content" | jq -r ".foundryvtt[$i].version" | cut -d'.' -f1)
            local nodejs_ver=$(echo "$json_content" | jq -r ".foundryvtt[$i].nodejs")
            local alpine_ver=$(echo "$json_content" | jq -r ".foundryvtt[$i].alpine")
            major_to_nodejs["$major_ver"]="$nodejs_ver"
            major_to_alpine["$major_ver"]="$alpine_ver"
        done
    else
        log_failure_msg "Invalid JSON structure in ${FOUNDRY_JSON}"
        return 1
    fi

        # Now, find extracted versions in FoundryVTT/
    local versions=()
    for dir in "${VTT_HOME}/FoundryVTT/"*; do
        if [[ -d "$dir" && $(basename "$dir") =~ ^[0-9]+\.[0-9]+$ ]]; then
            local version=$(basename "$dir")
            local major=${version%%.*}
            if [[ -n "${major_to_nodejs[$major]}" ]]; then
                versions+=("$version")
            fi
        fi
    done

    if [[ ${#versions[@]} -eq 0 ]]; then
        log_failure_msg "No extracted FoundryVTT versions found in ${VTT_HOME}/FoundryVTT/"
        return 1
    fi

    # Interactive selection with color for default
    log_daemon_msg "Select FoundryVTT version to build:"
    local i=1
    for ver in "${versions[@]}"; do
        if [[ "$ver" == "$DEFAULT_VER" ]]; then
            echo -e "$i) \033[32m$ver (default)\033[0m"
        else
            echo "$i) $ver"
        fi
        ((i++))
    done
    echo -n "Enter choice (1-${#versions[@]}): "
    read -r choice
    if [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#versions[@]} )); then
        version="${versions[$((choice-1))]}"
        major=${version%%.*}
        nodejs_version=${major_to_nodejs[$major]}
        alpine_version=${major_to_alpine[$major]}
    else
        log_failure_msg "Invalid selection."
        return 1
    fi

    log_daemon_msg "Selected version: ${version} (Node.js: ${nodejs_version}, Alpine: ${alpine_version})"

    # Check if image already exists
    local image_tag="foundryvtt:${version}"
    if docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "^${image_tag}$"; then
        if [[ "${FORCE_REBUILD}" != "true" ]]; then
            log_daemon_msg "Image ${image_tag} already exists. Use --force to rebuild."
            return 0
        else
            log_daemon_msg "Force rebuilding ${image_tag}..."
        fi
    fi

    # Generate Dockerfile from template
    log_daemon_msg "Generating Dockerfile for version ${version}..."
    if ! python3 "${VTT_HOME}/python/template_renderer.py" \
        --template "${DOCKERFILE_TEMPLATE}" \
        --output "${DOCKERFILE_OUTPUT}" \
        --var major_version="${major}" \
        --var nodejs_version="${nodejs_version}" \
        --var alpine_version="${alpine_version}"; then
        log_failure_msg "Failed to generate Dockerfile from template"
        return 1
    fi

    # Build the Docker image
    log_daemon_msg "Building Docker image ${image_tag}..."
    if docker build --build-arg BUILD_VER="${version}" -f "${DOCKERFILE_OUTPUT}" -t "${image_tag}" "${VTT_HOME}/FoundryVTT/"; then
        log_daemon_msg "Successfully built ${image_tag}"
    else
        log_failure_msg "Failed to build Docker image"
        return 1
    fi
}