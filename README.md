Requirements 
- awk
- basename
- bash
- cat
- curl
- cp
- docker
- docker-compose
- getent
- grep
- id
- jq
- rm
- timedatectl
- python3
- sed
- unzip
- wc
- wget
- xargs

Quick Start
./vttctl.sh validate
# Update .env with your personal configuration, such as NGINX_PROD_PORT
# Copy TIMED URL from FoundryVTT.com, Choose Linux/NodeJS as Operative System and paste it with double quotes as second argument for vttctl.
./vttctl.sh download "TIMED_URL"
./vttctl.sh build
./vttctl.sh default
./vttctl.sh start