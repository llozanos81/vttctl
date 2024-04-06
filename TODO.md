# TODO v1.0
- validate for docker frontend network
- Redo help section
- Integrate with Traefik
- Add HTTPS support. (traefik?)
- Add support for Amazon Linux 2
- Restore vttctl generated backups
- Restore any foundryvtt backup tar, tar.gz or tar.bz2 into vttctl structure.
- Do not allow creation of vttctl backups if FoundryVTT version is 11.311 or newer (use native tool instead).
- validate if downloaded file it's actually the FoundryVTT NodeJS application
- Add configuration Wizard for env file
- Add upgrade VTT version option
- Add security to /backups (.htaccess?)
- Create a binary instead of a script
- Integrate with bash autocomplete

# DONE
- Change logging, drop use of lsb functions
- Create Public URL for created backup using ./vttctl.sh backup
- Validate download URL is the correct ZIP file for Linux deployment
- Validate if download Zip major version is vttctl supported
- fix network interface detection ./vttctl.sh info
- Backup elapsed time at the end of the backup process
- Backup page with fonts and CSS from v9, v10 and v11
- Avoid building current or running version, use ./vttctl build --force to force running version rebuild
- Add support for CentOS 7
- Add support for RockyLinux 8 and 9
- Add support for Debian 12
- Add support for Ubuntu 20.04
- Improved docker image building process
- docker compose compatibility (docker-compose alias)


# DISCARDED
- Add a flag for compression using 'gz' for backups, like './vttctl.sh backup -z'. It's not implemented because most of Foundry's assets are already compressed (webp, webm, ogg, mp3, jpg, etc.). Compressing them again would result in diminishing returns.

