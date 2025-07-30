#!/bin/bash
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
# Future: source "${VTT_HOME}/src/workflow_backup.sh"
# Future: source "${VTT_HOME}/src/workflow_build.sh"
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

# Use mktemp for temporary files
function getVersion() {
    RESPONSE=$(mktemp)
    trap 'rm -f "$RESPONSE"' RETURN
    status=$(curl -s -w %{http_code} http://localhost:${NGINX_PROD_PORT}/api/status -H "Accept: application/json" -o "$RESPONSE")
    if [ "$status" == 200 ]; then
        JSON=$(cat "$RESPONSE")
        if echo "$JSON" | jq -e . >/dev/null 2>&1; then
            echo "$JSON"
        elif [ ! "$status" == "200" ]; then
            echo "{ \"running\": \"error\", \"http\": $status }"
        fi
    else
        echo "{ \"running\": \"error\", \"http\": $status }"
    fi
}

# Centralized version parsing function
parse_version() {
    # Usage: parse_version <filename>
    # Outputs: version, date
    local filename="$1"
    local version date
    version=$(echo "$filename" | grep -oP '\d+\.\d{3}')
    date=$(echo "$filename" | grep -oP '(?<=-)(2\d{7})(?=\.)')
    echo "$version|$date"
}

# Use portable shell constructs for file listing and avoid parsing ls output
function generateBackupListing() {
    BACKUP_INDEX="${VTT_HOME}/backups/FoundryVTT/index.html"

    case "${MAJOR_VER}" in
        9|10) TEMPLATE_VER=9 ;;
        11|12) TEMPLATE_VER=11 ;;
    esac

    BACKUP_TEMPLATE="${VTT_HOME}/FoundryVTT/templates/backups.${TEMPLATE_VER}.hbs"
    BACKUP_FILE_TABLE=""

    shopt -s nullglob
    for file in "${VTT_HOME}/backups/FoundryVTT/"*.tar*; do
        [ -f "$file" ] || continue
        filename=$(basename "$file")
        IFS="|" read -r version raw_date <<< "$(parse_version "$filename")"
        date=""
        if [ -n "$raw_date" ]; then
            date=$(date -d "$raw_date" +'%Y-%m-%d' 2>/dev/null || echo "$raw_date")
        fi
        size=$(stat -c "%s" "$file" 2>/dev/null || stat -f "%z" "$file")
        size_human=$(du -h "$file" | awk '{print $1}')
        md5=$(md5sum "$file" 2>/dev/null | awk '{print $1}')
        BACKUP_FILE_TABLE="${BACKUP_FILE_TABLE}<tr>
        <td><a href='${filename}'>${filename}</a></td>
        <td>${version}</td>
        <td>${date}</td>
        <td>${size_human}</td>
        <td>${md5}</td>
        </tr>"
    done
    shopt -u nullglob

    VTTCTL_VERSION="${VTTCTL_MAJ}.${VTTCTL_MIN} Build ${VTTCTL_BUILD}"

    awk -v refresh="${BACKUP_REFRESH}" \
        -v file_table="${BACKUP_FILE_TABLE}" \
        -v version="${VTTCTL_VERSION}" '
    {
        gsub("{{BACKUP_REFRESH}}", refresh);
        gsub("{{BACKUP_FILE_TABLE}}", file_table);
        gsub("{{VTTCTL_VERSION}}", version);
        print;
    }
    ' "${BACKUP_TEMPLATE}" > "${BACKUP_INDEX}"
}

function progressCursor() {
            i=1
            sp="/-\|"
            echo -n ' '
            while [ -d /proc/$1 ]; do
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

            echo "{" > "${METADATA_FILE}"

            first_file=true

            for filename in "${BACKUP_HOME}"*.tar "${BACKUP_HOME}"*.tar.gz "${BACKUP_HOME}"*.tar.bz2; do
                if [[ -f "${filename}" ]]; then
                    basefile=$(basename "${filename}")
                    IFS="|" read -r version date <<< "$(parse_version "$basefile")"
                    size=$(stat -c "%s" "${filename}")
                    size_mb=$(awk -v size="${size}" 'BEGIN{printf "%.0f", (size / 1024 / 1024) + 0.5}')
                    if [[ "${first_file}" == false ]]; then
                        echo "," >> "${METADATA_FILE}"
                    else
                        first_file=false
                    fi
                    echo "\"${date}\": { \"version\":\"${version}\", \"filename\":\"${WEB_PROTO}://${FQDN}/backups/${basefile}\", \"size\":\"${size_mb} MB\" }" >> "${METADATA_FILE}"
                fi
            done

            echo "}" >> "${METADATA_FILE}"

            log_daemon_msg "   - ${BACKUP_FILE} backup file created."
            generateBackupListing
            log_daemon_msg "   - Download it from ${WEB_PROTO}://${FQDN}/backups/"
        fi
    fi
}

function getParentDirectoriesToStrip() {
      tar_output=$(tar -tf $1 | head -n 30)

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
    FILE_NAME=$(basename ${REST_FILE})
    
    docker run \
                --rm \
                -v foundryvtt_UserData:/source/ \
                -v $(pwd)/backups/FoundryVTT/:/backup \
                busybox \
                ash -c "tar -xvf /backup/${FILE_NAME} -C /source/ --strip-components=1"

}

