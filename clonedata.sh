#!/usr/bin/env bash
src="10.291"
dst="11.299"

CLONER_NAME=dataReplicator
PROD_USERDATA="foundryvtt_prod_UserData$src"
DEV_USERDATA="foundryvtt_dev_UserData$dst"
docker run -v $PROD_USERDATA:/source -v $PROD_USERDATA:/destination -dit --name $CLONER_NAME alpine sh
docker exec $CLONER_NAME \
            rsync -avz --exclude '/source/Data/modules/jb2a_patreon' \
             /source/ /destination/
docker stop $CLONER_NAME
docker rm $CLONER_NAME
       
