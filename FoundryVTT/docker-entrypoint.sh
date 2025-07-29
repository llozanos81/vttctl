#!/usr/bin/env ash
echo "### Starting FoundryVTT Docker container using ... ###"
OPTIONS_FILE=/home/foundry/userdata/Config/options.json

decoded_str=$(echo "$VARS" | base64 -d)
echo "Decoded: $decoded_str"
for var in $decoded_str; do
    export "$var"
done

echo "FQDN=$FQDN"
echo "PROXY_PORT=$PROXY_PORT"

if [ -f "/home/foundry/.firstboot" ]; then
    echo " - Firstboot!"
    rm -rf /home/foundry/.firstboot
else
    sed -i "s/\"hostname\": .*,/\"hostname\": \"${FQDN}\",/" /home/foundry/userdata/Config/options.json
    sed -i "s/\"proxyPort\": .*,/\"proxyPort\": ${PROXY_PORT},/" /home/foundry/userdata/Config/options.json
    sed -i "s/\"upnp\": .*,/\"upnp\": ${UPNP},/" /home/foundry/userdata/Config/options.json
fi

cd /home/foundry/vtt/
export USER=$(whoami)
echo " - Running FoundryVTT as $USER"

# Detect main file path
if [ -f resources/app/main.js ]; then
    MAIN_PATH="resources/app/main.js"
elif [ -f main.js ]; then
    MAIN_PATH="main.js"
else
    echo "Error: Could not find FoundryVTT main.js entrypoint."
    exit 1
fi

echo " - Running pm2 app foundry ..."
pm2-runtime start --env production --name foundry $MAIN_PATH -- --dataPath=/home/foundry/userdata --noupnp=${UPNP} --port=30000
