#!/usr/bin/env bash
# Version: 0.01

function stop() {
    docker-compose -p $PROD_PROJECT -f docker/docker-compose.yml stop
    docker-compose -p $DEV_PROJECT -f docker/docker-compose-dev.yml stop
}

function getLogs() {
    docker-compose -p $PROD_PROJECT -f docker/docker-compose.yml logs
}

function liveLogs() {
    docker-compose -p $PROD_PROJECT -f docker/docker-compose.yml logs -f
}

function getVersion() {
    RESPONSE=/tmp/.response.txt
    rm -rf $RESPONSE
    status=$(curl -s -w %{http_code} http://localhost:${NGINX_PROD_PORT}/api/status -H "Accept: application/json" -o $RESPONSE)
    if [ $status == 200 ]; then
        cat $RESPONSE
    else
        echo "{ 'active': 'false' }"
    fi
}

function appReload() {
    CONT_NAME=$(docker container ls -a | grep vtt | grep app | grep prod | awk '{print $1}')
    docker exec -d $CONT_NAME pm2 restart foundry
}

function prodBackup()  {
    METADATA="backups/FoundryVTT/metadata.json"
    CONT_NAME=$(docker container ls -a | grep vtt | grep app | grep prod | awk '{print $1}')
    json=$(getVersion)
    if jq -e . >/dev/null 2>&1 <<<"$json"; then
        PROD_VER=$(echo $json | jq -r .version)
        if [[ -n $PROD_VER ]]; then
            DATESTAMP=$(date +"%Y%m%d")
            BACKUP_FILE=foundry_userdata_${PROD_VER}-${DATESTAMP}.tar

            docker run \
                --rm \
                -v foundryvtt_prod_UserData:/source/ \
                -v $(pwd)/backups/FoundryVTT/:/backup \
                busybox \
                ash -c " \
                tar -cvf /backup/$BACKUP_FILE \
                    -C / /source \
                ; chown $UID:$GID /backup/$BACKUP_FILE" >/dev/null 2>&1 &

            BACKPID=$!

            i=1
            sp="/-\|"
            echo -n ' '
            while [ -d /proc/$BACKPID ]; do
                printf "\r%c" "${sp:0:1}"
                sp="${sp:1}${sp:0:1}"
                sleep 0.05
            done

            DATE_FILE=$(stat --format="%y" "backups/FoundryVTT/$BACKUP_FILE" | awk {'print $1'})
            new_object="{\"$DATE_FILE\": {\"Version\": \"${PROD_VER}\", \"File\": \"${BACKUP_FILE}\"}}"
            python3 -c "import json; \
                        obj = $new_object; \
                        filename = '${METADATA}'; \
                        data = json.load(open(filename)) \
                        if filename else []; \
                        data.append(obj) \
                        if obj not in data else None; \
                        json.dump(data, open(filename, 'w'), indent=2)"
            printf "\r   - %s backup file created\n" "$BACKUP_FILE"
            echo "   - Done!."
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
    CONT_NAME=$(docker container ls -a | grep vtt | grep app | grep dev | awk '{print $1}')
    
    docker run \
                --rm \
                --volumes-from $CONT_NAME \
                -v $(pwd)/backups/FoundryVTT/:/backup \
                busybox \
                tar -xvf /backup/${FILE_NAME} -C /

}

function fixOnwer() {
    CONT_NAME=$(docker container ls -a | grep vtt | grep app | grep prod | awk '{print $1}')
    docker run --rm --volumes-from ${CONT_NAME} busybox chown 3000:3000 -R /home/foundry/userdata
}

function fixConfig() {
      CONT_NAME=$(docker container ls -a | grep vtt | grep app | grep prod | awk '{print $1}')
      docker run --rm --volumes-from ${CONT_NAME} busybox ash -c \
            "sed -i 's/\"upnp\": true/\"upnp\": false/' /home/foundry/userdata/Config/options.json"
}

function getIPaddr() {
    gateway_ip=$(ip route | awk '/default/ {print $3}' | sort -u)
    interface=$(ip route get $gateway_ip | awk '/dev/ {print $3}')
    ip_address=$(ip -o -4 addr show dev $interface | awk '{print $4}' | awk -F '/' '{print $1}')
    echo $ip_address
}

function getReleases() {
    url="https://foundryvtt.com/releases/"
    html_content=$(curl -s "$url")

    # Set custom record separator to </li>
    # Extract <li> elements containing the stable release
    stable_li_elements=$(awk -v RS='</li>' '/<span class="release-tag stable">Stable<\/span>/{print $0 "</li>"}' <<< "$html_content")

    # Extract the release versions from stable <li> elements
    release_versions=$(echo "$stable_li_elements" | grep -oP '(?<=<a href="/releases/)(9|[1-9][0-9]+)\.\d+')
    
    file_path="FoundryVTT/foundry_releases.json"
    max_age_days=1
    file_age=$(($(date +%s) - $(date -r "$file_path" +%s)))
 
    versions=()
    current_version=""

    while IFS= read -r line; do
    version=$(echo "$line" | awk -F '.' '{print $1}')
    build=$(echo "$line" | awk -F '.' '{print $2}')

    if [[ "$version" != "$current_version" ]]; then
        versions+=("{\"version\":\"$version\",\"build\":[{\"number\":$build,\"latest\":false}]}")
        current_version=$version
    else
        index=$((${#versions[@]} - 1))
        versions[$index]=$(jq ".build += [{\"number\":$build,\"latest\":false}]" <<< "${versions[$index]}")
        last_index=$(($index - 1))
        versions[$last_index]=$(jq ".build[-1].latest=true" <<< "${versions[$last_index]}")
    fi
    done <<< "$output"

    last_index=$((${#versions[@]} - 1))
    versions[$last_index]=$(jq ".build[-1].latest=true" <<< "${versions[$last_index]}")

    json=$(jq -n "{\"versions\":[$(IFS=,; echo "${versions[*]}")]}" 2>/dev/null)

    echo "$json" > "$file_path"

}

function isPlatformSupported() {
      platform="$1 $2 $3"
      supported=(
            "Ubuntu 22.04 aarch64"
            "Ubuntu 22.04 x86_64"
      )

      for p in "${supported[@]}"; do
            if [[ "$p" == "$platform" ]]; then
                  matchFound=true
                  echo -e "\e[92msupported\e[39m"
                  break
            fi
      done

      if [ ! $matchFound ]; then
            echo "\e[93mnot validated\e[39m"
      fi
}

ENV_FILE=.env
if [ ! -f .env ] && [ $1 != "validate" ]; then
      $0 validate
elif [ -f ${ENV_FILE} ]; then
      export $(cat .env | xargs)
fi

VTT_NAME=FoundryVTT
NAME=${VTT_NAME}
DESC=Environment
PROD_PROJECT="${NAME}_prod"
PROD_PROJECT=${PROD_PROJECT,,}
DEV_PROJECT="${NAME}_dev"
DEV_PROJECT=${DEV_PROJECT,,}
REGEX_URL='(https?|ftp|file)://[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|]'
TAG=${DEFAULT_VER}
GID=$(getent passwd $USER | awk -F: '{print $4}')
CPU_COUNT=$(cat /proc/cpuinfo | grep processor | wc -l)
TOTAL_RAM=$(free -mh | grep Mem | awk '{gsub(/i/, "B", $2); print $2}')

if ! command -v "lsb_release" >/dev/null 2>&1; then
      LINUX_DISTRO="N/A lsb_release missing"
else
      LINUX_DISTRO=$(lsb_release -sir | head -1)
      DISTRO_VERSION=$(lsb_release -sir | tail -1)
fi

if ! command -v "uname" >/dev/null 2>&1; then
      CPU_ARCH="N/A uname missing."
else
      CPU_ARCH=$(uname -m)
fi




# Source function library.
if ! [ -x "/lib/lsb/init-functions" ]; then
        . /lib/lsb/init-functions
elif ! [ -x "/etc/init.d/functions" ]; then
        . /etc/init.d/functions

      function log_failure_msg() {
            echo " * "$1 $2 $3           
      }

      function log_daemon_msg() {
            echo " * "$1 $2 $3      
      }

      function log_end_msg() {
            echo " * "$1 $2 $3
      }

else
        echo "E: /lib/lsb/init-functions or /etc/init.d/functions not found, lsb-base needed"
        exit 1
fi


IN_DOCKER=$(id -nG "$USER" | grep -qw "docker")

if [[ "root" != ${USER} ]] && [[ $IN_DOCKER ]]; then
    log_failure_msg "Usage: sudo $0 \n - alternative: add $USER to docker group."
    exit 1
fi 

case "$1" in
  attach)
        APP_CONTAINER=$(docker container ls -a | grep vtt | grep app | awk '{print $1}')
        docker exec -it $APP_CONTAINER ash -c "echo Attaching to FoundryVTT $DEFAULT_VER app container ...;ash"
        ;;
  build)
      log_daemon_msg "Building $DESC" "$NAME"
      VERSIONS=$(ls -l FoundryVTT/ | grep "^d" | awk '{print $NF}' | grep "^[0-9]*")
      if [[ -z $VERSIONS ]]; then
            log_daemon_msg " No FoundryVTT binares found, Use $0 download \"TIMED_URL\""
            log_end_msg $?
      else
            log_daemon_msg " "$VERSIONS" version(s) available!"
            OPT=""
            while [[ $OPT != "0" ]]; do
                  word_count=$(echo "$VERSIONS" | wc -w)

                  if [[ $word_count -gt 1 ]]; then
                        echo " Choose version to build ('0' to cancel):"
                        count=1

                        for VER in $VERSIONS; do
                              echo " $count) $VER"
                              ((count++))
                        done
                        read -p " Version to build?: " OPT
                  else 
                        OPT=1
                        echo "Building FoundryVTT $VERSIONS ..."
                  fi

                  case $OPT in
                        [1-9])
                              BUILD_VER=$(echo "$VERSIONS" | sed -n "${OPT}p")
                              matching_images=$(docker images | awk '{print $1":"$2}' | grep "$BUILD_VER")
                              if [ -z "$matching_images" ]; then
                                    echo "Image 'foundryvtt:$BUILD_VER' not found, building."
                              else
                                    read -p "Are you sure you want to rebuild image 'foundryvtt:$BUILD_VER'? (y/n): " confirmation

                                    # Process user's confirmation
                                    if [ "$confirmation" == "y" ] || [ "$confirmation" == "Y" ]; then
                                          $0 clean
                                          # Delete matching images
                                          docker rmi $matching_images >/dev/null 2>&1
                                          echo "Image(s) matching '$BUILD_VER' deleted. Re-building."
                                    else
                                          echo "Image building cancelled."
                                          exit
                                    fi
                              fi


                              for EX in $VERSIONS; do
                                    if [[ "$EX" != "$BUILD_VER" ]]; then
                                          exclude+=($EX)
                                    fi
                              done

                              rm FoundryVTT/.dockerignore >/dev/null 2>&1
                              echo "${exclude[@]}" > FoundryVTT/.dockerignore

                              MAJOR_VER="${BUILD_VER%%.*}"
                              TIMEZONE=$(timedatectl | grep "Time zone" | awk {'print $3'})

                              echo "Building version: $BUILD_VER"
                              cp FoundryVTT/Dockerfile.$MAJOR_VER FoundryVTT/Dockerfile
                              cp FoundryVTT/docker-entrypoint.sh FoundryVTT/$BUILD_VER/
                              docker build --progress=plain \
                                    --build-arg BUILD_VER=$BUILD_VER \
                                    --build-arg TIMEZONE=$TIMEZONE \
                                    -t foundryvtt:$BUILD_VER \
                                    -f ./FoundryVTT/Dockerfile ./FoundryVTT
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
      ;;
  clean)  
        $0 stop
        echo "Deleting FoundryVTT $DEFAULT_VER containers ..."
        TAG=$TAG docker-compose -p $PROD_PROJECT -f docker/docker-compose.yml down
        TAG=$TAG docker-compose -p $DEV_PROJECT -f docker/docker-compose-dev.yml down
        ;;
  default)
        if [ ! -n $DEFAULT_VER ]; then
            VERSIONS=$(docker images -a | grep vtt | awk {'print $2'})
            word_count=$(echo "$VERSIONS" | wc -w)
            if [ $word_count == 1 ]; then
                  echo $VERSIONS
            fi
        fi
        log_daemon_msg "Setting default version of Foundry VTT. (Current $DEFAULT_VER)"
        VERSIONS=$(docker images -a | grep vtt | awk {'print $2'})
        OPT=""
        while [[ $OPT != "0" ]]; do
              word_count=$(echo "$VERSIONS" | wc -w)
              if [[ $word_count -gt 1 ]]; then
                  echo "Choose version to build ('0' to cancel):"
                  count=1

                  for VER in $VERSIONS; do
                        if [ $VER = $DEFAULT_VER ]; then
                              echo -e "$count) \e[1;32m$VER\e[0m"
                        else
                              echo "$count) $VER"
                        fi
                        ((count++))
                  done
                  read -p "Version to set as default?: " OPT
              else 
                  OPT=1
              fi

            case $OPT in
                  [1-9])
                        NEW_DEFAULT_VER=$(echo "$VERSIONS" | sed -n "${OPT}p")
                        sed -i "s/^DEFAULT_VER=.*/DEFAULT_VER=$NEW_DEFAULT_VER/" ".env"
                        echo "New default version is $NEW_DEFAULT_VER."
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
        exit      
        ;; 
  validate)
      log_daemon_msg "Validating requirements ..."
      if [ ! -d backups ]; then
       mkdir -p backups/FoundryVTT
       mkdir -p backups/volumes
       mkdir -p downloads/
       echo "[]" > backups/FoundryVTT/metadata.json
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
                unzip
                wc
                wget
                xargs)

      for cmd in "${commands[@]}"; do
       if ! command -v "$cmd" >/dev/null 2>&1; then
        log_daemon_msg " - Command not found: $cmd"
        false
        log_end_msg $?  
        exit
       fi
      done
      


      if [ ! -f .env ]; then
            log_daemon_msg " - File .env does not exist, Generating ..."
            sed '/^#/d; /^$/d' "dotenv.example" > ".env"
      else
            log_daemon_msg " - File .env exists."
      fi
      log_end_msg $?
      
        ;;
  start)
        if [[ -n $DEFAULT_VER ]]; then
            log_daemon_msg "Starting $DESC" "$NAME $DEFAULT_VER"
            TAG=$TAG docker-compose -p $PROD_PROJECT -f docker/docker-compose.yml up -d
            if [ "$DEV_ENABLED" == "true" ]; then
                  TAG=$TAG docker-compose -p $DEV_PROJECT -f docker/docker-compose-dev.yml up -d
            fi
            fixOnwer
            $0 info
            log_end_msg $?
         else
             echo "No default FoundryVTT version found."
             $0 default
             $0 start
         fi
        ;;
  stop)
        IS_RUNNING=$($0 status --json=true | jq -r .running)
        if [ $IS_RUNNING ]; then
            RUNNING_VERSION=$($0 status --json=true | jq -r .version)
            log_daemon_msg "Stopping $DESC" "$NAME $RUNNING_VERSION."   
            stop
        else
            echo " - Foundry VTT not running."
        fi  
        log_end_msg $?
        ;;

  logs)
        if [[ -n $2 && $2 == "--live" ]]; then
            liveLogs
        else
            getLogs
        fi
        ;;

  rebuild)
        $0 clean
        $0 build
        log_end_msg $?
        ;;   
  reload|force-reload)
        log_daemon_msg "Reloading $DESC configuration files for" "$NAME"
        appReload
        log_end_msg $?
        ;;
  info)
         json=$(getVersion)
         if [[ ! -z "$json" ]]; then
                if jq -e . >/dev/null 2>&1 <<<"$json"; then
                        IS_ACTIVE=$(echo $json | jq .active)
                        VERSION=$(echo $json | jq -r .version)
                        SUPPORT=$(isPlatformSupported $LINUX_DISTRO $DISTRO_VERSION $CPU_ARCH)
                        LOCAL_IP=$(getIPaddr)
                        ETHERNET=$(ip add | grep -B2 $LOCAL_IP | grep UP | awk {'print $2'} | awk '{sub(/.$/,"")}1')
                        PUBLIC_IP=$(curl -s ifconfig.co)
                        if [ $IS_ACTIVE = "true" ]; then
                                WORLD=$(echo $json | jq -r .world)
                                SYSTEM=$(echo $json | jq -r .system)
                                log_daemon_msg "Foundry VTT v$VERSION is running."
                                log_daemon_msg " System: ${SYSTEM}"
                                log_daemon_msg " World: ${WORLD//-/ }"

                        else
                                log_daemon_msg "Foundry VTT v$VERSION is running BUT world not active."
                        fi
                        log_daemon_msg " --------------- System Info ---------------"
                        log_daemon_msg " Platform: ${LINUX_DISTRO} ${DISTRO_VERSION} ${CPU_ARCH} ${SUPPORT}."
                        log_daemon_msg " Network $ETHERNET config:"
                        log_daemon_msg "  Public IP: ${PUBLIC_IP}"
                        log_daemon_msg "  Internal IP: ${LOCAL_IP}"
                        log_daemon_msg "  FoundryVTT port: TCP/${NGINX_PROD_PORT}"

                        true
                        log_end_msg $?
                else
                        false
                        log_daemon_msg "Foundry VTT is not running."
                        log_end_msg $?
                fi
         else
                log_daemon_msg "Foundry VTT is not running."
                log_end_msg $?      
         fi
      ;;
  restart)
        $0 stop
        sleep 1
        $0 start
        ;;
  backup)
        IS_RUNNING=$($0 status --json=true | jq -r .running)
        if [ $IS_RUNNING ]; then
            RUNNING_VERSION=$($0 status --json=true | jq -r .version)
            log_daemon_msg "Backing up Foundry VTT $RUNNING_VERSION."   
           prodBackup
        else
            echo " - Foundry VTT not running."
        fi
        
        log_end_msg $?      
        ;;
  restore)
        log_daemon_msg "Restoring up Foundry VTT."
        prodLatestRestore
        $0 reload
        log_end_msg $?      
        ;;
  restoredev)
        log_daemon_msg "Restoring up Foundry VTT."
        devLatestRestore
        $0 reload
        log_end_msg $?      
        ;;
  fix)
        log_daemon_msg "Fixing permissions for Foundry VTT."
        fixOnwer
        fixConfig
        $0 reload
        log_end_msg $?      
        ;;

  download)
        if [[ $2 =~ $REGEX_URL ]]; then 
            VERSION=$(echo "$2" | grep -oP "(?<=releases\/)\d+\.\d+")
            MAJOR_VER="${VERSION%%.*}"
            if [[ $MAJOR_VER -ge 9 ]]; then
                  DEST="FoundryVTT"
                  count=$(find $DEST/ -type d -name "[0-9][0-9].*[0-9][0-9][0-9]" | wc -l)
                  if [ $count -gt 9 ]; then
                        echo "To many downloaded FoundryVTT binaries, please do $0 clean and remove at least 1 old version."
                        break
                  fi
                  
                  TARGET="${DEST}/${VERSION}"

                  FILE=$(basename "$2" | awk -F\? {'print $1'})
                  rm -rf "${DEST}/${VERSION}" >/dev/null 2>&1;
                  wget -O downloads/$FILE $2
                  echo "Extracting $FILE to ${TARGET}/ ..."
                  unzip -qq -o downloads/$FILE -d ${TARGET}/
                  VER=$(cat ${TARGET}/resources/app/package.json | jq -r '"\(.release.generation).\(.release.build)"')
                  cp ${DEST}/docker-entrypoint.sh ${TARGET}
            else
                  echo "Version $MAJOR_VER not supported."
            fi
        else
            echo "Usage: $0 download \"Foundry VTT Linux/NodeJS download timed URL\""
        fi
        ;;
  monitor)
            CONT_NAME=$(docker container ls -a | grep vtt | grep app | grep prod | awk '{print $1}')
            docker exec -it $CONT_NAME pm2 monit
        ;;
  status)
      json=$(getVersion)
      if [[ -n $2 && $2 == "--json=true" ]]; then      
            if [[ ! -z "$json" ]]; then
                  VERSION=$(echo $json | jq -r .version)
                  if [[ ! -z "$VERSION" ]]; then
                        echo "{ \"running\": true, \"version\": \"$VERSION\"}"
                  else
                        echo "{ \"running\": false }"
                  fi
            fi
      else
            echo "Foundry VTT version $DEFAULT_VER enabled"
      fi
      
      ;;
  cleanup)
      DIR_VERSIONS=$(ls -l FoundryVTT/ | grep "^d" | awk '{print $NF}' | grep "^[0-9]*")
      IMG_VERSIONS=$(docker images -a | grep vtt | awk {'print $1":"$2'})
      BIN_VERSIONS=$(ls downloads/ | grep -E '[0-9]{2,3}\.[0-9]{2,3}')

      declare -A word_counts

      # Loop through each variable
      for var_name in DIR_VERSIONS IMG_VERSIONS BIN_VERSIONS; do
            var_value=${!var_name}  # Get the value of the variable using indirect expansion
            word_count=$(echo "$var_value" | wc -w)
            word_counts[$var_name]=$word_count
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
      echo "Default version $DEFAULT_VER"
      while [[ $OPT != "0" ]]; do
            list=()
            echo "Choose version to clean/delete ('0' to cancel):"
            for i in $BIGGEST; do
                  [[ $i =~ $pattern ]] && version="${BASH_REMATCH[0]}"
                  if [ ! $version == $DEFAULT_VER ]; then
                        list+=($version)
                        echo "$count) $version"
                        ((count++))
                  fi
            done
            read -p "Version to clean/delete?: " OPT

            case $OPT in
                  [1-9])
                        ((OPT--))
                        DEL_VER=${list[$OPT]}
                        read -p "Are you sure you want to remove all v$DEL_VER related assets? (y/n): " confirmation
                        if [ "$confirmation" == "y" ] || [ "$confirmation" == "Y" ]; then
                              echo "Deleting zip file ..."
                              rm -f downloads/*$DEL_VER* >/dev/null 2>&1
                              echo "Deleting extracted folder ..."
                              rm -rf FoundryVTT/$DEL_VER/ >/dev/null 2>&1
                              echo "Deleting Docker image ..."
                              docker image rm foundryvtt:$DEL_VER >/dev/null 2>&1
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
      ;;
  *)
        log_failure_msg "Usage: $N {start|stop|logs|clean|cleanup|build|rebuild|status|monitor|restart|reload|force-reload}"
        exit 1
        ;;
esac






