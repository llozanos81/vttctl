#!/usr/bin/env ash
cd /home/foundry/vtt/
export USER=$(whoami)
echo "Running FoundryVTT as $USER"
echo " "
echo "Running pm2 app VTT ..."
pm2-runtime start --name VTT resources/app/main.js -- --dataPath=/home/foundry/userdata
echo "Stopping container ..."