function prodBackupRestore() {
      REST_FILE=$1
      STRIP_COMPONENTS=$2
      FILE_NAME=$(basename ${REST_FILE})
      
      docker run \
            --rm \
            -v foundryvtt_UserData:/source/ \
            -v $(pwd)/backups/FoundryVTT/:/backup \
            busybox \
            ash -c "tar -xvf /backup/${FILE_NAME} -C /source/ --strip-components=${STRIP_COMPONENTS}; \
                    chown -R 3000:3000 /source/"
}

function devLatestRestore() {
    REST_FILE=$(ls -t backups/*tar | head -1)
    FILE_NAME=$(basename ${REST_FILE})
    CONT_NAME=$(docker container ls -a | awk '/vtt/ && /app/ {print $1}')
    
    docker run \
                --rm \
                --volumes-from $CONT_NAME \
                -v $VTT_HOME/backups/FoundryVTT/:/backup \
                busybox \
                tar -xvf /backup/${FILE_NAME} -C /

}

function fixOwner() {
    CONT_NAME=$(docker container ls -a | awk '/vtt/ && /app/ {print $1}')
    # hardcoded 3000 UID and GID
    docker run --rm --volumes-from ${CONT_NAME} busybox chown 3000:3000 -R /home/foundry/userdata
}

function fixConfig() {
      # UPnP is not needed in current architecture.
      CONT_NAME=$(docker container ls -a | awk '/vtt/ && /app/ {print $1}')
      docker run --rm --volumes-from ${CONT_NAME} busybox ash -c \
            "sed -i 's/\"upnp\": true/\"upnp\": false/' /home/foundry/userdata/Config/options.json"
}

function getIPaddrByGW() {
      # Only IPv4 supported at this time
      gateway_ip=$(ip route | awk '/default/ {if ($3 ~ /\./) print $3}' | sort -u)
      interface=$(ip route get ${gateway_ip} | awk '/dev/ {print $3}')
      ip_address=$(ip -o -4 addr show dev ${interface} | awk -F '[ /]+' '/inet / {print $4}')
      echo ${ip_address}
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
            current_version=${version}
      else
            index=$((${#versions[@]} - 1))
            versions[${index}]=$(jq ".build += [{\"number\":${build},\"latest\":false}]" <<< "${versions[$index]}")
            last_index=$((${index} - 1))
            versions[${last_index}]=$(jq ".build[-1].latest=true" <<< "${versions[${last_index}]}")
      fi
    done <<< "${output}"

    last_index=$((${#versions[@]} - 1))
    versions[${last_index}]=$(jq ".build[-1].latest=true" <<< "${versions[${last_index}]}")

    json=$(jq -n "{\"versions\":[$(IFS=,; echo "${versions[*]}")]}" 2>/dev/null)

    echo "${json}" > "${file_path}"

}

function isPlatformSupported() {
      matchFoundSupported=false
      matchFoundNotSupported=false

      platform="$1 $2 $3"
      supported=(
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
    echo " 0) Cancel"
}

# Reusable function: prompt for a version selection from a list
prompt_version_selection() {
    local versions="$1"
    local prompt="$2"
    local default="$3"
    local word_count=$(echo "${versions}" | wc -w)
    if [[ $word_count -gt 1 ]]; then
        print_numbered_list "${versions}" "${default}"
        prompt_user_choice "$prompt" $word_count
    else
        echo 1
    fi
}

# Validate if environment is setted up
if [[ ! -f ${ENV_FILE} &&  $1 != "validate" ]]; then
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

function print_help() {
    cat <<EOF
vttctl.sh - FoundryVTT Docker Orchestration Utility

Usage:
  ./vttctl.sh <command> [options]

Commands:
  start           Start FoundryVTT services (production and optionally dev)
  stop            Stop FoundryVTT services
  build           Build Docker images for FoundryVTT (interactive version selection)
  backup          Create a backup of FoundryVTT user data
  restore         Restore FoundryVTT user data from backup (interactive)
  restoredev      Restore latest dev backup
  logs            Show logs (use --live for live logs)
  clean           Remove containers (optionally user data with --all)
  cleanup         Remove images, binaries, and extracted folders (interactive)
  default         Set default FoundryVTT version (interactive)
  info            Show FoundryVTT and system info
  validate        Check dependencies and generate .env if missing
  web             Show Nginx web container status
  monitor         Attach to PM2 monitor in app container
  diag            Output diagnostics.json from running container
  download <url>  Download FoundryVTT zip from timed URL
  extract <ver>   Extract downloaded FoundryVTT zip for version <ver>
  attach          Attach to running app container

Options:
  --all           Used with clean/cleanup to remove all user data/volumes
  --force         Used with build to force rebuild
  --live          Used with logs for live log tailing

Examples:
  ./vttctl.sh validate
  ./vttctl.sh download "TIMED_URL"
  ./vttctl.sh build
  ./vttctl.sh default
  ./vttctl.sh start
  ./vttctl.sh backup
  ./vttctl.sh restore
  ./vttctl.sh clean --all

Environment Variables (from .env):
  DEFAULT_VER     Default FoundryVTT version to run
  DOMAIN          Public domain for FoundryVTT
  HOSTNAME        Hostname prefix for FQDN
  SSL_ENABLED     Set to "true" to enable HTTPS
  NGINX_PROD_PORT Port for Nginx reverse proxy
  PUBLIC_PROD_PORT Public port for FoundryVTT
  DEV_ENABLED     Set to "true" to enable dev environment

Directory Structure:
  FoundryVTT/             # All extracted FoundryVTT versions
  FoundryVTT/Dockerfile.<major>  # Dockerfile per major version
  FoundryVTT/docker-entrypoint.sh # Entrypoint for app container
  backups/FoundryVTT/     # Backup tarballs and metadata.json
  downloads/              # Downloaded FoundryVTT zip files
  docker/                 # Docker Compose files and Nginx config

For more details, see README.md or the project documentation.

EOF
}

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
            log_daemon_msg "Backing up Foundry VTT ${RUNNING_VER}."   
            start_time=$(date +%s)
            prodBackup
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
            # Format minutes and seconds with leading zeros if below 10
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
            echo " - Foundry VTT not running."
            $0 start
            sleep 1
            $0 backup
        fi
        
        log_end_msg $?
        exit 1 
        ;;
  build)
      log_daemon_msg "Building ${DESC}" "${NAME}"
      IS_RUNNING=$($0 status --json=true | jq -r '.running')
      if [[ "${IS_RUNNING}" == "true" ]]; then
            RUNNING_VER=$($0 status --json=true | jq -r .version)
      elif [[ ! ${DEFAULT_VER} == "" ]]; then
            RUNNING_VER=${DEFAULT_VER}
            log_daemon_msg "Default version is set to ${RUNNING_VER}"
      fi

      if [[ (! -z $2 && $2 == "--force") || (${RUNNING_VER} == "") ]];then
            log_daemon_msg "Forced build, listing all available versions."
            mapfile -t VERSIONS_ARR < <(ls -l ${VTT_HOME}/FoundryVTT/ | grep -oE '[0-9]{1,2}\.[0-9]{3,4}' | grep -v '^$')
      else
            mapfile -t VERSIONS_ARR < <(ls -l ${VTT_HOME}/FoundryVTT/ | grep -oE '^d.* [0-9]{1,2}\.[0-9]{3,4}$' | awk '{print $NF}' | grep -v "${RUNNING_VER}")
      fi

      if [[ ${#VERSIONS_ARR[@]} -eq 0 ]]; then
            log_daemon_msg " No FoundryVTT binares available, Use $0 download \"TIMED_URL\""
            log_end_msg $?
      else
            log_daemon_msg " ${VERSIONS_ARR[*]} version(s) available!"
            OPT=""
            BUILD_STARTED=false
            while true; do
                echo "Available versions:"
                print_numbered_array VERSIONS_ARR ""
                read -p " Version to build?: " OPT
                if [[ "$OPT" =~ ^[0-9]+$ ]] && (( OPT >= 0 && OPT <= ${#VERSIONS_ARR[@]} )); then
                    if [[ "$OPT" == "0" ]]; then
                        echo "Canceled. Build was not started."
                        exit 0
                    fi
                    BUILD_VER="${VERSIONS_ARR[$((OPT-1))]}"
                    matching_images=$(docker images | awk '{print $1":"$2}' | grep "${BUILD_VER}")
                    if [ -z "${matching_images}" ]; then
                        echo "Image 'foundryvtt:${BUILD_VER}' not found, building."
                    else
                        if prompt_user_confirm "Are you sure you want to rebuild image 'foundryvtt:${BUILD_VER}'? (y/n): "; then
                            if [[ "${BUILD_VER}" == "${RUNNING_VER}" ]]; then
                                $0 stop
                            fi
                            docker image rm ${matching_images} >/dev/null 2>&1
                            echo "Image(s) matching '${BUILD_VER}' deleted. Re-building."
                        else
                            echo "Image building cancelled."
                            exit 1
                        fi
                    fi

                    exclude=()
                    for EX in "${VERSIONS_ARR[@]}"; do
                        if [[ "$EX" != "${BUILD_VER}" ]]; then
                            exclude+=($EX)
                        fi
                    done

                    rm ${VTT_HOME}/FoundryVTT/.dockerignore >/dev/null 2>&1
                    echo "${exclude[@]}" > ${VTT_HOME}/FoundryVTT/.dockerignore
                    MAJOR_VER="${BUILD_VER%%.*}"
                    TIMEZONE=$(timedatectl | grep "Time zone" | awk {'print $3'})

                    echo "Building version: ${BUILD_VER}"
                    cp ${VTT_HOME}/FoundryVTT/Dockerfile.${MAJOR_VER} ${VTT_HOME}/FoundryVTT/Dockerfile
                    cp ${VTT_HOME}/FoundryVTT/docker-entrypoint.sh ${VTT_HOME}/FoundryVTT/${BUILD_VER}/
                    docker build --progress=plain \
                        --build-arg BUILD_VER=${BUILD_VER} \
                        --build-arg TIMEZONE=${TIMEZONE} \
                        -t foundryvtt:${BUILD_VER} \
                        -f ${VTT_HOME}/FoundryVTT/Dockerfile ${VTT_HOME}/FoundryVTT
                    BUILD_STARTED=true
                    break
                else
                    echo "Invalid option."
                fi
            done
            if [[ "$BUILD_STARTED" == "true" ]]; then
                log_end_msg $?
            fi
      fi

      # Create frontend network if not exists
      if [[ -z $(docker network ls --filter name=frontend --format "{{.Name}}") ]]; then
            docker network create frontend
      fi

      # Create foundryvtt_UserData volume if not exists
      if [[ -z $(docker volume ls --filter name=foundryvtt_prod_UserData --format "{{.Name}}") ]]; then
            docker volume create foundryvtt_prod_UserData
      fi

      # Only call log_end_msg if not canceled (for legacy code path)
      # (This is safe, as above logic will not call log_end_msg on cancel)
      exit 1
      ;;
  clean)  
        # Ask before stopping the service
        if prompt_user_confirm "Do you want to stop the service before cleaning containers? (y/n): "; then
            $0 stop
            echo "Deleting FoundryVTT containers ..."
            VARS="" TAG=${TAG} FQDN=${FQDN} docker-compose -p ${PROD_PROJECT} -f ${VTT_HOME}/docker/docker-compose.yml down
            VARS="" TAG=${TAG} FQDN=${FQDN} docker-compose -p ${DEV_PROJECT} -f ${VTT_HOME}/docker/docker-compose-dev.yml down
        else
            log_warning_msg "Skipping stop. Cleaning cancelled."
            exit 1
        fi
        if [[ (! -z $2 && $2 == "--all") ]];then
            if prompt_user_confirm "Are you sure you want to delete all data? (y/n): "; then
                  echo "Deleting userdata docker volume ..."
                  VOLUME_NAME=$(docker volume ls --filter "name=UserData" --format "{{.Name}}")
                  if [[ -n $VOLUME_NAME ]]; then
                        docker volume rm $VOLUME_NAME >/dev/null 2>&1
                        echo " - ${VOLUME_NAME} volume deleted."
                  else
                        echo " - UserData volume does not exist."
                  fi
            else
                  echo "Operation cancelled."
            fi
        fi
        exit 1
        ;;
  cleanup)
      if [[ (! -z $2 && $2 == "--all") ]];then
            DEFAULT_VER=""
      fi
      DIR_VERSIONS=$(ls -ld ${VTT_HOME}/FoundryVTT/*[0-9]* | awk '/^d/ {print $NF}')
      IMG_VERSIONS=$(docker images -a | grep vtt | awk {'print $1":"$2'})
      BIN_VERSIONS=$(ls ${VTT_HOME}/downloads/ | grep -E '[0-9]{2,3}\.[0-9]{2,3}')

      declare -A word_counts

      # Loop through each variable
      for var_name in DIR_VERSIONS IMG_VERSIONS BIN_VERSIONS; do
            var_value=${!var_name}  # Get the value of the variable using indirect expansion
            word_count=$(echo "${var_value}" | wc -w)
            word_counts[${var_name}]=${word_count}
      done

      # Find the variable with the maximum word count
      max_words=0
      max_variable=""
      for var_name in "${!word_counts[@]}"; do
            if (( word_counts[$var_name] > max_words )); then
            max_words=${word_counts[$var_name]}
            max_variable=$var_name
            fi
      done

      if [[ -n $max_variable ]]; then
            BIGGEST=${!max_variable}
      else
            echo "Nothing to cleanup."
            exit 1
      fi

      pattern="[0-9]{1,3}\.[0-9]{1,3}"

      count=1
      DEFAULT_VER=${DEFAULT_VER:-null}
      if [[ ${DEFAULT_VER} == "null" ]]; then
            echo "Default version is not set"
      else
            echo "Default version ${DEFAULT_VER}"            
      fi
      while [[ ${OPT} != "0" ]]; do
            list=()
            echo "Choose version to clean/delete ('0' to cancel):"
            print_numbered_list "${BIGGEST}" "${DEFAULT_VER}"
            OPT=$(prompt_user_choice "Version to clean/delete?: " $count)

            case ${OPT} in
                  [1-9])
                        ((OPT--))
                        DEL_VER=${list[$OPT]}
                        # Use prompt_user_confirm and check return code
                        if prompt_user_confirm "Are you sure you want to remove all v${DEL_VER} related assets? (y/n): "; then
                              log_daemon_msg "Deleting zip file ..."
                              rm -f ${VTT_HOME}/downloads/*${DEL_VER}* >/dev/null 2>&1
                              log_daemon_msg "Deleting extracted folder ..."
                              rm -rf ${VTT_HOME}/FoundryVTT/${DEL_VER}/ >/dev/null 2>&1
                              log_daemon_msg "Deleting Docker image ..."
                              docker image rm foundryvtt:${DEL_VER} >/dev/null 2>&1
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
      ;;        
  userdata)
      JSON_OUTPUT=$($0 diag)
      if [[ $2 == "--version" && ! -z $2 ]]; then
            FOUNDRY_GENERATION=$(echo "$JSON_OUTPUT" | jq -r '.foundry.generation')
            FOUNDRY_BUILD=$(echo "$JSON_OUTPUT" | jq -r '.foundry.build')
            echo "$FOUNDRY_GENERATION.$FOUNDRY_BUILD"
      fi
      exit 1
      ;;
  default)
        if [ ! -n "${DEFAULT_VER}" ]; then
            VERSIONS=$(docker images -a | grep vtt | awk '{print $2}')
            word_count=$(echo "${VERSIONS}" | wc -w)
            if [ $word_count == 1 ]; then
                  echo ${VERSIONS}
            fi
        fi
        DEFAULT_VER=${DEFAULT_VER:-null}
        if [[ ${DEFAULT_VER} == "null" ]]; then
            VERSION_MSG="Default version is not set"
        else
            VERSION_MSG="Default version ${DEFAULT_VER}"
        fi
        log_daemon_msg "Setting default version of Foundry VTT. (${VERSION_MSG})"
        # Get versions as array
        mapfile -t VERSIONS_ARR < <(docker images -a | grep vtt | awk '{print $2}')
        if [[ ${#VERSIONS_ARR[@]} -eq 0 ]]; then
            log_failure_msg "No available built FoundryVTT images, can't set default."
            exit 1
        fi
        OPT=""
        while [[ ${OPT} != "0" ]]; do
            echo "Available versions:"
            for i in "${!VERSIONS_ARR[@]}"; do
                idx=$((i+1))
                if [[ "${VERSIONS_ARR[$i]}" == "${DEFAULT_VER}" ]]; then
                    echo -e " $idx) ${green}${VERSIONS_ARR[$i]}${reset}"
                else
                    echo " $idx) ${VERSIONS_ARR[$i]}"
                fi
            done
            echo " 0) Cancel"
            read -p "Version to set as default?: " OPT
            if [[ "$OPT" =~ ^[0-9]+$ ]] && (( OPT >= 0 && OPT <= ${#VERSIONS_ARR[@]} )); then
                if [[ "$OPT" == "0" ]]; then
                    echo "Canceled. Default version was not changed."
                    exit 0
                fi
                NEW_DEFAULT_VER="${VERSIONS_ARR[$((OPT-1))]}"
                if [[ "${NEW_DEFAULT_VER}" == "${DEFAULT_VER}" ]]; then
                    echo "Selected version is already the default. No changes made."
                    break
                fi
                USERDATA_VERSION=$($0 userdata --version)
                scale=1000
                NEW_DEFAULT_VER_SCALED=$(awk -v num="$NEW_DEFAULT_VER" -v scale="$scale" 'BEGIN{ print int(num * scale) }')
                USERDATA_VERSION_SCALED=$(awk -v num="$USERDATA_VERSION" -v scale="$scale" 'BEGIN{ print int(num * scale) }')
                if [[ ${NEW_DEFAULT_VER_SCALED} -ge ${USERDATA_VERSION_SCALED} ]]; then
                    sed -i "s/^DEFAULT_VER=.*/DEFAULT_VER=${NEW_DEFAULT_VER}/" "${ENV_FILE}"
                    echo "New default version is ${NEW_DEFAULT_VER}."
                else
                    log_failure_msg "Current userdata version is ${USERDATA_VERSION} can't default to lower app version."
                    log_failure_msg " - Restore v${NEW_DEFAULT_VER} userdata and then change default."
                fi
                break
            else
                echo "Invalid option."
            fi
        done
        exit 0     
        ;;
  diag)
            docker run \
                  --rm \
                  -v foundryvtt_prod_UserData:/source/ \
                  busybox \
                  ash -c "if [ -f /source/Logs/diagnostics.json ]; then cat /source/Logs/diagnostics.json; fi"

      ;;
  download)
        if [[ $2 =~ ${REGEX_URL} ]]; then 
            # Extract version from both Linux and Node zip URLs
            VERSION=$(echo "$2" | grep -oP "(?<=releases/)\d+\.\d+")
            MAJOR_VER="${VERSION%%.*}"
            FOUNDRY_VERSIONS="${VTT_HOME}/FoundryVTT/foundryvtt.json"
            MAJOR_MINOR=$(jq -r '.foundryvtt | map(.version | capture("(?<major>\\d+)")) | sort_by(.major | tonumber) | first | .major' ${FOUNDRY_VERSIONS})
            MAJOR_MAJOR=$(jq -r '.foundryvtt | map(.version | capture("(?<major>\\d+)")) | sort_by(.major | tonumber) | last | .major' ${FOUNDRY_VERSIONS})

            if [[ (${MAJOR_VER} -ge ${MAJOR_MINOR}) && (${MAJOR_VER} -le ${MAJOR_MAJOR}) ]]; then
                  DEST="${VTT_HOME}/FoundryVTT"
                  count=$(find ${DEST}/ -type d -name "[0-9][0-9].*[0-9][0-9][0-9]" | wc -l)
                  if [ ${count} -gt 9 ]; then
                        log_failure_msg "To many downloaded FoundryVTT binaries, please do $0 clean and remove at least 1 old version."
                        break
                  fi

                  FILE=$(basename "$2" | awk -F\? {'print $1'})
                  # Accept both Linux and Node zip files
                  if echo "$FILE" | grep -Eq "^FoundryVTT-(Linux|Node)-${VERSION}\.zip$"; then
                        log_daemon_msg " Downloading ZIP file ${FILE} ..."
                        curl -# -o "${VTT_HOME}/downloads/${FILE}" "$2"
                        log_daemon_msg " Download completed."

                        $0 extract ${VERSION}
                  else
                        # The file is not a recognized ZIP file
                        log_failure_msg -e "\nThe file is not a recognized FoundryVTT Linux or NodeJS ZIP file. Please use a valid TIMED URL. Aborting download."
                  fi
            else
                  log_failure_msg "Version ${MAJOR_VER} not supported by vttctl."
            fi
        else
            echo "Usage: $0 download \"Foundry VTT Linux/NodeJS download timed URL\"."
        fi
        ;;
  extract)
      VERSION=$2
      DEST="FoundryVTT"
      TARGET="${VTT_HOME}/${DEST}/${VERSION}"
      MAJOR_VER="${VERSION%%.*}"
      ZIP_PATH=""
      FILE=""
      if [ "$MAJOR_VER" -ge 13 ]; then
          # Try Node and Linux zips for v13+
          for variant in Node Linux; do
              CANDIDATE="${VTT_HOME}/downloads/FoundryVTT-${variant}-${VERSION}.zip"
              if [ -e "$CANDIDATE" ]; then
                  ZIP_PATH="$CANDIDATE"
                  FILE="FoundryVTT-${variant}-${VERSION}.zip"
                  break
              fi
          done
      else
          # v12 and below: FoundryVTT-<version>.zip
          CANDIDATE="${VTT_HOME}/downloads/FoundryVTT-${VERSION}.zip"
          if [ -e "$CANDIDATE" ]; then
              ZIP_PATH="$CANDIDATE"
              FILE="FoundryVTT-${VERSION}.zip"
          fi
      fi
      rm -rf ${TARGET} >/dev/null 2>&1;
      log_daemon_msg "Extracting ${FILE:-FoundryVTT-<version>.zip}"
      log_daemon_msg " Destination ${TARGET}/"
      if [ -n "$ZIP_PATH" ]; then
            unzip -qq -o "$ZIP_PATH" -d ${TARGET}/
            # Determine where package.json is located
            PKG_JSON=""
            if [ "$MAJOR_VER" -ge 13 ]; then
                # Node: root, Linux: resources/app/
                if [ -f "${TARGET}/package.json" ]; then
                    PKG_JSON="${TARGET}/package.json"
                else
                    PKG_JSON="${TARGET}/resources/app/package.json"
                fi
            else
                PKG_JSON="${TARGET}/resources/app/package.json"
            fi
            if [ -f "$PKG_JSON" ]; then
                VER=$(cat "$PKG_JSON" | jq -r '"\(.release.generation).\(.release.build)"')
            else
                VER="unknown"
            fi
            cp ${VTT_HOME}/${DEST}/*.sh ${TARGET}
            log_daemon_msg " ${FILE} contents extracted and ready to build."
      else
            log_failure_msg "No FoundryVTT zip for version ${VERSION} exists in downloads, please download the ZIP from foundryvtt.com."
      fi
      ;;
  fix)
        log_daemon_msg "Fixing permissions for Foundry VTT."
        fixOwner
        fixConfig
        $0 reload
        log_end_msg $?
        exit 1   
        ;;
  info)
         log_begin_msg "Getting FoundryVTT info"
         IS_RUNNING=$($0 status --json=true | jq -r '.running')
         IS_INACTIVE=$($0 status --json=true | jq -r '.world')
         if [[ $IS_RUNNING == "true" ]]; then
            VERSION=$($0 status --json=true | jq -r '.version')
            SUPPORT=$(isPlatformSupported ${LINUX_DISTRO} ${DISTRO_VERSION} ${CPU_ARCH})
            if [[ ! ${IS_INACTIVE} == "inactive" ]]; then
                  WORLD=$($0 status --json=true | jq -r .world)
                  SYSTEM=$($0 status --json=true | jq -r .system)
                  log_daemon_msg "Foundry VTT v${VERSION} is running."
                  log_daemon_msg " System: ${SYSTEM}"
                  log_daemon_msg " World: ${WORLD//-/ }"

            else
                  log_warning_msg "Foundry VTT v${VERSION} is running BUT world not active."
            fi
            log_daemon_msg " ----------------- System Info -----------------"
            log_daemon_msg " Platform: ${LINUX_DISTRO} ${DISTRO_VERSION} ${CPU_ARCH} ${SUPPORT}."
            log_daemon_msg " Network $ETHERNET config:"
            log_daemon_msg "  Public IP: ${PUBLIC_IP}"
            log_daemon_msg "  Internal IP: ${LOCAL_IP}"
            log_daemon_msg "  Foundry VTT port: ${NGINX_PROD_PORT}/TCP"
            log_daemon_msg "  Public URL: ${WEB_PROTO}://${HOSTNAME}.${DOMAIN}/"
            true
            log_end_msg $?
            exit
         elif [[ ${IS_RUNNING} == "error" ]]; then
            log_failure_msg "Foundry VTT is not running."
            false
            log_end_msg $?
            exit
         fi
      ;;
  logs)
        if [[ -n $2 && $2 == "--live" ]]; then
            liveLogs
        else
            getLogs
        fi
        exit 1
        ;;
  monitor)
            CONT_NAME=$(docker container ls -a | grep vtt | grep app | grep prod | awk '{print $1}')
            docker exec -it ${CONT_NAME} pm2 monit
            exit 1
        ;;
  validate)
      log_begin_msg "Validating requirements ..."
      if [ ! -d "${VTT_HOME}/backups" ]; then
       mkdir -p ${VTT_HOME}/backups/FoundryVTT
       if [ ! -f "${VTT_HOME}/backups/FoundryVTT/index.html" ]; then
            echo "No available backups yet." > ${VTT_HOME}/backups/FoundryVTT/index.html
       fi
       mkdir -p ${VTT_HOME}/backups/volumes
       mkdir -p ${VTT_HOME}/downloads/
       echo "[]" > ${VTT_HOME}/backups/FoundryVTT/metadata.json
      fi

      commands=(basename
                cat
                curl
                cp
                date
                docker
                docker-compose
                free
                getent
                grep
                id
                ip
                jq
                rm
                python3
                sed
                sort
                timedatectl
                uname
                unzip
                wc
                xargs)


      for cmd in "${commands[@]}"; do
            if [[ -z $(type -P "$cmd") ]]; then
                  if [[ -z $(command -v "$cmd") ]]; then
                        if ! alias | grep -wq $cmd ; then
                              log_daemon_msg " - Command not found: ${cmd}"
                              if [ "${cmd}" == "docker-compose" ]; then
                                    log_daemon_msg " - If 'docker compose' is available, create an alias for docker-compose using docker compose."
                                    echo "echo 'alias docker-compose=\"docker compose\"' >> ~/.bash_aliases"
                              fi                       
                              false
                              log_end_msg $?
                              exit
                        fi
                  fi
            fi
      done

      if [ ! -f ${ENV_FILE} ]; then
            log_daemon_msg " - File .env does not exist, Generating ..."
            sed '/^#/d; /^$/d' "${VTT_HOME}/dotenv.example" > "${ENV_FILE}"
      else
            log_daemon_msg " - File .env exists."
      fi
      log_end_msg $?
      
        ;;
  start)
        if [[ -n ${DEFAULT_VER} ]]; then
            log_begin_msg "Starting ${DESC}" "${NAME} ${DEFAULT_VER}"
            VARS=$(echo "FQDN=${FQDN} PROXY_PORT=${PUBLIC_PROD_PORT} UPNP=false" | base64)

            TAG=${TAG} FQDN=${FQDN} VARS=${VARS} docker-compose -p ${PROD_PROJECT} -f ${VTT_HOME}/docker/docker-compose.yml up -d
            if [ "${DEV_ENABLED}" == "true" ]; then
                  docker-compose -p ${DEV_PROJECT} -f ${VTT_HOME}/docker/docker-compose-dev.yml up -d -e VARS=${VARS} -e TAG=${TAG}
            fi
            fixOwner
            sleep 2
            $0 info
            log_end_msg $?
         else
             log_warning_msg "No default FoundryVTT version found."
             $0 default
             $0 start
         fi
        ;;
  stop)
        IS_RUNNING=$($0 status --json=true | jq -r '.running')
        if [[ "${IS_RUNNING}" == "true" ]]; then
            RUNNING_VERSION=$($0 status --json=true | jq -r .version)
            log_daemon_msg "Stopping ${DESC}" "${NAME} ${RUNNING_VERSION}."   
            stop
        elif [[ "${IS_RUNNING}" == "false" ]]; then
            log_daemon_msg "Stopping ${DESC}" "${NAME} ${DEFAULT_VERSION}."
            stop
        else
            log_daemon_msg " Foundry VTT not running."
        fi  
        log_end_msg $?
        exit
    ;;


  reload|force-reload)
        log_daemon_msg "Reloading ${DESC} configuration files for" "${NAME}"
        appReload
        log_end_msg $?
        ;;

  restart)
        $0 stop
        sleep 1
        $0 start
        exit 1
        ;;
  restore)
            # Enable extended globbing
            shopt -s extglob

            # Populate the file_array with .tar, .tar.gz, and .tar.bz2 files
            file_array=()

            # Iterate through matching files and append them to the array
            for file in "$BACKUP_HOME"*.tar "$BACKUP_HOME"*.tar.gz "$BACKUP_HOME"*.tar.bz2; do
                  if [ -f "$file" ]; then
                        file_array+=("$file")
                  fi
            done
            if [[ -z "$STY" && -z "$TMUX" ]]; then
                  # Use prompt_user_confirm and check return code
                  if ! prompt_user_confirm "You are not running in screen or tmux. Do you want to continue? (y/n): "; then
                        echo "Please use screen or tmux to run restore."
                        exit 1
                  fi
            fi
        log_begin_msg "Restoring up Foundry VTT."
        log_daemon_msg " Existing backups in ${BACKUP_HOME}"
        echo " "
        echo " Choose version/date to restore ('0' to cancel):"
        # Print a list of existing backups
        OPT=""
        while [[ $OPT != "0" ]]; do
            for ((i=0; i<${#file_array[@]}; i++)); do
                  filename=$(basename ${file_array[i]})

                  version="${filename#foundry_userdata_}"   # Remove the prefix 'foundry_userdata_'
                  version="${version%%-*}"  

                  filedate="${filename#*-}"                  # Remove the prefix until the first '-'
                  filedate="${filedate%%.*}"
                  human_readable_date=$(date -d "$filedate" +"%b %d, %Y")
                  echo " $((i+1))) $version - $human_readable_date"
            done
            # read -p " Version and date to restore?: " OPT
            OPT=$(prompt_user_choice " Version and date to restore?: " ${#file_array[@]})

            # Choosing restore options, up to 9 available versions.
            case ${OPT} in
                  [1-9])
                        count=${#file_array[@]}
                        # Validate if OPT is within a valid range
                        if [ $OPT -ge 0 ] && [ $OPT -le $count ]; then
                              # Decrement the value of OPT by 1
                              i=$((OPT - 1))

                              # Get the value at the specified index (i)
                              VER_RESTORE="${file_array[i]}"

                              # Print the value
                              BACKUP_FILE=$(basename "$VER_RESTORE")
                              log_daemon_msg "Validating ${BACKUP_FILE} ..."
                              directories=$(tar -tf ${VER_RESTORE} | grep -E '(/Logs/|/Config/|/Data/)' | awk -F/ '{print $2}' | sort -u)

                              if echo "$directories" | grep -q "Config" && echo "$directories" | grep -q "Data" && echo "$directories" | grep -q "Logs"; then
                                    log_daemon_msg " - Found valid FoundryVTT backup directory structure!"
                                    log_daemon_msg "Validating FoundryVTT backup version ..."
                                    FILE_DIAG=$(tar -tf ${VER_RESTORE} | grep diagnostics.json)
                                    BACK_DIAG=$(tar -xOf ${VER_RESTORE} ${FILE_DIAG} | grep -a .)
                                    BACKUP_GENERATION=$(echo ${BACK_DIAG}| jq -r '.foundry.generation')
                                    BACKUP_BUILD=$(echo ${BACK_DIAG}| jq -r '.foundry.build')
                                    BACKUP_DIAG_VER="${BACKUP_GENERATION}.${BACKUP_BUILD}"
                                    log_daemon_msg " - v${BACKUP_DIAG_VER} in ${FILE_DIAG}"
                                    STRIP=$(getParentDirectoriesToStrip ${VER_RESTORE})
                                    prodBackupRestore ${VER_RESTORE} ${STRIP}
                                    echo " "
                                    echo "Restore completed."
                                    RESTORED=true
                                    break;
                              else
                                    log_failure_msg "Missing one or more: Config, Data, or Logs"
                                    false
                                    break;
                              fi
                        else
                              log_failure_msg "${OPT} is an invalid option."
                        fi
                        ;;
                  0)
                        log_failure_msg "Canceled."
                        false
                        break
                        ;;
                  *)
                        log_failure_msg "Invalid option."
                        ;;                  
            esac
            if [[ ${RESTORED} == "true" ]]; then
                  break
            fi
        done

        log_end_msg $?
        exit 1   
        ;;
  restoredev)
        log_daemon_msg "Restoring up Foundry VTT."
        devLatestRestore
        $0 reload
        log_end_msg $?      
        ;;


  status)
      if [[ -n $2 && $2 == "--json=true" ]]; then
            json=$(getVersion)
            if [[ ! -z "${json}" ]]; then
                  IS_RUNNING=$(echo ${json} | jq -r .running)
                  IS_ACTIVE=$(echo ${json} | jq -r .active)
                  VERSION=$(echo ${json} | jq -r '.version')

                  if [[ ${IS_RUNNING} == "null" && ${IS_ACTIVE} == "true" ]]; then
                        RUNNING="true"
                        VERSION=$(echo ${json} | jq -r '.version')
                        VTTWORLD=$(echo ${json} | jq -r '.world')
                        VTTSYSTEM=$(echo ${json} | jq -r '.system')
                        SYSTEM_VERSION=$(echo ${json} | jq -r '.systemVersion')
                        CURRENT_STATUS="true"
                  elif [[ ${IS_ACTIVE} == "false" ]]; then
                        CURRENT_STATUS="inactive"
                  elif [[ ! ${IS_RUNNING} == "false" ]]; then
                        CURRENT_STATUS="error"
                  fi

                  case ${CURRENT_STATUS} in
                        true)
                              echo "{ \"running\": ${RUNNING}, \"version\": \"${VERSION}\", \"world\": \"${VTTWORLD}\", \"system\": \"${VTTSYSTEM}\"}"
                              ;;
                        inactive)
                              echo "{ \"running\": true, \"world\": \"inactive\", \"version\": \"${VERSION}\" }"
                              ;;
                        false)
                              echo "{ \"running\": false }"
                              ;;
                        *)
                              http_code=$(echo ${json} | jq -r '.http')
                              echo "{ \"running\": \"error\", \"http\": ${http_code} }"
                              ;;
                  esac
            else
                  log_daemon_msg "Foundry VTT v${DEFAULT_VER} enabled"
                  $0 info
            fi
      else
            log_daemon_msg "Foundry VTT v${DEFAULT_VER} enabled"
            $0 info
      fi
      
      ;;

  web)
      getWebStatus
        ;;
  *)
        log_failure_msg "Usage: $0 {start|stop|logs|clean|cleanup|build|status|monitor|restart|reload|force-reload|help}"
        log_failure_msg "Run '$0 help' for detailed usage and options."
        exit 1
        ;;
esac

exit 0

exit 0

