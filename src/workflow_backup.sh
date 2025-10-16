#!/bin/bash

# Source common functions
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# Use portable shell constructs for file listing and avoid parsing ls output
generateBackupListing() {
    local BACKUP_INDEX="${1}"
    local MAJOR_VER="${2}"
    local VTT_HOME="${3}"
    local BACKUP_DIR="${4}"
    local BACKUP_REFRESH="${5}"
    local VTTCTL_VERSION="${6}"
    local COMPUTE_MD5="${7:-true}"   # new: "true" or "false"

    # Fallback to current directory if VTT_HOME is empty
    if [[ -z "${VTT_HOME}" ]]; then
        VTT_HOME="$(pwd)"
    fi

    # If BACKUP_INDEX is empty, set default path
    if [[ -z "${BACKUP_INDEX}" ]]; then
        BACKUP_INDEX="${VTT_HOME}/backups/FoundryVTT/index.html"
        log_daemon_msg "No BACKUP_INDEX provided, using default: ${BACKUP_INDEX}"
    fi

    # Template is now fixed: templates/backup_index.j2
    # No need to choose based on MAJOR_VER

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
        md5=""
        if [[ "${COMPUTE_MD5}" == "true" ]]; then
            md5=$(md5sum "$file" 2>/dev/null | awk '{print $1}')
        fi
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

    # Use Python template renderer instead of awk
    python3 "${VTT_HOME}/python/template_renderer.py" \
        --template "${VTT_HOME}/templates/backup_index.j2" \
        --output "${BACKUP_INDEX}" \
        --var backup_refresh="${BACKUP_REFRESH}" \
        --var backup_file_table="${BACKUP_FILE_TABLE}" \
        --var vttctl_version="${VTTCTL_VERSION}" \
        --var major_version="${MAJOR_VER}" || {
        log_failure_msg "Failed to write backup listing to ${BACKUP_INDEX}"
        return 1
    }

    # Ensure the index.html is readable by the web server
    chmod 644 "${BACKUP_INDEX}" || log_warning_msg "Failed to set permissions on ${BACKUP_INDEX}"
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

    # Ensure backups are run inside a persistent session (tmux or screen).
    # Defensive check in case create_backup is called directly.
    if [[ -z "${STY:-}" && -z "${TMUX:-}" ]]; then
        log_failure_msg "Backups must be run inside tmux or screen. Aborting."
        return 1
    fi

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

    # Delegate metadata rebuild + index generation to a dedicated function
    rebuild_metadata "${BACKUP_HOME}" "${WEB_PROTO}" "${FQDN}" "${VTT_HOME}" "${MAJOR_VER}" "${BACKUP_REFRESH}" "${VTTCTL_VERSION}"

    log_daemon_msg "   - Backup listing page updated."
    log_daemon_msg "   - Download it from ${WEB_PROTO}://${FQDN}/backups/"
}

