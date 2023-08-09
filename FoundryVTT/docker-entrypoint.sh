#!/usr/bin/env ash
decoded_str=$(echo "$base64_vars" | base64 -d | tr '|' ' ')

for var in $decoded_str; do
    export "$var"
done

echo "FQDN=$FQDN"
echo "PROXY_PORT=$PROXY_PORT"

if [ -f "/home/foundry/.firstboot" ]; then
    echo " - Firstboot!"
    rm -rf /home/foundry/.firstboot
else
    sed -i 's/"hostname": null,/"hostname": "${FQDN}",/' /home/foundry/userdata/Config/options.json
    sed -i 's/"proxyPort": null,/"proxyPort": ${PROXY_PORT},/' /home/foundry/userdata/Config/options.json
fi

cd /home/foundry/vtt/
export USER=$(whoami)
echo " - Running FoundryVTT as $USER"
echo " - Running pm2 app foundry ..."
pm2-runtime start --env production --name foundry resources/app/main.js -- --dataPath=/home/foundry/userdata
