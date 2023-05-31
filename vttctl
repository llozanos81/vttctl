#!/usr/bin/env bash
ENV_FILE=.env
if [ -f ${ENV_FILE} ]; then
  export $(cat .env | xargs)
fi

NAME=${VTT_NAME}
DESC=Environment
PROD_PROJECT="${NAME}_PROD"
DEV_PROJECT="${NAME}_DEV"
REGEX_URL='(https?|ftp|file)://[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|]'
TAG=${DEFAULT_VER}

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
  start)
        log_daemon_msg "Starting $DESC" "$NAME"
        TAG=$TAG docker-compose -p $PROD_PROJECT -f docker/docker-compose.yml up -d
        TAG=$TAG docker-compose -p $DEV_PROJECT -f docker/docker-compose-dev.yml up -d
        log_end_msg $?
        ;;
  stop)
        log_daemon_msg "Stopping $DESC" "$NAME"
        stop
        log_end_msg $?
        ;;
  logs)
        getLogs
        ;;
  clean)
        $0 stop
        TAG=$TAG docker-compose -p $PROD_PROJECT -f docker/docker-compose.yml down
        TAG=$TAG docker-compose -p $DEV_PROJECT -f docker/docker-compose-dev.yml down
        ;;
  build)
        log_daemon_msg "Building $DESC" "$NAME"
        VERSIONS=$(ls -l FoundryVTT/ | grep "^d" | awk '{print $NF}' | grep "^[0-9]*")
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
                        OPT=$VERSIONS
                  fi


            if [[ $OPT =~ ^[0-9]+$ && $OPT -ge 1 && $OPT -le $count ]]; then
                  BUILD_VER=$(echo "$VERSIONS" | sed -n "${OPT}p")
                        matching_images=$(docker images | awk '{print $1":"$2}' | grep "$BUILD_VER")
                        if [ -z "$matching_images" ]; then
                              echo "Image 'foundryvtt:$BUILD_VER' not found, building."
                        else
                           read -p "Are you sure you want to rebuild image 'foundryvtt:$BUILD_VER'? (y/n): " confirmation

                              # Process user's confirmation
                              if [ "$confirmation" == "y" ] || [ "$confirmation" == "Y" ]; then
                                    # Delete matching images
                                    docker rmi $matching_images
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

                  rm FoundryVTT/.dockerignore
                  echo "${exclude[@]}" > FoundryVTT/.dockerignore

                  MAJOR_VER="${BUILD_VER%%.*}"
                  foundry_version="^${MAJOR_VER}\..*"
                  ALPINE_VER=$(jq -r --arg version "$foundry_version" '.foundryvtt[] | select(.version | test($version)) | .alpine' FoundryVTT/foundryvtt.json)


                  echo "Building version: $BUILD_VER"
                  cp FoundryVTT/docker-entrypoint.sh FoundryVTT/$BUILD_VER/
                  docker build --build-arg BUILD_VER=$BUILD_VER --build-arg ALPINE_VER=$ALPINE_VER \
                         -t foundryvtt:$BUILD_VER \
                         -f ./FoundryVTT/Dockerfile ./FoundryVTT
                  break
            elif [[ $OPT != "0" ]]; then
                  echo "Invalid option."
            fi
            done
        exit

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
  status)
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
        log_daemon_msg "Backing up Foundry VTT."
        prodBackup
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
        #$0 reload
        log_end_msg $?      
        ;;
  default)
        log_daemon_msg "Setting default version of Foundry VTT."
        
        log_end_msg $?      
        ;; 
  download)
        if [[ $2 =~ $REGEX_URL ]]; then 
            U_EXPIRES=$(echo $2 | awk -F= '{print $4}')
            U_NOW=$(date '+%s')
            if [[ U_NOW -gt U_EXPIRES ]]; then
                echo "Foundry VTT Timed URL expired."
                false
                log_end_msg $? 
            else
                FILE=$(basename $(echo $2 | awk -F\? '{ print $1 }'))
                echo $FILE
                log_daemon_msg "Downloading Foundry VTT version v$VERSION"
                true
                log_end_msg $?      
            fi
        else
            echo "Usage: $0 download \"Foundry VTT Linux/NodeJS download timed URL\""
        fi
        ;;   
  *)
        log_failure_msg "Usage: $N {start|stop|logs|clean|build|rebuild|status|restart|reload|force-reload}"
        exit 1
        ;;
esac






