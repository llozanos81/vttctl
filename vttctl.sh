#!/usr/bin/env bash
# Version: 0.01

if [ ! -f .env ] && [ $1 != "validate" ]; then
      $0 validate
fi

ENV_FILE=.env
if [ -f ${ENV_FILE} ]; then
  export $(cat .env | xargs)
fi

VTT_NAME=FoundryVTT
NAME=${VTT_NAME}
DESC=Environment
PROD_PROJECT="${NAME}_PROD"
DEV_PROJECT="${NAME}_DEV"
REGEX_URL='(https?|ftp|file)://[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|]'
TAG=${DEFAULT_VER}
GID=$(getent passwd $USER | awk -F: '{print $4}')


# Source function library.
if ! [ -x "/lib/lsb/init-functions" ]; then
        . /lib/lsb/init-functions
else
        echo "E: /lib/lsb/init-functions not found, lsb-base (>= 3.0-6) needed"
        exit 1
fi

if [ -f scripts/functions ]; then
        . ./scripts/functions
fi

IN_DOCKER=$(id -nG "$USER" | grep -qw "docker")

if [[ "root" != ${USER} ]] && [[ $IN_DOCKER ]]; then
    log_failure_msg "Usage: sudo $0 \n - alternative: add $USER to docker group."
    exit 1
fi 

case "$1" in
  validate)
      log_daemon_msg "Validating requirements ..."
      if [ ! -d backups ]; then
       mkdir -p backups/FoundryVTT
       mkdir -p backups/volumes
       mkdir -p downloads/
      fi

      # File containing commands, one command per line
      commands_file="scripts/binary_validation"

      # Read commands from file into an array
      mapfile -t commands < "$commands_file"

      for cmd in "${commands[@]}"; do
       if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Command not found: $cmd"
        log_end_msg $?  
        exit
       fi
      done
      log_end_msg $?

      sed '/^#/d; /^$/d' "dotenv.example" > ".env"

        ;;
  start)
        if [[ -n $DEFAULT_VER ]]; then
            log_daemon_msg "Starting $DESC" "$NAME $DEFAULT_VER"
            echo "Use port $NGINX_PROD_PORT/tcp."
            TAG=$TAG docker-compose -p $PROD_PROJECT -f docker/docker-compose.yml up -d
            if [ "$DEV_ENABLED" == "true" ]; then
                  TAG=$TAG docker-compose -p $DEV_PROJECT -f docker/docker-compose-dev.yml up -d
            fi
            fixOnwer
            log_end_msg $?
         else
             echo "No default FoundryVTT version found."
             $0 default
             $0 start
         fi
        ;;
  stop)
        log_daemon_msg "Stopping $DESC" "$NAME $DEFAULT_VER" 
        stop
        log_end_msg $?
        ;;
  attach)
        APP_CONTAINER=$(docker container ls -a | grep vtt | grep app | awk '{print $1}')
        docker exec -it $APP_CONTAINER ash -c "echo Attaching to FoundryVTT $DEFAULT_VER app container ...;ash"
        ;;
  logs)
        getLogs
        ;;
  clean)
        $0 stop
        echo "Deleting FoundryVTT $DEFAULT_VER containers ..."
        TAG=$TAG docker-compose -p $PROD_PROJECT -f docker/docker-compose.yml down
        TAG=$TAG docker-compose -p $DEV_PROJECT -f docker/docker-compose-dev.yml down
        ;;
  build)
      log_daemon_msg "Building $DESC" "$NAME"
      VERSIONS=$(ls -l FoundryVTT/ | grep "^d" | awk '{print $NF}' | grep "^[0-9]*")
      if [[ -z $VERSIONS ]]; then
            echo "No FoundryVTT binares found, Use $0 download \"TIMED_URL\""
            log_end_msg $?
            ;;
      else
            echo $VERSIONS" version(s) available!"
      fi
      OPT=""
      while [[ $OPT != "0" ]]; do
            word_count=$(echo "$VERSIONS" | wc -w)

            if [[ $word_count -gt 1 ]]; then
                  echo "Choose version to build ('0' to cancel):"
                  count=1

                  for VER in $VERSIONS; do
                        echo "$count) $VER"
                        ((count++))
                  done
                  read -p "Version to build?: " OPT
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
                        #foundry_version="^${MAJOR_VER}\..*"
                        #ALPINE_VER=$(jq -r --arg version "$foundry_version" '.foundryvtt[] | select(.version | test($version)) | .alpine' FoundryVTT/foundryvtt.json)

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
      log_end_msg $?
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
                        if [ $IS_ACTIVE = "true" ]; then
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
      ;;
  restart)
        $0 stop
        sleep 1
        $0 start
        ;;
  backup)
        log_daemon_msg "Backing up Foundry VTT $DEFAULT_VER."
        IS_RUNNING=$($0 status --json=true | jq -r .running)
        if [ $IS_RUNNING ]; then
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
        $0 reload
        log_end_msg $?      
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
                        break
                        ;;
                  *)
                        echo "Invalid option."
                        ;;
            esac
        done
        exit      
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
                  VERSION=$(jq -r .version >/dev/null 2>&1 <<< echo $json)
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






