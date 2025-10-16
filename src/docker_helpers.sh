# Docker/container helper functions for vttctl

function stop() {
    CONT_NAME=$(docker container ls -a | awk '/vtt/ && /app/ {print $1}')
    docker exec -it ${CONT_NAME} pm2 stop all
    VARS="" FQDN="" docker-compose -p ${PROD_PROJECT} -f ${VTT_HOME}/docker/docker-compose.yml stop
    VARS="" FQDN="" docker-compose -p ${DEV_PROJECT} -f ${VTT_HOME}/docker/docker-compose-dev.yml stop
}

function getLogs() {
    VARS="" docker-compose -p ${PROD_PROJECT} -f ${VTT_HOME}/docker/docker-compose.yml logs
}

function liveLogs() {
    VARS="" docker-compose -p ${PROD_PROJECT} -f ${VTT_HOME}/docker/docker-compose.yml logs -f
}

function appReload() {
    CONT_NAME=$(docker container ls -a | awk '/vtt/ && /app/ {print $1}')
    docker exec -d ${CONT_NAME} pm2 restart foundry
    sleep 2
    log_daemon_msg "FoundryVTT nodejs application reloaded."
}

function download_foundry() {
    local TIMED_URL="$1"
    local DOWNLOAD_DIR="${VTT_HOME}/downloads"
    local TEMP_DIR=$(mktemp -d)
    
    # Create downloads directory if it doesn't exist
    mkdir -p "$DOWNLOAD_DIR"
    
    log_daemon_msg "Downloading FoundryVTT from: $TIMED_URL"
    
    # Download the file
    if ! curl -L -o "${TEMP_DIR}/foundryvtt.zip" "$TIMED_URL"; then
        log_failure_msg "Failed to download from $TIMED_URL"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # Validate the downloaded file
    if ! validate_foundryvtt_zip "${TEMP_DIR}/foundryvtt.zip"; then
        log_failure_msg "Downloaded file is not a valid FoundryVTT application"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # Extract version from the validated package.json
    local VERSION=$(get_foundryvtt_version "${TEMP_DIR}/foundryvtt.zip")
    if [[ -z "$VERSION" ]]; then
        log_failure_msg "Could not determine FoundryVTT version"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # Determine filename format based on content analysis
    local FINAL_NAME
    if unzip -l "${TEMP_DIR}/foundryvtt.zip" | grep -q "foundryvtt\|resources/app/\|libEGL.so"; then
        # This is an Electron application (version 12 or similar)
        FINAL_NAME="FoundryVTT-${VERSION}.zip"
    elif [[ "$TIMED_URL" == *"FoundryVTT-Linux-"* ]]; then
        FINAL_NAME="FoundryVTT-Linux-${VERSION}.zip"
    else
        # Default to Node format for version 13+
        FINAL_NAME="FoundryVTT-Node-${VERSION}.zip"
    fi
    
    local FINAL_PATH="${DOWNLOAD_DIR}/${FINAL_NAME}"
    
    # Move to final location
    mv "${TEMP_DIR}/foundryvtt.zip" "$FINAL_PATH"
    rm -rf "$TEMP_DIR"
    
    log_daemon_msg "Successfully downloaded and validated FoundryVTT ${VERSION}"
    log_daemon_msg "Saved as: $FINAL_NAME"
}

