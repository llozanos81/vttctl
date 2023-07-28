# TODO v1.0
- fix network interface detection ./vttctl.sh info
- Backup page with CSS from v9 and 10
- avoid build current or running version
- Redo help section
- Add HTTPS support. (Caddy?)
- Add support for Amazon Linux 2
- Add support for CentOS 7
- Add support for RockyLinux 8 and 9
- Add support for Debian 11 and 12
- Add support for Ubuntu 20.04

# DONE
- Create Public URL for created backup using ./vttctl.sh backup
- Validate download URL is the correct for Linux deployment
- Validate if download Zip major version is vttctl supported
- Backup elapsed time at the end of the backup process

# DISCARDED
- Add flag for compression using gz for backup like ./vttctl.sh backup -z | Not implemented, most of Foundry assets are already compressed. (webp,webm,ogg,etc.)
