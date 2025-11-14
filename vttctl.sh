#!/bin/bash
set -euo pipefail
# Version: 0.05

IP_IDENT="4.ident.me"
#IP_IDENT="ifconfig.me/ip"

TMP_DIR="/tmp"
if [ -f "${HOME}/.bash_aliases" ]; then
      source "${HOME}/.bash_aliases"
      shopt -s expand_aliases
fi

VTT_HOME=$(pwd)
ENV_FILE="${VTT_HOME}/.env"

# Source helper scripts
source "${VTT_HOME}/src/logging.sh"
source "${VTT_HOME}/src/docker_helpers.sh"
source "${VTT_HOME}/src/workflow_backup.sh"
source "${VTT_HOME}/src/common.sh"
source "${VTT_HOME}/src/workflow_build.sh"
source "${VTT_HOME}/src/normalize_json.sh"
# Future: source "${VTT_HOME}/src/workflow_restore.sh"

# Check for required tools at the start and provide installation hints
REQUIRED_TOOLS=(basename cat curl cp date docker docker-compose free getent grep id ip jq rm python3 sed sort timedatectl uname unzip wc xargs awk)
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        log_failure_msg "Required tool '$tool' is not installed or not in PATH."
        log_failure_msg "Please install it using your package manager. Example: sudo apt install $tool"
        exit 1
    fi
done

# Set defaults for configurable variables
FOUNDRY_UID=${FOUNDRY_UID:-3000}
FOUNDRY_GID=${FOUNDRY_GID:-3000}
DOCKER_COMPOSE_FILE="${VTT_HOME}/docker/docker-compose.yml"
DOWNLOAD_HOME="${VTT_HOME}/downloads"

# Use mktemp for temporary files
function getVersion() {
    RESPONSE=$(mktemp)
    trap 'rm -f "$RESPONSE"' RETURN
    status=$(curl -s -w %{http_code} "http://localhost:${NGINX_PROD_PORT}/api/status" -H "Accept: application/json" -o "$RESPONSE")
    if [ "$status" == 200 ]; then
        JSON=$(cat "$RESPONSE")
        if echo "$JSON" | jq -e . >/dev/null 2>&1; then
            echo "$JSON"
        else
            # Return canonical error JSON
            jq -n --argjson http ${status} --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '{running:"error",http:$http,active:false,version:null,world:null,system:null,timestamp:$ts}'
        fi
    else
        jq -n --argjson http ${status} --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '{running:"error",http:$http,active:false,version:null,world:null,system:null,timestamp:$ts}'
    fi
}

# Output diagnostics.json (from running app container) to stdout if available
function output_diagnostics() {
    # Find running app container
    CONT_NAME=$(docker container ls -a --format "{{.ID}} {{.Names}} {{.Status}}" | awk '/vtt/ && /app/ {print $1; exit}')
    if [[ -z "${CONT_NAME:-}" ]]; then
        log_failure_msg "No running FoundryVTT app container found."
        return 1
    fi

    # Candidate paths inside container where diagnostics.json may be located
    CANDIDATES=("/home/foundry/userdata/Logs/diagnostics.json" "/home/foundry/userdata/diagnostics.json" "/home/foundry/userdata/diagnostics/diagnostics.json" "/home/foundry/diagnostics.json" "/usr/src/app/diagnostics.json" "/source/Logs/diagnostics.json")

    for path in "${CANDIDATES[@]}"; do
        if docker exec "${CONT_NAME}" test -f "${path}" >/dev/null 2>&1; then
            # Output raw JSON to stdout and format with jq on host if available
            if command -v jq >/dev/null 2>&1; then
                docker exec "${CONT_NAME}" cat "${path}" | jq . || docker exec "${CONT_NAME}" cat "${path}"
            else
                docker exec "${CONT_NAME}" cat "${path}"
            fi
            return 0
        fi
    done

    # If not found, attempt to create diagnostics using FoundryVTT's internal endpoint if available
    if docker exec "${CONT_NAME}" test -x /usr/local/bin/pm2 >/dev/null 2>&1; then
        # Try curl inside container to fetch /diagnostics (best-effort)
        if docker exec "${CONT_NAME}" sh -c "command -v curl >/dev/null 2>&1"; then
            if docker exec "${CONT_NAME}" sh -c "curl -sS --fail http://localhost:30000/diagnostics.json" >/dev/null 2>&1; then
                docker exec "${CONT_NAME}" curl -sS http://localhost:30000/diagnostics.json || true
                return 0
            fi
        fi
    fi

    log_failure_msg "diagnostics.json not found in container ${CONT_NAME}."
    return 2
}

# Remove the local definition of generateBackupListing

function progressCursor() {
            i=1
            sp="/-\|"
            echo -n ' '
            while [ -d /proc/"$1" ]; do
                printf "\r%c" "${sp:0:1}"
                sp="${sp:1}${sp:0:1}"
                sleep 0.05
            done
}

function prodBackup()  {
    METADATA_FILE="${BACKUP_HOME}metadata.json"
    json=$(getVersion)
    if jq -e . >/dev/null 2>&1 <<<"${json}"; then
        PROD_VER=$(echo "${json}" | jq -r .version)
        if [[ -n "${PROD_VER}" ]]; then
            DATESTAMP=$(date +"%Y%m%d")
            BACKUP_FILE="foundry_userdata_${PROD_VER}-${DATESTAMP}.tar"
            docker run \
                --rm \
                -v foundryvtt_UserData:/source/ \
                -v "${BACKUP_HOME}":/backup \
                busybox \
                ash -c "tar -cvf /backup/${BACKUP_FILE} -C / /source "

            docker run \
                --rm \
                -v "${BACKUP_HOME}":/backup \
                busybox \
                ash -c "chown ${UID}:${GID} /backup/${BACKUP_FILE}"

            DATE_FILE=$(stat --format="%y" "${BACKUP_HOME}/${BACKUP_FILE}" | awk '{print $1}')

            if [[ -f "${METADATA_FILE}" ]]; then
                rm "${METADATA_FILE}"
            fi

            shopt -s nullglob

            # Build metadata as a JSON object mapping date -> {version, filename, size}
            tmp_entries=$(mktemp)
            >"${tmp_entries}"
            for filename in "${BACKUP_HOME}"*.tar "${BACKUP_HOME}"*.tar.gz "${BACKUP_HOME}"*.tar.bz2; do
                if [[ -f "${filename}" ]]; then
                    basefile=$(basename "${filename}")
                    IFS="|" read -r version date <<< "$(parse_version "$basefile")"
                    size=$(stat -c "%s" "${filename}")
                    size_mb=$(awk -v size="${size}" 'BEGIN{printf "%.0f", (size / 1024 / 1024) + 0.5}')
                    # Emit one JSON object per line for jq to slurp
                    jq -n --arg date "${date}" --arg version "${version}" --arg filename "${WEB_PROTO}://${FQDN}/backups/${basefile}" --arg size "${size_mb} MB" '{date:$date,version:$version,filename:$filename,size:$size}' >> "${tmp_entries}"
                fi
            done

            # Construct final metadata mapping date -> object
            if [[ -s "${tmp_entries}" ]]; then
                jq -n 'reduce inputs as $i ({}; . + {($i.date): {version:$i.version, filename:$i.filename, size:$i.size}})' "${tmp_entries}" > "${METADATA_FILE}"
            else
                echo '{}' > "${METADATA_FILE}"
            fi
            rm -f "${tmp_entries}"

            log_daemon_msg "   - ${BACKUP_FILE} backup file created."

            # Rebuild metadata and listing, include md5 when creating backup
            rebuild_metadata "${BACKUP_HOME}" "${WEB_PROTO}" "${FQDN}" "${VTT_HOME}" "${MAJOR_VER}" "${BACKUP_REFRESH}" "${VTTCTL_VERSION}" "true"
            log_daemon_msg "   - metadata.json and backup listing updated."

            log_daemon_msg "   - Download it from ${WEB_PROTO}://${FQDN}/backups/"
        fi
    fi
}