function extract_foundry() {
    local VERSION="$1"
    local DOWNLOAD_DIR="${VTT_HOME}/downloads"
    local EXTRACT_DIR="${VTT_HOME}/FoundryVTT/${VERSION}"
    
    # Try different filename patterns (prioritize version-specific patterns)
    local ZIP_FILE=""
    for pattern in "FoundryVTT-${VERSION}.zip" "FoundryVTT-Node-${VERSION}.zip" "FoundryVTT-Linux-${VERSION}.zip"; do
        if [[ -f "${DOWNLOAD_DIR}/${pattern}" ]]; then
            ZIP_FILE="${DOWNLOAD_DIR}/${pattern}"
            break
        fi
    done
    
    if [[ -z "$ZIP_FILE" ]]; then
        log_failure_msg "FoundryVTT zip file not found for version ${VERSION}"
        log_failure_msg "Tried: FoundryVTT-${VERSION}.zip, FoundryVTT-Node-${VERSION}.zip, FoundryVTT-Linux-${VERSION}.zip"
        log_failure_msg "Run './vttctl.sh download <url>' first"
        exit 1
    fi
    
    log_daemon_msg "Extracting FoundryVTT ${VERSION}..."
    
    # Create extraction directory
    mkdir -p "$EXTRACT_DIR"
    
    # Extract the zip file
    if ! unzip -q "$ZIP_FILE" -d "$EXTRACT_DIR"; then
        log_failure_msg "Failed to extract $ZIP_FILE"
        rm -rf "$EXTRACT_DIR"
        exit 1
    fi
    
    # Validate the extracted application
    if ! validate_foundryvtt_app "$EXTRACT_DIR"; then
        log_failure_msg "Extracted files are not a valid FoundryVTT application"
        rm -rf "$EXTRACT_DIR"
        exit 1
    fi
    
    # Handle Electron applications (version 12): copy package.json to root for consistency
    if [[ -f "${EXTRACT_DIR}/resources/app/package.json" && ! -f "${EXTRACT_DIR}/package.json" ]]; then
        cp "${EXTRACT_DIR}/resources/app/package.json" "${EXTRACT_DIR}/package.json"
        log_daemon_msg "Copied package.json from resources/app/ to root for Electron application"
    fi
    
    # Make executable files executable (for Electron apps)
    if [[ -f "${EXTRACT_DIR}/foundryvtt" ]]; then
        chmod +x "${EXTRACT_DIR}/foundryvtt"
        log_daemon_msg "Made foundryvtt executable"
    fi
    
    # Copy entrypoint script if it exists in the template
    if [[ -f "${VTT_HOME}/FoundryVTT/docker-entrypoint.sh" ]]; then
        cp "${VTT_HOME}/FoundryVTT/docker-entrypoint.sh" "$EXTRACT_DIR/"
    fi
    
    # Copy topdirsize script if it exists
    if [[ -f "${VTT_HOME}/FoundryVTT/topdirsize.sh" ]]; then
        cp "${VTT_HOME}/FoundryVTT/topdirsize.sh" "$EXTRACT_DIR/"
    fi
    
    log_daemon_msg "Successfully extracted FoundryVTT ${VERSION} to ${EXTRACT_DIR}"
}

function validate_foundryvtt_zip() {
    local ZIP_FILE="$1"
    local TEMP_DIR=$(mktemp -d)
    
    # Check if it's a valid zip file
    if ! unzip -l "$ZIP_FILE" >/dev/null 2>&1; then
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Try to extract package.json from different possible locations
    local PACKAGE_JSON_CONTENT=""
    if unzip -p "$ZIP_FILE" "package.json" > "${TEMP_DIR}/package.json" 2>/dev/null; then
        PACKAGE_JSON_CONTENT="${TEMP_DIR}/package.json"
    elif unzip -p "$ZIP_FILE" "resources/app/package.json" > "${TEMP_DIR}/package.json" 2>/dev/null; then
        PACKAGE_JSON_CONTENT="${TEMP_DIR}/package.json"
    fi
    
    # If we found package.json content, validate it
    if [[ -n "$PACKAGE_JSON_CONTENT" ]]; then
        if ! validate_foundryvtt_package_json "$PACKAGE_JSON_CONTENT"; then
            rm -rf "$TEMP_DIR"
            return 1
        fi
    else
        # Check if package.json exists anywhere in the zip
        if ! unzip -l "$ZIP_FILE" | grep -q "package.json"; then
            log_failure_msg "Missing essential file: package.json"
            rm -rf "$TEMP_DIR"
            return 1
        fi
        # If package.json exists but we can't extract it, continue with structure validation
    fi
    
    # Check for FoundryVTT-specific indicators based on version type
    local found_any=false
    
    # Check for Node.js application structure (version 13+)
    if unzip -l "$ZIP_FILE" | grep -q "client/\|common/\|public/"; then
        found_any=true
    fi
    
    # Check for Electron application structure (version 12 and some older)
    if unzip -l "$ZIP_FILE" | grep -q "foundryvtt\|resources/app/\|libEGL.so\|libGLESv2.so"; then
        found_any=true
    fi
    
    # Check for other common FoundryVTT files
    if unzip -l "$ZIP_FILE" | grep -q "templates/\|license.html"; then
        found_any=true
    fi
    
    if [[ "$found_any" != "true" ]]; then
        log_failure_msg "Does not appear to be a FoundryVTT application (missing expected directories/files)"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    rm -rf "$TEMP_DIR"
    return 0
}

