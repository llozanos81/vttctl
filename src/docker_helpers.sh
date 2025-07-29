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
