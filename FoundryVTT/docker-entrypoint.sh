#!/usr/bin/env ash
cd /home/foundry/vtt/
export USER=$(whoami)
echo "Running FoundryVTT as $USER"
echo " "
echo "Cleaning environment ..."
rm -rf node.pid
rm -rf reload.txt

echo "Running node app ..."
while [ 1 ]
do
    if [ ! -f node.pid ]; then
        node resources/app/main.js --dataPath=/home/foundry/userdata --noupnp &
        ps | grep node | grep -v grep | awk '{print $1}' > node.pid
    fi

    if [ -f reload.txt ]; then
        export PID=$(cat node.pid)
        echo "Waiting for process ID $PID to finish ..."
        sleep 5
        kill $PID
        rm -rf node.pid
        rm -rf reload.txt
    fi
sleep 5
done


echo "Stopping container ..."