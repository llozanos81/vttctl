#!/usr/bin/env ash
echo "$VARS" | base64 -d | xargs -d'|' -i export {}
if [ -f "/home/foundry/.firstboot" ]; then
    echo "Firstboot!"
    rm -rf /home/foundry/.firstboot
else
    sed -i 's/"hostname": null,/"hostname": "${FQDN}",/' /home/foundry/userdata/Config/options.json
    sed -i 's/"proxyPort": null,/"proxyPort": "${PROXY_PORT}",/' /home/foundry/userdata/Config/options.json
fi

cd /home/foundry/vtt/
export USER=$(whoami)
echo "Running FoundryVTT as $USER"
echo " "
echo "Running pm2 app VTT ..."
pm2-runtime start --env production --name foundry resources/app/main.js -- --dataPath=/home/foundry/userdata
