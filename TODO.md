# TODO v1.0
- fix network interface detection ./vttctl.sh info
- Redo help section
- Add HTTPS support. (Caddy?)
- Add support for Amazon Linux 2
- Add support for CentOS 7
- Add support for RockyLinux 8 and 9
- Add support for Debian 11 and 12
- Add support for Ubuntu 20.04
- Restore vttctl generated backups
- Restore any tar, tar.gz or tar.bz2 backup into vttctl structure.
- validate if downloaded file it's actualy the FoundryVTT application

# DONE
- Create Public URL for created backup using ./vttctl.sh backup
- Validate download URL is the correct for Linux deployment
- Validate if download Zip major version is vttctl supported
- Backup elapsed time at the end of the backup process
- Backup page with CSS from v9, v10 and v11
- Avoid building current or running version, use ./vttctl build --force to force running version rebuild

# DISCARDED
- Add flag for compression using gz for backup like ./vttctl.sh backup -z | Not implemented, most of Foundry assets are already compressed. (webp,webm,ogg,mp3,jpg,etc.)
