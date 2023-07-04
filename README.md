# VTTctl Quick Start

## Software Requirements 
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

## Usage

```
./vttctl.sh validate
```

 Update .env with your personal configuration, such as NGINX_PROD_PORT
 
 Copy TIMED URL from FoundryVTT.com, Choose Linux/NodeJS as Operative System and paste it with double quotes as second argument for vttctl.

```
./vttctl.sh download "TIMED_URL"
./vttctl.sh build
./vttctl.sh default
./vttctl.sh start
```

## Contributing

Pull requests are welcome. For major changes, please open an issue first
to discuss what you would like to change.

Please make sure to update tests as appropriate.

## License

[MIT](https://choosealicense.com/licenses/mit/)