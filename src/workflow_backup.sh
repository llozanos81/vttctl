#!/bin/bash

# Centralized version parsing function
parse_version() {
    # Usage: parse_version <filename>
    # Outputs: version, date
    local filename="$1"
    local version date
    version=$(echo "$filename" | grep -oP '\d+\.\d{3}')
    date=$(echo "$filename" | grep -oP '(?<=-)(2\d{7})(?=\.)')
    echo "$version|$date"
}

# Use portable shell constructs for file listing and avoid parsing ls output
generateBackupListing() {
    local BACKUP_INDEX="${1}"
    local MAJOR_VER="${2}"
    local VTT_HOME="${3}"
    local BACKUP_DIR="${4}"
    local BACKUP_REFRESH="${5}"
    local VTTCTL_VERSION="${6}"

    # Fallback to current directory if VTT_HOME is empty
    if [[ -z "${VTT_HOME}" ]]; then
        VTT_HOME="$(pwd)"
    fi

    # If BACKUP_INDEX is empty, set default path
    if [[ -z "${BACKUP_INDEX}" ]]; then
        BACKUP_INDEX="${VTT_HOME}/backups/FoundryVTT/index.html"
        log_daemon_msg "No BACKUP_INDEX provided, using default: ${BACKUP_INDEX}"
    fi

    local TEMPLATE_VER=""
    case "${MAJOR_VER}" in
        9|10) TEMPLATE_VER=9 ;;
        11|12) TEMPLATE_VER=11 ;;
        *) TEMPLATE_VER=13 ;;
    esac

    local BACKUP_TEMPLATE="${VTT_HOME}/FoundryVTT/templates/backups.${TEMPLATE_VER}.hbs"
    local BACKUP_FILE_TABLE=""

    # Debug log for template path
    log_daemon_msg "Looking for backup template at: ${BACKUP_TEMPLATE}"

    # Verifica que el template existe antes de usarlo
    if [[ ! -f "${BACKUP_TEMPLATE}" ]]; then
        log_failure_msg "Backup template not found: ${BACKUP_TEMPLATE}"
        return 1
    fi

    shopt -s nullglob
    for file in "${BACKUP_DIR}/"*.tar*; do
        [ -f "$file" ] || continue
        filename=$(basename "$file")
        IFS="|" read -r version raw_date <<< "$(parse_version "$filename")"
        date=""
        if [ -n "$raw_date" ]; then
            date=$(date -d "$raw_date" +'%Y-%m-%d' 2>/dev/null || echo "$raw_date")
        fi
        size=$(stat -c "%s" "$file" 2>/dev/null || stat -f "%z" "$file")
        size_human=$(du -h "$file" | awk '{print $1}')
        md5=$(md5sum "$file" 2>/dev/null | awk '{print $1}')
        BACKUP_FILE_TABLE="${BACKUP_FILE_TABLE}<tr>
        <td><a href='${filename}'>${filename}</a></td>
        <td>${version}</td>
        <td>${date}</td>
        <td>${size_human}</td>
        <td>${md5}</td>
        </tr>"
    done
    shopt -u nullglob

    # Before writing, check that BACKUP_INDEX is not empty and is a valid path
    if [[ -z "${BACKUP_INDEX}" ]]; then
        log_failure_msg "Backup index path is empty. Cannot write backup listing."
        return 1
    fi

    awk -v refresh="${BACKUP_REFRESH}" \
        -v file_table="${BACKUP_FILE_TABLE}" \
        -v version="${VTTCTL_VERSION}" '
    {
        gsub("{{BACKUP_REFRESH}}", refresh);
        gsub("{{BACKUP_FILE_TABLE}}", file_table);
        gsub("{{VTTCTL_VERSION}}", version);
        print;
    }
    ' "${BACKUP_TEMPLATE}" > "${BACKUP_INDEX}" || {
        log_failure_msg "Failed to write backup listing to ${BACKUP_INDEX}"
        return 1
    }
}

create_backup()  {
    local PROD_VER="$1"
    local BACKUP_HOME="$2"
    local USER_ID="$3"
    local GROUP_ID="$4"
    local WEB_PROTO="$5"
    local FQDN="$6"
    local VTT_HOME="$7"
    local MAJOR_VER="$8"
    local BACKUP_REFRESH="$9"
    local VTTCTL_VERSION="${10}"

    local METADATA_FILE="${BACKUP_HOME}metadata.json"
    
    if [[ -z "${PROD_VER}" ]]; then
        log_failure_msg "Could not determine product version. Backup aborted."
        return 1
    fi

    log_daemon_msg "   - Creating backup for version ${PROD_VER}..."
    local DATESTAMP=$(date +"%Y%m%d")
    local BACKUP_FILE="foundry_userdata_${PROD_VER}-${DATESTAMP}.tar"
    
    docker run \
        --rm \
        -v foundryvtt_UserData:/source/ \
        -v "${BACKUP_HOME}":/backup \
        busybox \
        ash -c "tar -cvf /backup/${BACKUP_FILE} -C / /source " > /dev/null 2>&1

    log_daemon_msg "   - Setting permissions on backup file..."
    docker run \
        --rm \
        -v "${BACKUP_HOME}":/backup \
        busybox \
        ash -c "chown ${USER_ID}:${GROUP_ID} /backup/${BACKUP_FILE}"

    log_daemon_msg "   - ${BACKUP_FILE} backup file created."

    log_daemon_msg "   - Updating metadata.json..."
    if [[ -f "${METADATA_FILE}" ]]; then
        rm "${METADATA_FILE}"
    fi

    shopt -s nullglob
    echo "{" > "${METADATA_FILE}"
    local first_file=true
    for filename in "${BACKUP_HOME}"*.tar "${BACKUP_HOME}"*.tar.gz "${BACKUP_HOME}"*.tar.bz2; do
        if [[ -f "${filename}" ]]; then
            basefile=$(basename "${filename}")
            IFS="|" read -r version date <<< "$(parse_version "$basefile")"
            size=$(stat -c "%s" "${filename}")
            size_mb=$(awk -v size="${size}" 'BEGIN{printf "%.0f", (size / 1024 / 1024) + 0.5}')
            if [[ "${first_file}" == false ]]; then
                echo "," >> "${METADATA_FILE}"
            else
                first_file=false
            fi
            echo "\"${date}\": { \"version\":\"${version}\", \"filename\":\"${WEB_PROTO}://${FQDN}/backups/${basefile}\", \"size\":\"${size_mb} MB\" }" >> "${METADATA_FILE}"
        fi
    done
    echo "}" >> "${METADATA_FILE}"
    log_daemon_msg "   - metadata.json updated."

    log_daemon_msg "   - Generating backup listing page..."
    local BACKUP_INDEX="${VTT_HOME}/backups/FoundryVTT/index.html"
    generateBackupListing "${BACKUP_INDEX}" "${MAJOR_VER}" "${VTT_HOME}" "${BACKUP_HOME}" "${BACKUP_REFRESH}" "${VTTCTL_VERSION}"
    log_daemon_msg "   - Backup listing page updated."
    log_daemon_msg "   - Download it from ${WEB_PROTO}://${FQDN}/backups/"
}
