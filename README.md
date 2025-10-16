# vttctl - FoundryVTT Docker Orchestration

[![FoundryVTT Release Version: v9.280](https://img.shields.io/badge/release-v9.280%20%7C%20v10.312-brightgreen?logo=data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA4AAAAOCAYAAAAfSC3RAAAAAXNSR0IArs4c6QAAAIRlWElmTU0AKgAAAAgABQESAAMAAAABAAEAAAEaAAUAAAABAAAASgEbAAUAAAABAAAAUgEoAAMAAAABAAIAAIdpAAQAAAABAAAAWgAAAAAAAABIAAAAAQAAAEgAAAABAAOgAQADAAAAAQABAACgAgAEAAAAAQAAAA6gAwAEAAAAAQAAAA4AAAAATspU+QAAAAlwSFlzAAALEwAACxMBAJqcGAAAAVlpVFh0WE1MOmNvbS5hZG9iZS54bXAAAAAAADx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IlhNUCBDb3JlIDUuNC4wIj4KICAgPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4KICAgICAgPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIKICAgICAgICAgICAgeG1sbnM6dGlmZj0iaHR0cDovL25zLmFkb2JlLmNvbS90aWZmLzEuMC8iPgogICAgICAgICA8dGlmZjpPcmllbnRhdGlvbj4xPC90aWZmOk9yaWVudGF0aW9uPgogICAgICA8L3JkZjpEZXNjcmlwdGlvbj4KICAgPC9yZGY6UkRGPgo8L3g6eG1wbWV0YT4KTMInWQAAAiFJREFUKBVVks1rE1EUxc+d5tO0prZVSZsUhSBIPyC02ooWurJ0I7rQlRvdC/4N4h9gt7pyoRTswpWgILgQBIOIiC340VhbpC0Ek85MGmPmXc+baWpNGJg77/7uOffeB+z9FHB0FrH9eLwwqpOF0f34KrpsTicW+6L8KE8QhO/n8n1IOgtQHYZA+a/Ai9+Wd6v1g7liq5A2OjKSQNa9hkO4hAzOIylf6CHALk6hoWXsylPkfjyyApaJhVCxmERy5zLSuI7D8h1H5BWht1aBhS6wdI3pN7GabyuyS4JPrchzujmNjDxAVrrRL2PoxRSGxOfjssgEjkkJvVJBWu6h5M7YenvDoOO0OgicD4TPIKWbBG6xvwTaKCMwSU7hKxK6gt8mbsFIMaF5iDyjUg6iPnqc58higCr9fD4iTvWMziAmK2g73f/AADVWX0YXrlChirgOcqL3WXYBYpTfUuxzjkW30dI1C0ZW1RnjMopo4C56MIs6CgQrMER2cJoz9zjdO2iz17g2yZUjqzHWbuA4/ugiEz7DVRe/aLxmcvDQ5Cq+oWGWeDbAgiETXgArrVOFGzR0EkclxrVMcpfLgFThY5roe2yz95ZZkzcbj22+w2VG8Pz6Q/b5Gr6uM9mw04uo6ll4tOlhE8a8xNzGYihCJoT+u3I4kUIp6OM0X9CHHds8frbqsrXlh9CB62nj8L5a9Y4DHR/K68TgcHhoz607Qp34L72X0rdSdM+vAAAAAElFTkSuQmCC)](https://foundryvtt.com/releases/9.280) ![Platforms](https://img.shields.io/badge/platforms-amd64%20%7C%20aarch64-blue)

`vttctl` is a Bash script for managing FoundryVTT installations using Docker. It provides an easy way to download, build, run, backup, and restore FoundryVTT instances with minimal configuration.

## Features

- **Docker-based**: Isolated FoundryVTT environments
- **Version Management**: Support for multiple FoundryVTT versions
- **Backup/Restore**: Automated user data backups
- **Multi-platform**: Supports various Linux distributions
- **Templating**: Dynamic Dockerfile and HTML generation
- **Testing**: Comprehensive BATS test suite

## Quick Start

### Prerequisites

- Linux (amd64/aarch64)
- Docker and Docker Compose
- Bash 4+
- Required tools: `awk`, `curl`, `jq`, `python3`, etc. (see [Requirements](#requirements))

### Installation

```bash
git clone https://github.com/lloZanos81/vttctl
cd vttctl
./vttctl.sh validate
```

### Basic Usage

1. **Download FoundryVTT**:
   ```bash
   ./vttctl.sh download "https://foundryvtt.com/releases/download?version=11.315&platform=linux"
   ```

2. **Build and Start**:
   ```bash
   ./vttctl.sh build
   ./vttctl.sh start
   ```

3. **Access FoundryVTT**:
   - Open `http://localhost:30000` (default port)
   - Check status: `./vttctl.sh info`

## Requirements

The following tools must be installed:

- `awk`, `basename`, `cat`, `curl`, `cp`, `date`, `docker`, `docker-compose`
- `free`, `getent`, `grep`, `id`, `iproute2`, `jq`, `md5sum`
- `python3`, `sed`, `sort`, `timedatectl`, `uname`, `unzip`, `wc`, `xargs`

Run `./vttctl.sh validate` to check and install missing dependencies.

## Supported Platforms

- **Debian/Ubuntu**: 20.04+
- **CentOS/Rocky Linux**: 7, 8, 9
- **Architectures**: amd64, aarch64

## FoundryVTT Version Support

`vttctl` supports multiple FoundryVTT architectures and versions:

- **Electron Applications** (v9, v10, v11, v12): Desktop-style applications with embedded Chromium
  - Executable: `foundryvtt`
  - Libraries: `libEGL.so`, `libGLESv2.so`
  - Package location: `resources/app/package.json`

- **Node.js Applications** (v13+): Server applications with modular structure
  - Directories: `client/`, `common/`, `public/`
  - Package location: `package.json` (root)

All downloads are automatically validated for authenticity and architecture compatibility before installation.

## Configuration

Create a `.env` file or run `./vttctl.sh validate` to generate one:

```bash
# Example .env
NGINX_PROD_PORT=30000
FOUNDRY_UID=3000
FOUNDRY_GID=3000
WEB_PROTO=http
HOSTNAME=your-host
DOMAIN=local
```

## Commands

For a complete command reference, see [docs/commands.md](docs/commands.md).

### Core Commands

- `validate`: Check dependencies and setup
- `download <url>`: Download FoundryVTT from timed URL
- `build`: Build Docker image (interactive)
- `start`: Start services
- `stop`: Stop services
- `backup`: Create user data backup
- `restore`: Restore from backup (interactive)
- `logs`: Show container logs
- `info`: Display system and FoundryVTT info

### Examples

```bash
# Full setup
./vttctl.sh validate
./vttctl.sh download "TIMED_URL"
./vttctl.sh build
./vttctl.sh start

# Backup and restore
./vttctl.sh backup
./vttctl.sh restore

# View logs
./vttctl.sh logs --live
```

## Project Structure

```
vttctl/
├── vttctl.sh              # Main script
├── docker/                # Docker Compose files
├── FoundryVTT/            # Foundry binaries and templates
├── templates/             # Jinja2 templates
├── python/                # Python utilities
├── test/                  # BATS tests
├── docs/                  # Generated documentation
├── backups/               # User data backups
└── .env                   # Configuration
```

## Development

### Running Tests

```bash
bats test/vttctl.bats
```

### Generating Docs

```bash
python3 python/docs_generator.py
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes and add tests
4. Run tests: `bats test/vttctl.bats`
5. Submit a pull request

## Troubleshooting

### Common Issues

- **Port conflicts**: Change `NGINX_PROD_PORT` in `.env`
- **Permission errors**: Ensure Docker can access directories
- **Build failures**: Check Docker logs with `./vttctl.sh logs`
- **Backup issues**: Verify backup directory permissions

### Getting Help

- Run `./vttctl.sh help` for command overview
- Check logs: `./vttctl.sh logs`
- View system info: `./vttctl.sh info`

## License

[MIT](https://choosealicense.com/licenses/mit/)