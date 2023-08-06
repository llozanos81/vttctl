#!/bin/bash
# Version: 0.03

VTT_HOME=$(pwd)
ENV_FILE="${VTT_HOME}/.env"

function stop() {
      CONT_NAME=$(docker container ls -a | awk '/vtt/ && /app/ {print $1}')
      docker exec -it ${CONT_NAME} pm2 stop all
      VARS="" docker-compose -p ${PROD_PROJECT} -f ${VTT_HOME}/docker/docker-compose.yml stop
      VARS="" docker-compose -p ${DEV_PROJECT} -f ${VTT_HOME}/docker/docker-compose-dev.yml stop
}

function getLogs() {
    VARS="" docker-compose -p ${PROD_PROJECT} -f ${VTT_HOME}/docker/docker-compose.yml logs
}

function liveLogs() {
    VARS="" docker-compose -p ${PROD_PROJECT} -f ${VTT_HOME}/docker/docker-compose.yml logs -f
}

function getVersion() {
    RESPONSE=/tmp/.response.txt
    rm -rf ${RESPONSE}
    status=$(curl -s -w %{http_code} http://localhost:${NGINX_PROD_PORT}/api/status -H "Accept: application/json" -o ${RESPONSE})
    if [ ${status} == 200 ]; then
        JSON=$(cat ${RESPONSE})
        if echo ${JSON} | jq -e . >/dev/null 2>&1; then
            echo ${JSON}
        elif [ ! ${status} == "200" ]; then
            echo "{ \"running\": \"error\", \"http\": ${status} }"
        fi
    else
        echo "{ \"running\": \"error\", \"http\": ${status} }"
    fi
}

function appReload() {
    CONT_NAME=$(docker container ls -a | awk '/vtt/ && /app/ {print $1}')
    docker exec -d ${CONT_NAME} pm2 restart foundry
    sleep 2
    log_daemon_msg "FoundryVTT nodejs application reloaded."
}

function generateBackupListing() {
      BACKUP_INDEX="${VTT_HOME}/backups/FoundryVTT/index.html"

      case "${MAJOR_VER}" in
            9)
                  TEMPLATE_VER=9
            ;;
            10)
                  # 9 and 10 shares template
                  TEMPLATE_VER=9
            ;;
            11)
                  TEMPLATE_VER=11
            ;;
      esac

      BACKUP_TEMPLATE="${VTT_HOME}/FoundryVTT/templates/backups.${TEMPLATE_VER}.hbs"

      BACKUP_FILE_TABLE=""

      # Extract version, date, and size information for tar and tar.gz files
      files=$(ls -hal "${VTT_HOME}/backups/FoundryVTT/" | awk '/^.*\.tar(\.gz|\.bz2)?$/ {print}')
      while IFS= read -r line; do
            file=$(echo "${line}" | awk '{print $9}')
            version=$(echo "${file}" | awk -F"[_.-]" '{match($0, /[0-9]+\.[0-9]{3}/, v); print v[0]}')
            raw_date=$(echo "${file}" | awk -F"[_.-]" '{match($0, /[0-9]{4}[0-9]{2}[0-9]{2}/, d); print d[0]}')
            date=$(date -d "${raw_date}" +'%Y-%m-%d')
            size=$(echo "${line}" | awk '{print $5}')
            md5=$(md5sum ${VTT_HOME}/backups/FoundryVTT/${file} | awk {'print $1'} )
            BACKUP_FILE_TABLE="${BACKUP_FILE_TABLE}<tr>
            <td><a href='${file}'>${file}</a></td>
            <td>${version}</td>
            <td>${date}</td>
            <td>${size}</td>
            <td>${md5}</td>
            </tr>"
      done <<< "${files}"

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
        PROD_VER=$(echo ${json} | jq -r .version)
        if [[ -n ${PROD_VER} ]]; then
            DATESTAMP=$(date +"%Y%m%d")
            BACKUP_FILE=foundry_userdata_${PROD_VER}-${DATESTAMP}.tar
            docker run \
                --rm \
                -v foundryvtt_prod_UserData:/source/ \
                -v ${BACKUP_HOME}:/backup \
                busybox \
                ash -c " \
                tar -cvf /backup/${BACKUP_FILE} \
                    -C / /source "
 
            #BACKPID=$!
            #progressCursor "$BACKUPID"

            docker run \
                --rm \
                -v ${BACKUP_HOME}:/backup \
                busybox \
                ash -c "chown ${UID}:${GID} /backup/${BACKUP_FILE}"

            DATE_FILE=$(stat --format="%y" "${BACKUP_HOME}/${BACKUP_FILE}" | awk {'print $1'})

            if [[ -f "${METADATA_FILE}" ]]; then
                  rm "${METADATA_FILE}"
            fi

            shopt -s nullglob

            echo "{" > "${METADATA_FILE}"

            first_file=true

            for filename in "${BACKUP_HOME}"*.tar "${BACKUP_HOME}"*.tar.gz "${BACKUP_HOME}"*.tar.bz2; do
                  if [[ -f "${filename}" ]]; then
                        version=$(basename "${filename}" | awk -F '[._-]' '{print $(NF-3)"."$(NF-2)}')
                        date=$(basename "${filename}" | grep -oE '[0-9]{8}' | head -n1)
                        size=$(stat -c "%s" "${filename}")
                        size_mb=$(awk -v size="${size}" 'BEGIN{printf "%.0f", (size / 1024 / 1024) + 0.5}')  # Rounding up the size and removing decimal places

                        if [[ "${first_file}" == false ]]; then
                              echo "," >> "${METADATA_FILE}"
                        else
                              first_file=false
                        fi

                        echo "\"${date}\": { \"version\":\"${version}\", \"filename\":\"${WEB_PROTO}://${FQDN}/backups/$(basename "${filename}")\", \"size\":\"${size_mb} MB\" }" >> "${METADATA_FILE}"
                  fi
            done

            echo "}" >> "${METADATA_FILE}"

            log_daemon_msg "   - ${BACKUP_FILE} backup file created."
            generateBackupListing
            log_daemon_msg "   - Download it from ${WEB_PROTO}://${FQDN}/backups/"
        fi
    fi
}