# New function: rebuild metadata.json and regenerate index.html
rebuild_metadata() {
    local BACKUP_HOME="${1:-}"
    local WEB_PROTO="${2:-http}"
    local FQDN="${3:-localhost}"
    local VTT_HOME="${4:-$(pwd)}"
    local MAJOR_VER="${5:-13}"
    local BACKUP_REFRESH="${6:-300000}"
    local VTTCTL_VERSION="${7:-}"
    local COMPUTE_MD5="${8:-false}"   # new, default false for deletions

    local METADATA_FILE="${BACKUP_HOME}metadata.json"
    local BACKUP_INDEX="${VTT_HOME}/backups/FoundryVTT/index.html"

    # Safety checks
    if [[ -z "${BACKUP_HOME}" ]]; then
        log_failure_msg "rebuild_metadata: BACKUP_HOME is empty"
        return 1
    fi

    shopt -s nullglob
    echo "{" > "${METADATA_FILE}"
    local first_file=true

    for filename in "${BACKUP_HOME}"*.tar "${BACKUP_HOME}"*.tar.gz "${BACKUP_HOME}"*.tar.bz2; do
        if [[ -f "${filename}" ]]; then
            basefile=$(basename "${filename}")
            IFS="|" read -r version date <<< "$(parse_version "$basefile")"
            size=$(stat -c "%s" "${filename}" 2>/dev/null || stat -f "%z" "${filename}")
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
    shopt -u nullglob

    # Regenerate HTML listing (uses generateBackupListing defined in same file)
    # Choose timeout according to whether we compute md5 (md5 may be slow)
    if [[ "${COMPUTE_MD5}" == "true" ]]; then
        timeout_seconds=120
    else
        timeout_seconds=10
    fi

    generateBackupListing "${BACKUP_INDEX}" "${MAJOR_VER}" "${VTT_HOME}" "${BACKUP_HOME}" "${BACKUP_REFRESH}" "${VTTCTL_VERSION}" "${COMPUTE_MD5}" &
    gb_pid=$!
    # wait up to timeout_seconds for background job to finish
    for i in $(seq 1 "${timeout_seconds}"); do
        if ! kill -0 "${gb_pid}" 2>/dev/null; then
            # finished
            break
        fi
        sleep 1
    done
    if kill -0 "${gb_pid}" 2>/dev/null; then
        # still running -> kill and report
        kill "${gb_pid}" 2>/dev/null || true
        wait "${gb_pid}" 2>/dev/null || true
        log_failure_msg "generateBackupListing did not finish within ${timeout_seconds}s and was terminated."
        return 1
    fi
}

cleanup_backups() {
    local BACKUP_HOME="$1"
    local WEB_PROTO="$2"
    local FQDN="$3"
    local VTT_HOME="$4"
    local MAJOR_VER="$5"
    local BACKUP_REFRESH="$6"
    local VTTCTL_VERSION="$7"

    local backups=()
    local selected=()

    # Collect .tar files, sorted by modification time (oldest first)
    while IFS= read -r -d '' file; do
        backups+=("$file")
    done < <(find "$BACKUP_HOME" -name "*.tar" -type f -print0 | xargs -0 ls -t | tac | tr '\n' '\0')

    if [[ ${#backups[@]} -eq 0 ]]; then
        log_daemon_msg "No backups found to clean up."
        return 0
    fi

    echo "Select backups to delete (use space to select, enter to confirm):"
    echo "Available backups (oldest first):"
    for i in "${!backups[@]}"; do
        basefile=$(basename "${backups[$i]}")
        size=$(du -h "${backups[$i]}" | awk '{print $1}')
        # Parse date from filename
        raw_date=$(echo "$basefile" | grep -oP '(?<=-)(2\d{7})(?=\.)')
        if [ -n "$raw_date" ]; then
            formatted_date=$(date -d "$raw_date" +'%Y-%m-%d' 2>/dev/null || echo "$raw_date")
        else
            formatted_date="unknown"
        fi
        echo "$((i+1))) $basefile ($size) - $formatted_date"
    done
    echo "0) Cancel"

    while true; do
        read -p "Enter numbers separated by spaces (or 0 to cancel): " -a choices
        selected=()
        invalid=false
        for choice in "${choices[@]}"; do
            if [[ $choice == 0 ]]; then
                echo "Cleanup canceled."
                return 0
            elif [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#backups[@]} )); then
                selected+=("${backups[$((choice-1))]}")
            else
                echo "Invalid choice: $choice"
                invalid=true
                break
            fi
        done
        if [[ $invalid == false ]]; then
            break
        fi
    done

    for file in "${selected[@]}"; do
        basefile=$(basename "$file")
        log_daemon_msg "Deleting: $basefile"
        rm -f -- "$file"
    done

    # Rebuild metadata and listing after deletion
    rebuild_metadata "${BACKUP_HOME}" "${WEB_PROTO}" "${FQDN}" "${VTT_HOME}" "${MAJOR_VER}" "${BACKUP_REFRESH}" "${VTTCTL_VERSION}" "false"
    log_daemon_msg "Metadata and backup listing updated."
}