function getParentDirectoriesToStrip() {
      tar_output=$(tar -tf "$1" | head -n 30)

      # Look for common parent directories among the paths
      parent_dirs=()

      while IFS= read -r line; do
      # Use the first path to initialize the parent_dirs array
      if [[ -z "${parent_dirs[@]}" ]]; then
            IFS="/" read -ra parts <<< "$line"
            parent_dirs=("${parts[@]}")
      else
            IFS="/" read -ra parts <<< "$line"
            for i in "${!parts[@]}"; do
                  if [[ "${parts[i]}" != "${parent_dirs[i]}" ]]; then
                  # Trim the parent_dirs array to the common parent
                  parent_dirs=("${parent_dirs[@]:0:i}")
                  break
                  fi
            done
      fi
      done <<< "$tar_output"

      # Calculate the value for --strip-components
      strip_components=${#parent_dirs[@]}

      echo "$strip_components"      
}

function prodLatestRestore() {
    REST_FILE=$(ls -t backups/FoundryVTT/*tar | head -1)
    FILE_NAME=$(basename "${REST_FILE}")
    
    docker run \
                --rm \
                -v foundryvtt_UserData:/source/ \
                -v $(pwd)/backups/FoundryVTT/:/backup \
                busybox \
                ash -c "tar -xvf /backup/${FILE_NAME} -C /source/ --strip-components=1"

}

function prodBackupRestore() {
      REST_FILE="$1"
      STRIP_COMPONENTS="$2"
      FILE_NAME=$(basename "${REST_FILE}")
      
      docker run \
            --rm \
            -v foundryvtt_UserData:/source/ \
            -v $(pwd)/backups/FoundryVTT/:/backup \
            busybox \
            ash -c "tar -xvf /backup/${FILE_NAME} -C /source/ --strip-components=${STRIP_COMPONENTS}; \
                    chown -R ${FOUNDRY_UID}:${FOUNDRY_GID} /source/"
}

function devLatestRestore() {
    REST_FILE=$(ls -t backups/*tar | head -1)
    FILE_NAME=$(basename "${REST_FILE}")
    CONT_NAME=$(docker container ls -a | awk '/vtt/ && /app/ {print $1}')
    
    docker run \
                --rm \
                --volumes-from "$CONT_NAME" \
                -v "$VTT_HOME"/backups/FoundryVTT/:/backup \
                busybox \
                tar -xvf /backup/${FILE_NAME} -C /

}

function fixOwner() {
    CONT_NAME=$(docker container ls -a | awk '/vtt/ && /app/ {print $1}')
    docker run --rm --volumes-from "${CONT_NAME}" busybox chown ${FOUNDRY_UID}:${FOUNDRY_GID} -R /home/foundry/userdata
}

function fixConfig() {
      # UPnP is not needed in current architecture.
      CONT_NAME=$(docker container ls -a | awk '/vtt/ && /app/ {print $1}')
      docker run --rm --volumes-from "${CONT_NAME}" busybox ash -c \
            "sed -i 's/\"upnp\": true/\"upnp\": false/' /home/foundry/userdata/Config/options.json"
}

function getIPaddrByGW() {
      # Only IPv4 supported at this time
      gateway_ip=$(ip route | awk '/default/ {if ($3 ~ /\./) print $3}' | sort -u)
      interface=$(ip route get "${gateway_ip}" | awk '/dev/ {print $3}')
      ip_address=$(ip -o -4 addr show dev "${interface}" | awk -F '[ /]+' '/inet / {print $4}')
      echo "${ip_address}"
}

function getReleases() {
    url="https://foundryvtt.com/releases/"
    html_content=$(curl -s "${url}")

    # Set custom record separator to </li>
    # Extract <li> elements containing the stable release
    stable_li_elements=$(awk -v RS='</li>' '/<span class="release-tag stable">Stable<\/span>/{print $0 "</li>"}' <<< "${html_content}")

    # Extract the release versions from stable <li> elements
    release_versions=$(echo "${stable_li_elements}" | grep -oP '(?<=<a href="/releases/)(9|[1-9][0-9]+)\.\d+')
    
    file_path="${VTT_HOME}/FoundryVTT/foundry_releases.json"
    max_age_days=1
    file_age=$(($(date +%s) - $(date -r "${file_path}" +%s)))
 
    versions=()
    current_version=""

    while IFS= read -r line; do
      version=$(echo "${line}" | awk -F '.' '{print $1}')
      build=$(echo "$line" | awk -F '.' '{print $2}')

      if [[ "${version}" != "${current_version}" ]]; then
            versions+=("{\"version\":\"${version}\",\"build\":[{\"number\":${build},\"latest\":false}]}")
            current_version="${version}"
      else
            index=$((${#versions[@]} - 1))
            versions[${index}]=$(jq ".build += [{\"number\":${build},\"latest\":false}]" <<< "${versions[$index]}")
            last_index=$((${index} - 1))
            versions[${last_index}]=$(jq ".build[-1].latest=true" <<< "${versions[${last_index}]}")
      fi
    done <<< "${output}"

    last_index=$((${#versions[@]} - 1))
    versions[${last_index}]=$(jq ".build[-1].latest=true" <<< "${versions[${last_index}]}")

    json=$(jq -n "{\"versions\":[$(IFS=,; echo "${versions[*]}")] }" 2>/dev/null)

    # Write releases file (already structured). No additional normalization required
    echo "${json}" > "${file_path}"

}

function isPlatformSupported() {
      matchFoundSupported=false
      matchFoundNotSupported=false

      platform="$1 $2 $3"
      supported=(
            "Ubuntu 24.04 aarch64"
            "Ubuntu 22.04 aarch64"
            "Ubuntu 22.04 x86_64"
            "Ubuntu 20.04 x86_64"
            "CentOS 7.9.2009 x86_64"
            "Rocky 8.8 x86_64"
            "Rocky 9.2 x86_64"
            "Debian 12 x86_64"
      )

      notsupported=(
            "CentOS 5 x86_64"
            "Debian 11 x86_64"
      )

      for p in "${supported[@]}"; do
            if [[ "${p}" == "${platform}" ]]; then
                  matchFoundSupported=true
                  echo -e "${light_green}supported${reset}"
                  break
            fi
      done

      for p in "${notsupported[@]}"; do
            if [[ "$p" == "$platform" ]]; then
                  matchFoundNotSupported=true
                  echo -e "${red}not supported${reset}"
                  break
            fi
      done

      if [[ ! ${matchFoundSupported} && ! ${matchFoundNotSupported} ]]; then
            echo -e "${light_yellow}not tested${reset}"
      fi
}

function getWebStatus() {
      WEB_CONTAINER=$(docker container ls -a | awk '/vtt/ && /web/ {print $1}')
      docker exec -it ${WEB_CONTAINER} ash -c "curl http://localhost/basic_status"       
}

# Compatibility wrappers for status output
function get_status_json() {
    json=$(getVersion)
    # Normalize and output canonical JSON schema
    normalize_json "${json:-}"
}


function get_status() {
    # Display system status information
    log_daemon_msg "System Status:"
    case "$OS_SUPPORT" in
        "supported")
            log_daemon_msg " OS: ${LINUX_DISTRO} ${DISTRO_VERSION} [${color_info}supported${color_reset}]"
            ;;
        "unsupported")
            log_daemon_msg " OS: ${LINUX_DISTRO} ${DISTRO_VERSION} [${color_error}unsupported${color_reset}]"
            ;;
        "not tested")
            log_daemon_msg " OS: ${LINUX_DISTRO} ${DISTRO_VERSION} [${color_warn}not tested${color_reset}]"
            ;;
    esac
    log_daemon_msg " CPU Architecture: ${CPU_ARCH}"
    log_daemon_msg " CPU Cores: ${CPU_COUNT}"
    log_daemon_msg " RAM: ${TOTAL_RAM}"
    log_daemon_msg " Local IP: ${LOCAL_IP}"
    log_daemon_msg " Public IP: ${PUBLIC_IP}"
    log_daemon_msg " Ethernet: ${ETHERNET}"
    log_end_msg 0
}

# Helper logging functions moved to src/logging.sh
#      function log_begin_msg() { ... }
#      function log_daemon_msg() { ... }
#      function log_warning_msg() { ... }
#      function log_failure_msg() { ... }
#      function log_end_msg() { ... }

# Docker/container helper functions moved to src/docker_helpers.sh
# function stop() { ... }
# function getLogs() { ... }
# function liveLogs() { ... }
# function appReload() { ... }
# ...etc...

# Centralized user input functions
prompt_user_choice() {
    local prompt="$1"
    local max_choice="$2"
    local choice
    while true; do
        read -p "$prompt" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 0 && choice <= max_choice )); then
            echo "$choice"
            return 0
        else
            log_warning_msg "Invalid option. Please enter a number between 0 and $max_choice."
        fi
    done
}

prompt_user_confirm() {
    local prompt="${1:-Are you sure? (y/n): }"
    local answer
    while true; do
        read -p "$prompt" answer
        case "$answer" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) log_warning_msg "Please answer y or n." ;;
        esac
    done
}

# Reusable function: check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1 || type "$1" >/dev/null 2>&1
}

# Reusable function: print a numbered list from an array
print_numbered_array() {
    local -n arr=$1
    local default="$2"
    for i in "${!arr[@]}"; do
        idx=$((i+1))
        if [[ "${arr[$i]}" == "$default" ]]; then
            echo -e " $idx) ${green}${arr[$i]}${reset}"
        else
            echo " $idx) ${arr[$i]}"
        fi
    done
    printf " %2d) Cancel\n" 0
}

# Helper function for cleanup numbered list
print_numbered_list() {
    local items="$1"
    local default="$2"
    local arr=()
    # Convert items to array
    read -ra arr <<< "$items"
    for i in "${!arr[@]}"; do
        idx=$((i+1))
        if [[ "${arr[$i]}" == "$default" ]]; then
            echo -e " $idx) ${green}${arr[$i]}${reset}"
        else
            echo " $idx) ${arr[$i]}"
        fi
    done
    printf " %2d) Cancel\n" 0
}

# Cleanup helper functions
function cleanup_versions() {
    local VALUE="${1:-}"
    # Build candidate lists
    DIR_VERSIONS=$(ls -ld "${VTT_HOME}/FoundryVTT/"*[0-9]* 2>/dev/null | awk '/^d/ {print $NF}' || true)
    IMG_VERSIONS=$(docker images -a | grep vtt | awk '{print $1":"$2}' 2>/dev/null | awk -F: '{print $2}' || true)
    BIN_VERSIONS=$(ls "${VTT_HOME}/downloads/" 2>/dev/null | grep -E '[0-9]{1,3}\.[0-9]{1,3}' || true)

    declare -A counts
    counts[DIR_VERSIONS]=$(echo "${DIR_VERSIONS}" | wc -w)
    counts[IMG_VERSIONS]=$(echo "${IMG_VERSIONS}" | wc -w)
    counts[BIN_VERSIONS]=$(echo "${BIN_VERSIONS}" | wc -w)

    max=0; maxvar=""
    for k in "${!counts[@]}"; do
        if (( counts[$k] > max )); then
            max=${counts[$k]}
            maxvar=$k
        fi
    done

    if [[ -n "${maxvar}" && ${max} -gt 0 ]]; then
        BIGGEST="${!maxvar}"
    else
        echo "Nothing to cleanup."
        exit 1
    fi

    # Convert to array of version strings
    version_list=()
    for entry in ${BIGGEST}; do
        ver=$(parse_version "$entry" | cut -d'|' -f1)
        if [[ -n "$ver" ]]; then
            version_list+=("$ver")
        fi
    done
    # Remove duplicates
    version_list=($(echo "${version_list[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

    pattern="^[0-9]{1,3}\.[0-9]{1,3}$"
    DEFAULT_VER=${DEFAULT_VER:-null}

    # Non-interactive if VALUE provided: delete specified version
    if [[ -n "${VALUE}" ]]; then
        DEL_VER="${VALUE}"
        if ! [[ "${DEL_VER}" =~ ${pattern} ]]; then
            log_failure_msg "Invalid version format: ${DEL_VER}"
            exit 1
        fi
        if prompt_user_confirm "Are you sure you want to remove all v${DEL_VER} related assets? (y/n): "; then
            log_daemon_msg "Deleting zip file ..."
            rm -f -- "${VTT_HOME}/downloads/"*${DEL_VER}* >/dev/null 2>&1 || true
            log_daemon_msg "Deleting extracted folder ..."
            rm -rf -- "${VTT_HOME}/FoundryVTT/${DEL_VER}/" >/dev/null 2>&1 || true
            log_daemon_msg "Deleting Docker image ..."
            docker image rm "foundryvtt:${DEL_VER}" >/dev/null 2>&1 || true
            log_daemon_msg "Cleaning completed."
            exit 0
        else
            log_failure_msg "Operation cancelled."
            exit 1
        fi
    fi

    # Interactive selection (fallback)
    count=${#version_list[@]}
    OPT=""
    while [[ ${OPT} != "0" ]]; do
        echo "Choose version to clean/delete ('0' to cancel):"
        print_numbered_list "${version_list[*]}" "${DEFAULT_VER}"
        OPT=$(prompt_user_choice "Version to clean/delete?: " $count)

        case ${OPT} in
            [1-9]*)
                ((OPT--))
                DEL_VER=${version_list[$OPT]}
                if prompt_user_confirm "Are you sure you want to remove all v${DEL_VER} related assets? (y/n): "; then
                    log_daemon_msg "Deleting zip file ..."
                    rm -f -- "${VTT_HOME}/downloads/"*${DEL_VER}* >/dev/null 2>&1 || true
                    log_daemon_msg "Deleting extracted folder ..."
                    rm -rf -- "${VTT_HOME}/FoundryVTT/${DEL_VER}/" >/dev/null 2>&1 || true
                    log_daemon_msg "Deleting Docker image ..."
                    docker image rm "foundryvtt:${DEL_VER}" >/dev/null 2>&1 || true
                    log_daemon_msg "Cleaning completed."
                fi
                break
                ;;
            0)
                log_failure_msg "Cleaning cancelled."
                false
                log_end_msg
                break
                ;;
            *)
                echo "Invalid option."
                ;;
        esac
    done

    exit 1
}

function cleanup_backups() {
    local VALUE="$1"
    mapfile -t BACKUP_FILES < <(find "${BACKUP_HOME}" -maxdepth 1 -name "*.tar*" -type f 2>/dev/null || true)

    if [[ ${#BACKUP_FILES[@]} -eq 0 ]]; then
        echo "No backup files found in ${BACKUP_HOME}"
        exit 1
    fi

    # Non-interactive if VALUE provided -> treat as filename or basename
    if [[ -n "${VALUE}" ]]; then
        TARGET_FILE="${VALUE}"
        if [[ -f "${TARGET_FILE}" ]]; then
            FILEPATH="${TARGET_FILE}"
            BASENAME=$(basename "${TARGET_FILE}")
        else
            FILEPATH="${BACKUP_HOME}${TARGET_FILE}"
            BASENAME="${TARGET_FILE}"
        fi

        if [[ -f "${FILEPATH}" ]]; then
            if prompt_user_confirm "Delete backup ${BASENAME}? (y/n): "; then
                rm -f -- "${FILEPATH}"
                
                # rebuild metadata.json and index.html after deletion (no md5)
                IFS="|" read -r parsed_ver parsed_date <<< "$(parse_version "${BASENAME}")"
                MAJOR_VER="${parsed_ver%%.*}"
                MAJOR_VER=${MAJOR_VER:-13}
                VTTCTL_VERSION="${VTTCTL_MAJ:-}.${VTTCTL_MIN:-} Build ${VTTCTL_BUILD:-}"
                if rebuild_metadata "${BACKUP_HOME}" "${WEB_PROTO}" "${FQDN}" "${VTT_HOME}" "${MAJOR_VER}" "${BACKUP_REFRESH}" "${VTTCTL_VERSION}" "false"; then
                    log_daemon_msg "Backup '${BASENAME}' deleted and listing updated."
                    exit 0
                else
                    log_failure_msg "Backup '${BASENAME}' deleted but failed to update listing (see logs)."
                    exit 1
                fi
            else
                log_failure_msg "Operation cancelled."
                exit 1
            fi
        else
            log_failure_msg "Backup file not found: ${TARGET_FILE}"
            exit 1
        fi
    fi

    # Interactive listing and deletion
    echo "Choose backup to delete ('0' to cancel):"
    for i in "${!BACKUP_FILES[@]}"; do
        idx=$((i+1))
        printf " %2d) %s\n" "${idx}" "$(basename "${BACKUP_FILES[$i]}")"
    done
    printf " %2d) Cancel\n" 0

    CHOICE=$(prompt_user_choice "Backup to delete?: " $(( ${#BACKUP_FILES[@]} )))
    if [[ "${CHOICE}" == "0" ]]; then
        log_failure_msg "Cleaning cancelled."
        exit 1
    fi
    ((CHOICE--))
    DEL_PATH="${BACKUP_FILES[$CHOICE]}"
    DEL_NAME=$(basename "${DEL_PATH}")
    if prompt_user_confirm "Are you sure you want to delete backup ${DEL_NAME}? (y/n): "; then
        rm -f -- "${DEL_PATH}" >/dev/null 2>&1 || true
        
        # rebuild metadata.json and index.html after deletion (no md5)
        IFS="|" read -r parsed_ver parsed_date <<< "$(parse_version "${DEL_NAME}")"
        MAJOR_VER="${parsed_ver%%.*}"
        MAJOR_VER=${MAJOR_VER:-13}
        VTTCTL_VERSION="${VTTCTL_MAJ:-}.${VTTCTL_MIN:-} Build ${VTTCTL_BUILD:-}"
        if rebuild_metadata "${BACKUP_HOME}" "${WEB_PROTO}" "${FQDN}" "${VTT_HOME}" "${MAJOR_VER}" "${BACKUP_REFRESH}" "${VTTCTL_VERSION}" "false"; then
            log_daemon_msg "Backup '${DEL_NAME}' deleted and listing updated."
        else
            log_failure_msg "Backup '${DEL_NAME}' deleted but failed to update listing (see logs)."
            exit 1
        fi
    else
        log_failure_msg "Operation cancelled."
        exit 1
    fi
    exit 0
}

# Validate if environment is setted up
if [[ ! -f ${ENV_FILE} &&  ${1:-} != "validate" ]]; then
    $0 validate
elif [ -f ${ENV_FILE} ]; then
      if [ "${USER}" != "root" ] && ! id -nG "${USER}" | grep -qw "docker"; then
            log_failure_msg "Do not run vttctl as root, add ${USER} to docker group."
            log_failure_msg " - example: sudo usermod -aG docker ${USER}"
            exit 1
      fi 
      export $(cat ${ENV_FILE} | xargs)
fi

# App Variables
VTT_NAME=FoundryVTT
NAME=${VTT_NAME}
PROD_PROJECT="${NAME}_prod"
PROD_PROJECT=${PROD_PROJECT,,}
DEV_PROJECT="${NAME}_dev"
DEV_PROJECT=${DEV_PROJECT,,}
REGEX_URL='(https?)://[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|]'
TAG=${DEFAULT_VER}
if [ ! -z ${HOSTNAME} ]; then
      FQDN=${HOSTNAME}.${DOMAIN}
else
      FQDN=${DOMAIN}
fi

# Create VARS with base64 encoded environment variables for the container
VARS_DATA="FQDN=${FQDN}\nPROXY_PORT=${PROXY_PORT}\nUPNP=${UPNP}"
VARS=$(echo -e "${VARS_DATA}" | base64 -w 0)

if [[ ${SSL_ENABLED} == "true" ]]; then
      WEB_PROTO="https"
else
      WEB_PROTO="http"
fi
BACKUP_REFRESH=300000 # 5 Minutes delay


# Linux/bash OS Variables
DESC=Environment
black='\e[30m'
red='\e[31m'
green='\e[32m'
yellow='\e[33m'
blue='\e[34m'
magenta='\e[35m'
cyan='\e[36m'
white='\e[37m'
reset='\e[0m'
light_black='\e[90m'
light_red='\e[91m'
light_green='\e[92m'
light_yellow='\e[93m'
light_blue='\e[94m'
light_magenta='\e[95m'
light_cyan='\e[96m'
light_white='\e[97m'

BACKUP_HOME="${VTT_HOME}/backups/FoundryVTT/"
GID=$(getent passwd ${USER} | awk -F: '{print $4}')
CPU_COUNT=$(awk '/^processor/ {count++} END {print count}' /proc/cpuinfo)
TOTAL_RAM=$(free -mh | sed -n '2 s/i/B/gp' | awk '{print $2}')
LOCAL_IP=$(getIPaddrByGW)
ETHERNET=$(ip add | grep -v altname | grep -B2 ${LOCAL_IP} | grep UP | awk {'print $2'} | awk '{sub(/.$/,"")}1')
PUBLIC_IP=$(curl -s ${IP_IDENT})

LINUX_DISTRO="N/A lsb_release missing"

# Distro detection
if [ -f /etc/debian_version ]; then # Ubuntu/Debian validation
      deb_version=$(< /etc/debian_version)
      if type "lsb_release" >/dev/null 2>&1; then
            if [[ $deb_version == *"sid"* ]]; then
                  LINUX_DISTRO=$(lsb_release -si)
                  DISTRO_VERSION=$(lsb_release -rs)
            else
                  LINUX_DISTRO=$(lsb_release -si 2>/dev/null)
                  DISTRO_VERSION=$(lsb_release -rs 2>/dev/null)
            fi
      fi
elif [ -f /etc/redhat-release ] || [ -f /etc/rocky-release ]; then # CentOS/RockyLinux validation
      if type "lsb_release" >/dev/null 2>&1; then
            LINUX_DISTRO=$(lsb_release -si)
            DISTRO_VERSION=$(lsb_release -sr)
      else
            LINUX_DISTRO=$(cat /etc/rocky-release | awk {'print $1'})
            DISTRO_VERSION=$(cat /etc/rocky-release | awk {'print $4'})

      fi
else # Default LSB
      LINUX_DISTRO=$(lsb_release -sir | head -1)
      DISTRO_VERSION=$(lsb_release -sir | tail -1)
fi

# CPU Architecture
if ! type "uname" >/dev/null 2>&1; then
      CPU_ARCH="N/A uname missing."
else
      CPU_ARCH=$(uname -m)
fi

# OS Support Status
OS_SUPPORT="not tested"
if [[ "$CPU_ARCH" == "x86_64" || "$CPU_ARCH" == "aarch64" ]]; then
    case "$LINUX_DISTRO" in
        "Ubuntu")
            if [[ "$DISTRO_VERSION" =~ ^(20\.04|22\.04|24\.04)$ ]]; then
                OS_SUPPORT="supported"
            else
                OS_SUPPORT="unsupported"
            fi
            ;;
        "Debian")
            if [[ "$DISTRO_VERSION" =~ ^(10|11|12)$ ]]; then
                OS_SUPPORT="supported"
            else
                OS_SUPPORT="unsupported"
            fi
            ;;
        "CentOS"|"Rocky Linux")
            if [[ "$DISTRO_VERSION" =~ ^(7|8|9)$ ]]; then
                OS_SUPPORT="supported"
            else
                OS_SUPPORT="unsupported"
            fi
            ;;
        *)
            OS_SUPPORT="not tested"
            ;;
    esac
else
    OS_SUPPORT="unsupported"
fi

function run_config_wizard() {
    echo "========================================"
    echo "  vttctl Configuration Wizard"
    echo "========================================"
    echo ""
    echo "This wizard will help you configure your .env file."
    echo "Press Enter to accept default values in brackets."
    echo "Current values (if any) are shown in parentheses."
    echo ""

    # Load existing values if .env exists
    if [[ -f "$ENV_FILE" ]]; then
        echo "Loading existing configuration..."
        source "$ENV_FILE" 2>/dev/null || true
    fi

    # NGINX_PROD_PORT
    current_nginx="${NGINX_PROD_PORT:-30000}"
    read -p "Nginx production port [$current_nginx]: " nginx_port
    NGINX_PROD_PORT="${nginx_port:-$current_nginx}"
    if ! [[ "$NGINX_PROD_PORT" =~ ^[0-9]+$ ]] || [ "$NGINX_PROD_PORT" -lt 1 ] || [ "$NGINX_PROD_PORT" -gt 65535 ]; then
        echo "Invalid port number. Using default: 30000"
        NGINX_PROD_PORT=30000
    fi

    # NGINX_DEV_PORT
    current_dev="${NGINX_DEV_PORT:-9043}"
    read -p "Nginx development port [$current_dev]: " dev_port
    NGINX_DEV_PORT="${dev_port:-$current_dev}"
    if ! [[ "$NGINX_DEV_PORT" =~ ^[0-9]+$ ]] || [ "$NGINX_DEV_PORT" -lt 1 ] || [ "$NGINX_DEV_PORT" -gt 65535 ]; then
        echo "Invalid port number. Using default: 9043"
        NGINX_DEV_PORT=9043
    fi

    # PUBLIC_PROD_PORT
    current_public="${PUBLIC_PROD_PORT:-80}"
    read -p "Public production port [$current_public]: " public_port
    PUBLIC_PROD_PORT="${public_port:-$current_public}"
    if ! [[ "$PUBLIC_PROD_PORT" =~ ^[0-9]+$ ]] || [ "$PUBLIC_PROD_PORT" -lt 1 ] || [ "$PUBLIC_PROD_PORT" -gt 65535 ]; then
        echo "Invalid port number. Using default: 80"
        PUBLIC_PROD_PORT=80
    fi

    # SSL_ENABLED
    current_ssl="${SSL_ENABLED:-false}"
    read -p "Enable SSL/HTTPS? (true/false) [$current_ssl]: " ssl_enabled
    SSL_ENABLED="${ssl_enabled:-$current_ssl}"
    case "${SSL_ENABLED,,}" in
        true|false) ;;
        *) echo "Invalid value. Using default: false"; SSL_ENABLED=false ;;
    esac

    # HOSTNAME
    current_hostname="${HOSTNAME:-vtt}"
    read -p "Hostname prefix for FQDN [$current_hostname]: " hostname
    HOSTNAME="${hostname:-$current_hostname}"
    # Basic validation - no spaces or special chars
    if [[ "$HOSTNAME" =~ [^a-zA-Z0-9\-] ]]; then
        echo "Warning: Hostname contains special characters. This may cause issues."
    fi

    # DOMAIN
    current_domain="${DOMAIN:-localhost}"
    read -p "Domain name [$current_domain]: " domain
    DOMAIN="${domain:-$current_domain}"

    # DEFAULT_VER
    current_default="${DEFAULT_VER:-}"
    read -p "Default FoundryVTT version (leave empty for latest) [$current_default]: " default_ver
    DEFAULT_VER="${default_ver:-$current_default}"

    # TIMEZONE
    current_tz="${TIMEZONE:-UTC}"
    read -p "Timezone [$current_tz]: " timezone
    TIMEZONE="${timezone:-$current_tz}"

    # FOUNDRY_UID
    current_uid="${FOUNDRY_UID:-3000}"
    read -p "FoundryVTT user ID [$current_uid]: " foundry_uid
    FOUNDRY_UID="${foundry_uid:-$current_uid}"
    if ! [[ "$FOUNDRY_UID" =~ ^[0-9]+$ ]] || [ "$FOUNDRY_UID" -lt 1000 ] || [ "$FOUNDRY_UID" -gt 65535 ]; then
        echo "Invalid UID. Using default: 3000"
        FOUNDRY_UID=3000
    fi

    # FOUNDRY_GID
    current_gid="${FOUNDRY_GID:-3000}"
    read -p "FoundryVTT group ID [$current_gid]: " foundry_gid
    FOUNDRY_GID="${foundry_gid:-$current_gid}"
    if ! [[ "$FOUNDRY_GID" =~ ^[0-9]+$ ]] || [ "$FOUNDRY_GID" -lt 1000 ] || [ "$FOUNDRY_GID" -gt 65535 ]; then
        echo "Invalid GID. Using default: 3000"
        FOUNDRY_GID=3000
    fi

    # DEV_ENABLED
    current_dev_enabled="${DEV_ENABLED:-false}"
    read -p "Enable development environment? (true/false) [$current_dev_enabled]: " dev_enabled
    DEV_ENABLED="${dev_enabled:-$current_dev_enabled}"
    case "${DEV_ENABLED,,}" in
        true|false) ;;
        *) echo "Invalid value. Using default: false"; DEV_ENABLED=false ;;
    esac

    echo ""
    echo "========================================"
    echo "Configuration Summary:"
    echo "========================================"
    echo "NGINX_PROD_PORT=$NGINX_PROD_PORT"
    echo "NGINX_DEV_PORT=$NGINX_DEV_PORT"
    echo "PUBLIC_PROD_PORT=$PUBLIC_PROD_PORT"
    echo "SSL_ENABLED=$SSL_ENABLED"
    echo "HOSTNAME=$HOSTNAME"
    echo "DOMAIN=$DOMAIN"
    echo "DEFAULT_VER=$DEFAULT_VER"
    echo "TIMEZONE=$TIMEZONE"
    echo "FOUNDRY_UID=$FOUNDRY_UID"
    echo "FOUNDRY_GID=$FOUNDRY_GID"
    echo "DEV_ENABLED=$DEV_ENABLED"
    echo ""

    read -p "Save this configuration? (y/n) [y]: " save_config
    save_config="${save_config:-y}"
    case "${save_config,,}" in
        y|yes)
            cat > "$ENV_FILE" << EOF
# vttctl configuration generated by wizard on $(date)
NGINX_PROD_PORT=$NGINX_PROD_PORT
NGINX_DEV_PORT=$NGINX_DEV_PORT
PUBLIC_PROD_PORT=$PUBLIC_PROD_PORT
SSL_ENABLED=$SSL_ENABLED
HOSTNAME=$HOSTNAME
DOMAIN=$DOMAIN
DEFAULT_VER=$DEFAULT_VER
TIMEZONE=$TIMEZONE
FOUNDRY_UID=$FOUNDRY_UID
FOUNDRY_GID=$FOUNDRY_GID
DEV_ENABLED=$DEV_ENABLED
EOF
            echo "Configuration saved to $ENV_FILE"
            echo "You can now run './vttctl.sh validate' to check your setup."
            ;;
        *)
            echo "Configuration not saved."
            ;;
    esac
}


function upgrade_version() {
    local target_version="$1"
    if [[ -z "$target_version" ]]; then
        log_failure_msg "Usage: $0 upgrade <version>"
        return 1
    fi

    local ENV_FILE="${VTT_HOME}/.env"
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
    fi

    # Check if target version is higher than current
    if [[ -n "$DEFAULT_VER" ]]; then
        if ! [[ "$target_version" =~ ^[0-9]+\.[0-9]+$ ]]; then
            log_failure_msg "Invalid version format. Expected: major.minor"
            return 1
        fi
        if [[ "$(printf '%s\n' "$target_version" "$DEFAULT_VER" | sort -V | head -n1)" == "$target_version" && "$target_version" != "$DEFAULT_VER" ]]; then
            log_failure_msg "Target version $target_version is not higher than current default $DEFAULT_VER"
            return 1
        fi
    fi

    log_daemon_msg "Upgrading to FoundryVTT version $target_version..."

    # Check if version is extracted
    if [[ ! -d "${VTT_HOME}/FoundryVTT/${target_version}" ]]; then
        log_failure_msg "Version $target_version not found. Please download and extract it first."
        return 1
    fi

    # Build the image
    export FORCE_REBUILD=false  # or true if needed
    if ! build_image "$target_version"; then
        log_failure_msg "Failed to build image for version $target_version"
        return 1
    fi

    # Set as default
    if [[ -f "$ENV_FILE" ]]; then
        sed -i "s/^DEFAULT_VER=.*/DEFAULT_VER=${target_version}/" "$ENV_FILE"
    else
        echo "DEFAULT_VER=${target_version}" > "$ENV_FILE"
    fi

    # Restart services
    if ! restart_services; then
        log_failure_msg "Failed to restart services after upgrade"
        return 1
    fi

    log_daemon_msg "Upgrade to $target_version completed successfully."
}


function restore_from_tar() {
    local tar_file="$1"
    if [[ -z "$tar_file" ]]; then
        log_failure_msg "Usage: $0 restore-tar <path_to_tar_file>"
        return 1
    fi
    if [[ ! -f "$tar_file" ]]; then
        log_failure_msg "Tar file not found: $tar_file"
        return 1
    fi

    local file_name=$(basename "$tar_file")
    local dir_name=$(dirname "$tar_file")

    log_daemon_msg "Restoring from $tar_file..."

    # Determine compression and strip components
    local tar_cmd="tar"
    if [[ "$file_name" == *.tar.gz ]]; then
        tar_cmd="tar -xzf"
    elif [[ "$file_name" == *.tar.bz2 ]]; then
        tar_cmd="tar -xjf"
    elif [[ "$file_name" == *.tar ]]; then
        tar_cmd="tar -xf"
    else
        log_failure_msg "Unsupported file format. Supported: .tar, .tar.gz, .tar.bz2"
        return 1
    fi

    # Extract to volume, assuming strip-components=1 for backups
    docker run \
        --rm \
        -v foundryvtt_UserData:/source/ \
        -v "$dir_name":/backup \
        busybox \
        ash -c "$tar_cmd /backup/${file_name} -C /source/ --strip-components=1; \
                chown -R ${FOUNDRY_UID}:${FOUNDRY_GID} /source/"

    log_daemon_msg "Restore from tar completed."
}


function restore_backup() {
    log_daemon_msg "Restoring from latest backup..."
    prodLatestRestore
    log_daemon_msg "Restore completed."
}


function select_default_version() {
    local VTT_HOME="${VTT_HOME:-$(pwd)}"
    local FOUNDRY_JSON="${VTT_HOME}/FoundryVTT/foundryvtt.json"
    local ENV_FILE="${VTT_HOME}/.env"

    # Source .env for current DEFAULT_VER
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
    local versions=()

    for dir in "${VTT_HOME}/FoundryVTT/"*; do
        if [[ -d "$dir" && $(basename "$dir") =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
            local version=$(basename "$dir")
            versions+=("$version")
        fi
    done

    if [[ ${#versions[@]} -eq 0 ]]; then
        log_failure_msg "No extracted FoundryVTT versions found in ${VTT_HOME}/FoundryVTT/"
        return 1
    fi

    # Sort versions
    IFS=$'\n' versions=($(sort -V <<<"${versions[*]}"))
    unset IFS

    # Interactive selection with color for current default
    log_daemon_msg "Select FoundryVTT version to set as default:"
    local i=1
    for ver in "${versions[@]}"; do
        if [[ "$ver" == "$DEFAULT_VER" ]]; then
            echo -e "$i) \033[32m$ver (current default)\033[0m"
        else
            echo "$i) $ver"
        fi
        ((i++))
    done
    echo -n "Enter choice (0 to cancel, 1-${#versions[@]}): "
    read -r choice
    if [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 0 && choice <= ${#versions[@]} )); then
        if [[ $choice -eq 0 ]]; then
            log_daemon_msg "Selection cancelled."
            return 1
        fi
        local selected_version="${versions[$((choice-1))]}"
        log_daemon_msg "Setting default version to: ${selected_version}"
        # Update .env
        if [[ -f "$ENV_FILE" ]]; then
            sed -i "s/^DEFAULT_VER=.*/DEFAULT_VER=${selected_version}/" "$ENV_FILE"
        else
            echo "DEFAULT_VER=${selected_version}" > "$ENV_FILE"
        fi
        log_daemon_msg "Default version updated. Run 'restart' to apply changes."
    else
        log_failure_msg "Invalid selection."
        return 1
    fi
}


function print_help() {
    cat <<EOF
vttctl.sh - FoundryVTT Docker Orchestration Utility
Version: 0.05

DESCRIPTION:
    vttctl is a comprehensive tool for managing FoundryVTT installations using Docker.
    It handles downloading, building, running, backing up, and restoring FoundryVTT
    instances with minimal configuration required.

USAGE:
    ./vttctl.sh <command> [options] [arguments]

CORE COMMANDS:
    validate        Check system dependencies and generate .env file if missing
    wizard          Interactive configuration wizard for .env file setup
    download <url>  Download FoundryVTT from timed URL (Linux/NodeJS platform)
    build           Build Docker image for selected FoundryVTT version (interactive)
    start           Start FoundryVTT production services
    stop            Stop FoundryVTT services
    info            Display FoundryVTT status information

MANAGEMENT COMMANDS:
    backup          Create backup of FoundryVTT user data (--cleanup for cleanup)
    restore         Restore user data from backup (interactive selection)
    restore-tar <file> Restore user data from external tar file (.tar, .tar.gz, .tar.bz2)
    restoredev      Restore latest development backup
    default         Set default FoundryVTT version (interactive)
    upgrade <ver>   Upgrade to higher FoundryVTT version (build + default + restart)
    clean           Remove Docker containers (--all removes user data volumes)
    cleanup         Remove Docker images, binaries, and extracted folders

MONITORING & DIAGNOSTICS:
    logs            Show container logs (--live for live tailing)
    web             Show Nginx web container status
    monitor         Attach to PM2 process monitor in running container
    diag            Output diagnostics.json from running container
    status          Display system status information

DEVELOPMENT & UTILITIES:
    extract <ver>   Extract downloaded FoundryVTT zip for specific version
    attach          Attach to running FoundryVTT app container shell

OPTIONS:
    --all           Remove all user data and volumes (with clean/cleanup)
    --force         Force rebuild of running version (with build)
    --live          Live log tailing (with logs)
    --cleanup       Interactive cleanup of old backups (with backup)

EXAMPLES:
    # Initial setup
    ./vttctl.sh wizard
    ./vttctl.sh validate
    ./vttctl.sh download "https://foundryvtt.com/releases/download?version=11.315&platform=linux"
    ./vttctl.sh build
    ./vttctl.sh start

    # Basic operations
    ./vttctl.sh info
    ./vttctl.sh logs --live
    ./vttctl.sh backup

    # Maintenance
    ./vttctl.sh stop
    ./vttctl.sh clean --all
    ./vttctl.sh restore

ENVIRONMENT VARIABLES (.env file):
    DEFAULT_VER      Default FoundryVTT version to run
    NGINX_PROD_PORT  Port for Nginx reverse proxy (default: 30000)
    PUBLIC_PROD_PORT Public port for FoundryVTT access
    DOMAIN           Public domain for FoundryVTT
    HOSTNAME         Hostname prefix for FQDN
    SSL_ENABLED      Enable HTTPS ("true"/"false")
    DEV_ENABLED      Enable development environment ("true"/"false")
    FOUNDRY_UID      User ID for FoundryVTT process (default: 3000)
    FOUNDRY_GID      Group ID for FoundryVTT process (default: 3000)

DIRECTORY STRUCTURE:
    FoundryVTT/             # Extracted FoundryVTT versions and templates
    ├── Dockerfile.<major>  # Version-specific Dockerfiles
    ├── docker-entrypoint.sh # Container entrypoint script
    └── foundryvtt.json     # Version compatibility data
    backups/FoundryVTT/     # Backup tarballs and index.html
    downloads/              # Downloaded FoundryVTT zip files
    docker/                 # Docker Compose files and Nginx config
    templates/              # Jinja2 templates for dynamic generation
    docs/                   # Generated documentation
    test/                   # BATS test suite

SUPPORTED PLATFORMS:
    - Debian/Ubuntu 20.04+
    - CentOS/Rocky Linux 7, 8, 9
    - Architectures: amd64, aarch64

For detailed documentation, see README.md or docs/commands.md
For issues and contributions: https://github.com/lloZanos81/vttctl

EOF
}

function show_info() {
    json=$(getVersion)
    if [[ ! -z "$json" ]]; then
        if jq -e . >/dev/null 2>&1 <<<"$json"; then
                IS_ACTIVE=$(echo $json | jq .active)
                VERSION=$(echo $json | jq -r .version)
                if [ "$IS_ACTIVE" = "true" ]; then
                        WORLD=$(echo $json | jq -r .world)
                        SYSTEM=$(echo $json | jq -r .system)
                        log_daemon_msg "Foundry VTT v$VERSION is running."
                        log_daemon_msg " System: ${SYSTEM}"
                        log_daemon_msg " World: ${WORLD//-/ }"
                        true
                        log_end_msg $?
                else
                        log_daemon_msg "Foundry VTT v$VERSION is running BUT world not active."
                        true
                        log_end_msg $?
                fi
        else
                false
                log_daemon_msg "Foundry VTT is not running."
                log_end_msg $?
        fi
    else
        log_daemon_msg "Foundry VTT is not running."
        log_end_msg $?
    fi
}

if [[ $# -eq 0 ]]; then
    print_help
    exit 0
fi

case "$1" in
  help|-h|--help)
        print_help
        exit 0
        ;;
  attach)
        APP_CONTAINER=$(docker container ls -a | awk '/vtt/ && /app/ {print $1}')
        RUNNING_VER=$(docker container ls -a | awk '/vtt/ && /app/ { split($2, a, ":"); print a[2] }')
        echo ' '
        docker exec -it ${APP_CONTAINER} ash -c "echo Attaching to FoundryVTT ${RUNNING_VER} app container ...; export PS1=\"FoundryVTT:$ \"; cd; ls -l; echo ' ' ; /bin/ash"
        log_daemon_msg "Detaching from FoundryVTT ${RUNNING_VER} app container."
        log_end_msg $?
        exit 1
        ;;
  backup)
        # Do not allow starting backups unless running inside tmux or screen.
        # This prevents accidental interactive restores/backups that may require
        # a persistent session.
        if [[ -z "${STY:-}" && -z "${TMUX:-}" ]]; then
            log_failure_msg "Backups must be run inside tmux or screen. Aborting."
            exit 1
        fi

    if [[ "${2:-}" == "--cleanup" ]]; then
            log_daemon_msg "Starting interactive backup cleanup."
            # Set MAJOR_VER for rebuild_metadata, default to 13
            MAJOR_VER="${MAJOR_VER:-13}"
            cleanup_backups "${BACKUP_HOME}" "${WEB_PROTO}" "${FQDN}" "${VTT_HOME}" "${MAJOR_VER}" "${BACKUP_REFRESH}" "${VTTCTL_VERSION}"
            log_end_msg $?
            exit
        fi

        IS_RUNNING=$($0 status --json=true | jq -r .running)
        WORLD=$($0 status --json=true | jq -r .world)

        if [[ ${WORLD} == "inactive" ]]; then
            IS_ACTIVE=false
        else
            IS_ACTIVE=true
        fi

        if [[ ${IS_RUNNING} && ! ${IS_RUNNING} == "error" && ${IS_ACTIVE} ]]; then
            RUNNING_VER=$($0 status --json=true | jq -r .version)
            MAJOR_VER="${RUNNING_VER%%.*}"
            VTTCTL_VERSION="${VTTCTL_MAJ}.${VTTCTL_MIN} Build ${VTTCTL_BUILD}"
            log_daemon_msg "Backing up Foundry VTT ${RUNNING_VER}."
            start_time=$(date +%s)
            create_backup \
                "${RUNNING_VER}" \
                "${BACKUP_HOME}" \
                "${UID}" \
                "${GID}" \
                "${WEB_PROTO}" \
                "${FQDN}" \
                "${VTT_HOME}" \
                "${MAJOR_VER}" \
                "${BACKUP_REFRESH}" \
                "${VTTCTL_VERSION}"
            end_time=$(date +%s)
            duration=$((end_time - start_time))

            minutes=$((duration / 60))
            seconds=$((duration % 60))

            if [ ${minutes} -ge 60 ]; then
                  hours=$((minutes / 60))
                  minutes=$((minutes %60))
            fi

            ELAPSED_TIME=""

            if [ ! -z ${hours} ]; then
                  ELAPSED_TIME="${hours}:"
            fi
            minutes_formatted=$(printf "%02d" "${minutes}")
            seconds_formatted=$(printf "%02d" "${seconds}")

            ELAPSED_TIME="${ELAPSED_TIME}${minutes_formatted}:${seconds_formatted}"

            log_daemon_msg "Elapsed Time: ${ELAPSED_TIME}"
            log_daemon_msg " Done."
            log_end_msg $?
            exit
        elif [[ $IS_ACTIVE ]]; then
            $0 reload
            sleep 1
            $0 backup
        else
            log_failure_msg "FoundryVTT is not running or active. Cannot create backup."
            exit 1
        fi
        ;;
  build)
        build_version=""
        if [[ $# -ge 2 && "${2:-}" == "--force" ]]; then
            FORCE_REBUILD=true
        elif [[ $# -ge 2 && "${2:-}" =~ ^[0-9]+\.[0-9]+$ ]]; then
            build_version="${2:-}"
        fi
        build_image "$build_version"
        ;;
  clean)
    if [[ $# -ge 2 && "${2:-}" == "--all" ]]; then
            read -p "Are you sure you want to clean ALL containers and volumes? This will permanently delete user data. (y/N): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                log_failure_msg "Clean cancelled."
                exit 1
            fi
            log_daemon_msg "Removing all containers and volumes."
            docker compose -f "${DOCKER_COMPOSE_FILE}" down -v --remove-orphans
            log_end_msg $?
            exit
        fi
        read -p "Are you sure you want to clean the containers? This will stop and remove them. (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_failure_msg "Clean cancelled."
            exit 1
        fi
        log_daemon_msg "Removing containers."
        docker compose -f "${DOCKER_COMPOSE_FILE}" down --remove-orphans
        log_end_msg $?
        ;;
  cleanup)
    if [[ $# -ge 2 && "${2:-}" == "--all" ]]; then
            log_daemon_msg "Removing all containers, volumes, images, binaries, and extracted folders."
            docker compose -f "${DOCKER_COMPOSE_FILE}" down -v --remove-orphans
            docker system prune -f
            rm -rf "${VTT_HOME}/"*.tgz "${VTT_HOME}/"*.zip "${DOWNLOAD_HOME}" "${VTT_HOME}/FoundryVTT/"*/
            log_end_msg $?
            exit
        fi
        cleanup_versions
        ;;
  default)
        select_default_version
        ;;
  diag)
        output_diagnostics
        ;;
  download)
        if [[ -z "${2:-}" ]]; then
            log_failure_msg "Usage: $0 download <TIMED_URL>"
            exit 1
        fi
        download_foundry "${2:-}"
        ;;
  extract)
        if [[ -z "${2:-}" ]]; then
            log_failure_msg "Usage: $0 extract <version>"
            exit 1
        fi
        extract_foundry "${2:-}"
        ;;
  info)
        show_info
        ;;
  logs)
        if [[ "${2:-}" == "--live" ]]; then
            VARS="${VARS}" TAG="${TAG}" FQDN="${FQDN}" docker compose -p ${PROD_PROJECT} -f "${DOCKER_COMPOSE_FILE}" logs -f
        else
            VARS="${VARS}" TAG="${TAG}" FQDN="${FQDN}" docker compose -p ${PROD_PROJECT} -f "${DOCKER_COMPOSE_FILE}" logs
        fi
        ;;
  monitor)
        monitor_app
        ;;
  reload)
        reload_app
        ;;
  restart)
        restart_services
        ;;
  restore)
        restore_backup
        ;;
  restore-tar)
        if [[ -z "${2:-}" ]]; then
            log_failure_msg "Usage: $0 restore-tar <path_to_tar_file>"
            exit 1
        fi
        restore_from_tar "${2:-}"
        ;;
  restoredev)
        restore_dev_backup
        ;;
  start)
        start_services
        ;;
  status)
        if [[ "${2:-}" == "--json=true" ]]; then
            get_status_json
        else
            get_status
        fi
        ;;
  stop)
        stop_services
        ;;
  upgrade)
        if [[ -z "${2:-}" ]]; then
            log_failure_msg "Usage: $0 upgrade <version>"
            exit 1
        fi
        upgrade_version "${2:-}"
        ;;
  validate)
        validate_setup
        ;;
  web)
      getWebStatus
        ;;
  wizard)
      run_config_wizard
      ;;
  *)
        log_failure_msg "Usage: $0 {start|stop|logs|clean|cleanup|build|status|monitor|restart|reload|force-reload|wizard|upgrade|restore-tar|help}"
        log_failure_msg "Run '$0 help' for detailed usage and options."
        exit 1
        ;;
esac

exit 0
