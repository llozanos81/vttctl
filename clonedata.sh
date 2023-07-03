#!/usr/bin/env bash
ENV_FILE=.env
if [ -f ${ENV_FILE} ]; then
  export $(cat .env | xargs)
fi

docker run \
       --rm \
       -v foundryvtt_prod_UserData:/source/ \
       -v shared_michaelghelfi:/destination/ \
       busybox \
       ash -c "rm -rf /destination/*; \
               cp -aur /source/Data/modules/michaelghelfi /destination/; \
               mv /destination/michaelghelfi/* /destination/; \
               rm -rf /destination/michaelghelfi/"

       
       #ls -hal /source/Data/modules/jb2a_patreon/