function prodLatestRestore() {
    REST_FILE=$(ls -t backups/FoundryVTT/*tar | head -1)
    FILE_NAME=$(basename ${REST_FILE})
    
    docker run \
                --rm \
                -v foundryvtt_prod_UserData:/source/ \
                -v $(pwd)/backups/FoundryVTT/:/backup \
                busybox \
                tar -xvf /backup/${FILE_NAME} -C /source/ --strip-components=1

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
            "CentOS 7.9.2009 x86_64"
            "Rocky 8.8 x86_64"
      )

      notsupported=(
            "CentOS 5 x86_64"
            "Debian 12 x86_64"
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


# Source function library.
if ! [ -x "/lib/lsb/init-functions" ]; then
        . /lib/lsb/init-functions
elif ! [ -x "/etc/init.d/functions" ]; then
        . /etc/init.d/functions

      # Helper logging functions not included in /etc/init.d/functions
      function log_failure_msg() {
            echo -e " * "$1 $2 $3           
      }

      function log_daemon_msg() {
            echo -e " * "$1 $2 $3      
      }

      function log_begin_msg() {
            echo -e " * "$1 $2 $3
      }

      function log_warning_msg() {
            echo -e " * "$1 $2 $3
      }

      function log_end_msg() {
            echo -e " * "$1 $2 $3
      }

else
        echo "E: /lib/lsb/init-functions or /etc/init.d/functions not found, lsb-base needed"
        exit 1
fi

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
PUBLIC_IP=$(curl -s ifconfig.me/ip)

LINUX_DISTRO="N/A lsb_release missing"

# Distro detection
if [ -f /etc/debian_version ]; then # Ubuntu/Debian validation
      version=$(< /etc/debian_version)
      if type "lsb_release" >/dev/null 2>&1; then
            if [[ $version == *"sid"* ]]; then
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

case "$1" in
  attach)
        APP_CONTAINER=$(docker container ls -a | awk '/vtt/ && /app/ {print $1}')
        RUNNING_VER=$(docker container ls -a | awk '/vtt/ && /app/ { split($2, a, ":"); print a[2] }')
        docker exec -it ${APP_CONTAINER} ash -c "echo Attaching to FoundryVTT ${RUNNING_VER} app container ...; export PS1=\"FoundryVTT:$ \"; cd; ls -l; /bin/ash"
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
                  ELAPSED_TIME=${hours}
            fi
            # Format minutes and seconds with leading zeros if below 10
            minutes_formatted=$(printf "%02d" "${minutes}")
            seconds_formatted=$(printf "%02d" "${seconds}")

            ELAPSED_TIME="${ELAPSED_TIME}:${minutes_formatted}:${seconds_formatted}"

            log_daemon_msg "Elapsed Time: ${ELAPSED_TIME}."
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
      fi

      if [[ (! -z $2 && $2 == "--force") || (${RUNNING_VER} == "") ]];then
            # List all available extracted binaries folders
            VERSIONS=$(ls -l ${VTT_HOME}/FoundryVTT/ | grep -oE '[0-9]{1,2}\.[0-9]{3,4}' | grep -v '^$')
      else
            # List all available extracted binaries folders but running or default version
            VERSIONS=$(ls -l ${VTT_HOME}/FoundryVTT/ | grep "^d" | awk '$NF ~ /^[0-9]{1,2}\.[0-9]{3,4}$/ {print $NF}' | grep -v "${RUNNING_VER}")
      fi

      #  Validating if is there any available FoundryVTT binaries.
      if [[ -z ${VERSIONS} ]]; then
            log_daemon_msg " No FoundryVTT binares available, Use $0 download \"TIMED_URL\""
            log_end_msg $?
      else
            log_daemon_msg " "${VERSIONS}" version(s) available!"
            OPT=""
            # Print list, choose version to build
            while [[ $OPT != "0" ]]; do
                  word_count=$(echo "${VERSIONS}" | wc -w)

                  if [[ ${word_count} -gt 1 ]]; then
                        echo " Choose version to build ('0' to cancel):"
                        count=1

                        for VER in ${VERSIONS}; do
                              echo " $count) $VER"
                              ((count++))
                        done
                        read -p " Version to build?: " OPT
                  else 
                        # If only one is available auto-build kicks in.
                        OPT=1
                        echo "Building FoundryVTT ${VERSIONS} ..."
                  fi

                  # Choosing Build options, up to 9 available versions.
                  case ${OPT} in
                        [1-9])
                              BUILD_VER=$(echo "${VERSIONS}" | sed -n "${OPT}p")
                              matching_images=$(docker images | awk '{print $1":"$2}' | grep "${BUILD_VER}")
                              if [ -z "${matching_images}" ]; then
                                    echo "Image 'foundryvtt:${BUILD_VER}' not found, building."
                              else
                                    read -p "Are you sure you want to rebuild image 'foundryvtt:${BUILD_VER}'? (y/n): " confirmation

                                    # Process user's confirmation
                                    if [[ "${confirmation}" == "y" || "${confirmation}" == "Y" ]]; then                              
                                          $0 stop
                                          # Delete matching images
                                          docker image rm ${matching_images} >/dev/null 2>&1
                                          echo "Image(s) matching '${BUILD_VER}' deleted. Re-building."
                                    else
                                          echo "Image building cancelled."
                                          exit
                                    fi
                              fi


                              for EX in ${VERSIONS}; do
                                    if [[ "$EX" != "${BUILD_VER}" ]]; then
                                          exclude+=($EX)
                                    fi
                              done

                              # Preparing docker build environment
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
                              break
                              ;;
                        0)
                              echo "Canceled."
                              break
                              ;;
                        *)
                              echo "Invalid option."
                              ;;
                  esac
            done
      fi
      
      log_end_msg $?
      exit 1
      ;;
  clean)  
        $0 stop
        echo "Deleting FoundryVTT containers ..."
        VARS="" TAG=${TAG} docker-compose -p ${PROD_PROJECT} -f ${VTT_HOME}/docker/docker-compose.yml down
        VARS="" TAG=${TAG} docker-compose -p ${DEV_PROJECT} -f ${VTT_HOME}/docker/docker-compose-dev.yml down
        exit 1
        ;;
  cleanup)
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

      BIGGEST=${!max_variable}

      pattern="[0-9]{1,3}\.[0-9]{1,3}"

      count=1
      echo "Default version ${DEFAULT_VER}"
      while [[ ${OPT} != "0" ]]; do
            list=()
            echo "Choose version to clean/delete ('0' to cancel):"
            for i in ${BIGGEST}; do
                  [[ $i =~ ${pattern} ]] && version="${BASH_REMATCH[0]}"
                  if [ ! ${version} == ${DEFAULT_VER} ]; then
                        list+=($version)
                        echo "${count}) ${version}"
                        ((count++))
                  fi
            done
            read -p "Version to clean/delete?: " OPT

            case ${OPT} in
                  [1-9])
                        ((OPT--))
                        DEL_VER=${list[$OPT]}
                        read -p "Are you sure you want to remove all v${DEL_VER} related assets? (y/n): " confirmation
                        if [ "${confirmation}" == "y" ] || [ "${confirmation}" == "Y" ]; then
                              echo "Deleting zip file ..."
                              rm -f ${VTT_HOME}/downloads/*${DEL_VER}* >/dev/null 2>&1
                              echo "Deleting extracted folder ..."
                              rm -rf ${VTT_HOME}/FoundryVTT/${DEL_VER}/ >/dev/null 2>&1
                              echo "Deleting Docker image ..."
                              docker image rm foundryvtt:${DEL_VER} >/dev/null 2>&1
                              echo "Cleaning completed."
                        fi
                        break
                        ;;
                  0)
                        echo "Cleaning cancelled."
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
        if [ ! -n ${DEFAULT_VER} ]; then
            VERSIONS=$(docker images -a | grep vtt | awk {'print $2'})
            word_count=$(echo "${VERSIONS}" | wc -w)
            if [ $word_count == 1 ]; then
                  echo ${VERSIONS}
            fi
        fi
        log_daemon_msg "Setting default version of Foundry VTT. (Current ${DEFAULT_VER})"
        VERSIONS=$(docker images -a | grep vtt | awk {'print $2'})
        OPT=""
        while [[ ${OPT} != "0" ]]; do
              word_count=$(echo "${VERSIONS}" | wc -w)
              if [[ $word_count -gt 1 ]]; then
                  echo "Choose version to build ('0' to cancel):"
                  count=1

                  for VER in ${VERSIONS}; do
                        if [[ $VER == ${DEFAULT_VER} ]]; then
                              echo -e "${count}) ${green}${VER}${reset}"
                        else
                              echo "${count}) ${VER}"
                        fi
                        ((count++))
                  done
                  read -p "Version to set as default?: " OPT
              else 
                  OPT=1
              fi

            case ${OPT} in
                  [1-9])
                        NEW_DEFAULT_VER=$(echo "${VERSIONS}" | sed -n "${OPT}p")
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
                        ;;
                  0)
                        echo "Canceled."
                        false
                        log_end_msg $?
                        break
                        ;;
                  *)
                        echo "Invalid option."
                        ;;
            esac
        done
        exit 1     
        ;;
  diag)
            docker run \
                  --rm \
                  -v foundryvtt_prod_UserData:/source/ \
                  busybox \
                  ash -c "cat /source/Logs/diagnostics.json"
      ;;
  download)
        if [[ $2 =~ ${REGEX_URL} ]]; then 
            VERSION=$(echo "$2" | grep -oP "(?<=releases\/)\d+\.\d+")
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
                  # Validate the URL if contains ZIP file
                  echo $2 | grep -E "/[^/]*\.zip\?AWSAccessKeyId" >/dev/null 2>&1;

                  # Check the exit code of the previous command
                  if [ $? -eq 0 ]; then
                        # The file is a ZIP file, proceed with downloading
                        log_daemon_msg " Downloading ZIP file ${FILE} ..."
                        curl -# -o "${VTT_HOME}/downloads/${FILE}" "$2"
                        log_daemon_msg " Download completed."

                        $0 extract ${VERSION}
                  else
                        # The file is not a ZIP file or has other extensions
                        log_failure_msg -e "\nThe file is not a ZIP file or has other extensions. Please use TIMED URL for Linux/NodeJS. Aborting download."
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
      FILE="FoundryVTT-${VERSION}.zip"
      rm -rf ${TARGET} >/dev/null 2>&1;
      log_daemon_msg "Extracting ${FILE}"
      log_daemon_msg " Destination ${TARGET}/"
      ZIP_PATH=${VTT_HOME}/downloads/${FILE}
      if [ -e $ZIP_PATH ]; then
            unzip -qq -o $ZIP_PATH -d ${TARGET}/
            VER=$(cat ${TARGET}/resources/app/package.json | jq -r '"\(.release.generation).\(.release.build)"')
            cp ${VTT_HOME}/${DEST}/*.sh ${TARGET}
            log_daemon_msg " ${FILE} contents extracted and ready to build."
      else
            log_failure_msg "${FILE} does not exists in downloads, please download the ZIP form foundryvtt.com."
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
       if ! type "$cmd" >/dev/null 2>&1; then
            if ! command -v "${cmd}" >/dev/null 2>&1; then
                  log_daemon_msg " - Command not found: ${cmd}"
                  false
                  log_end_msg $?  
                  exit
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
            VARS=$(echo "FQDN=${FQDN}|PROXY_PORT=${PUBLIC_PROD_PORT}" | base64)

            TAG=${TAG} VARS=${VARS} docker-compose -p ${PROD_PROJECT} -f ${VTT_HOME}/docker/docker-compose.yml up -d
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
        
        file_array=("$BACKUP_HOME"/*.tar)
        log_daemon_msg "Restoring up Foundry VTT."
        #prodLatestRestore
        #$0 reload
        for ((i=0; i<${#file_array[@]}; i++)); do
            filename=$(basename ${file_array[i]})

            version="${filename#foundry_userdata_}"   # Remove the prefix 'foundry_userdata_'
            version="${version%%-*}"  

            filedate="${filename#*-}"                  # Remove the prefix until the first '-'
            filedate="${filedate%.tar}"
            human_readable_date=$(date -d "$filedate" +"%b %d, %Y")

            echo "$((i+1))) $version - $human_readable_date"
        done
        log_end_msg $?      
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
        log_failure_msg "Usage: $0 {start|stop|logs|clean|cleanup|build|status|monitor|restart|reload|force-reload}"
        exit 1
        ;;
esac

exit



