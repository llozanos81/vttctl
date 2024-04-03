#!/usr/bin/env ash
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
echo " - Running pm2 app foundry ..."
pm2-runtime start --env production --name foundry resources/app/main.js -- --dataPath=/home/foundry/userdata --noupnp=${UPNP} --port=30000
