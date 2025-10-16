# vttctl Commands Reference

This document provides a detailed reference for all available `vttctl.sh` commands.

## Command List


### `start`
**Description:** Start FoundryVTT services (production and optionally dev)

**Usage:**
```
./vttctl.sh start
```




**Examples:**

```
./vttctl.sh start
```




### `stop`
**Description:** Stop FoundryVTT services

**Usage:**
```
./vttctl.sh stop [--all]
```


**Options:**

- `--all`: Stop all services including dev




**Examples:**

```
./vttctl.sh stop
```

```
./vttctl.sh stop --all
```




### `build`
**Description:** Build Docker images for FoundryVTT (interactive version selection)

**Usage:**
```
./vttctl.sh build [--force]
```


**Options:**

- `--force`: Force rebuild of running version




**Examples:**

```
./vttctl.sh build
```




### `backup`
**Description:** Create a backup of FoundryVTT user data

**Usage:**
```
./vttctl.sh backup [--cleanup]
```


**Options:**

- `--cleanup`: Interactive cleanup of old backups




**Examples:**

```
./vttctl.sh backup
```

```
./vttctl.sh backup --cleanup
```




### `restore`
**Description:** Restore FoundryVTT user data from backup (interactive)

**Usage:**
```
./vttctl.sh restore
```




**Examples:**

```
./vttctl.sh restore
```




### `logs`
**Description:** Show logs

**Usage:**
```
./vttctl.sh logs [--live]
```


**Options:**

- `--live`: Live log tailing




**Examples:**

```
./vttctl.sh logs
```

```
./vttctl.sh logs --live
```




### `clean`
**Description:** Remove containers

**Usage:**
```
./vttctl.sh clean [--all]
```


**Options:**

- `--all`: Remove all user data and volumes




**Examples:**

```
./vttctl.sh clean
```

```
./vttctl.sh clean --all
```




### `validate`
**Description:** Check dependencies and generate .env if missing

**Usage:**
```
./vttctl.sh validate
```




**Examples:**

```
./vttctl.sh validate
```




### `wizard`
**Description:** Interactive configuration wizard for .env file setup

**Usage:**
```
./vttctl.sh wizard
```




**Examples:**

```
./vttctl.sh wizard
```




### `download`
**Description:** Download FoundryVTT zip from timed URL

**Usage:**
```
./vttctl.sh download "<TIMED_URL>"
```




**Examples:**

```
./vttctl.sh download "https://foundryvtt.com/..."
```




### `info`
**Description:** Show FoundryVTT and system info

**Usage:**
```
./vttctl.sh info
```




**Examples:**

```
./vttctl.sh info
```




### `help`
**Description:** Show help and usage information

**Usage:**
```
./vttctl.sh help
```




**Examples:**

```
./vttctl.sh help
```





## Getting Help

Run `./vttctl.sh help` for a quick overview of commands and options.