function validate_foundryvtt_app() {
    local APP_DIR="$1"
    
    # Check for package.json in different locations
    local package_path=""
    if [[ -f "${APP_DIR}/package.json" ]]; then
        package_path="${APP_DIR}/package.json"
    elif [[ -f "${APP_DIR}/resources/app/package.json" ]]; then
        package_path="${APP_DIR}/resources/app/package.json"
    fi
    
    if [[ -z "$package_path" ]]; then
        log_failure_msg "Missing essential file: package.json"
        return 1
    fi
    
    # Validate package.json
    if ! validate_foundryvtt_package_json "$package_path"; then
        return 1
    fi
    
    # Check for FoundryVTT-specific indicators based on application type
    local found_any=false
    
    # Check for Node.js application structure (version 13+)
    if [[ -d "${APP_DIR}/client" || -d "${APP_DIR}/common" || -d "${APP_DIR}/public" ]]; then
        found_any=true
    fi
    
    # Check for Electron application structure (version 12)
    if [[ -f "${APP_DIR}/foundryvtt" || -d "${APP_DIR}/resources" || -f "${APP_DIR}/libEGL.so" ]]; then
        found_any=true
    fi
    
    # Check for other common files
    if [[ -d "${APP_DIR}/templates" || -f "${APP_DIR}/license.html" ]]; then
        found_any=true
    fi
    
    if [[ "$found_any" != "true" ]]; then
        log_failure_msg "Does not appear to be a FoundryVTT application (missing expected directories/files)"
        return 1
    fi
    
    return 0
}

function validate_foundryvtt_package_json() {
    local PACKAGE_JSON="$1"
    
    if [[ ! -f "$PACKAGE_JSON" ]]; then
        return 1
    fi
    
    # Check if it's valid JSON
    if ! python3 -m json.tool "$PACKAGE_JSON" >/dev/null 2>&1; then
        log_failure_msg "Invalid JSON in package.json"
        return 1
    fi
    
    # Check for FoundryVTT-specific fields
    local name=$(python3 -c "import json; print(json.load(open('$PACKAGE_JSON'))['name'])" 2>/dev/null)
    local version=$(python3 -c "import json; print(json.load(open('$PACKAGE_JSON'))['version'])" 2>/dev/null)
    
    # Make name check case-insensitive and more flexible
    if ! [[ "${name,,}" == *"foundry"* ]]; then
        log_failure_msg "Package name does not contain 'foundry': $name"
        return 1
    fi
    
    if [[ -z "$version" ]]; then
        log_failure_msg "No version found in package.json"
        return 1
    fi
    
    # Validate version format (should be like 13.347, 12.330, 13.350.0, etc.)
    if ! [[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        log_failure_msg "Invalid version format: $version"
        return 1
    fi
    
    return 0
}

function get_foundryvtt_version() {
    local ZIP_FILE="$1"
    local TEMP_DIR=$(mktemp -d)
    
    # Try to extract package.json from different locations
    local package_path=""
    if unzip -p "$ZIP_FILE" "package.json" > "${TEMP_DIR}/package.json" 2>/dev/null; then
        package_path="${TEMP_DIR}/package.json"
    elif unzip -p "$ZIP_FILE" "resources/app/package.json" > "${TEMP_DIR}/package.json" 2>/dev/null; then
        package_path="${TEMP_DIR}/package.json"
    fi
    
    if [[ -z "$package_path" ]]; then
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Get version from package.json
    local version=$(python3 -c "import json; print(json.load(open('${TEMP_DIR}/package.json'))['version'])" 2>/dev/null)
    
    rm -rf "$TEMP_DIR"
    echo "$version"
}
