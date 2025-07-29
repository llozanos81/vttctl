# Advanced Logging helper functions for vttctl
# Supports log levels, timestamps, color, and optional log file output.
#
# Error Handling Best Practices:
# - Use 'set -euo pipefail' at the top of your scripts for strict error handling.
# - Always check the exit status of critical commands and log errors using log_error.
# - Use 'trap' to perform cleanup on errors or interrupts.
#
# Example usage in your scripts:
#   set -euo pipefail
#   trap 'log_error "Script interrupted or failed"; cleanup_function' ERR INT TERM
#
#   some_critical_command || { log_error "Failed to run some_critical_command"; exit 1; }

# Log level constants
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3
LOG_LEVEL_FATAL=4

# Default log level (can be overridden by environment)
LOG_LEVEL=${LOG_LEVEL:-$LOG_LEVEL_INFO}
LOG_FILE=""

# Color codes (only if output is a terminal)
if [ -t 1 ]; then
    color_reset="\033[0m"
    color_debug="\033[36m"   # Cyan
    color_info="\033[32m"    # Green
    color_warn="\033[33m"    # Yellow
    color_error="\033[31m"   # Red
    color_fatal="\033[41;97m" # White on Red
else
    color_reset=""
    color_debug=""
    color_info=""
    color_warn=""
    color_error=""
    color_fatal=""
fi

# Set log file (optional)
function set_log_file() {
    LOG_FILE="$1"
}

# Internal: log level name
function _log_level_name() {
    case $1 in
        0) echo "DEBUG" ;;
        1) echo "INFO" ;;
        2) echo "WARN" ;;
        3) echo "ERROR" ;;
        4) echo "FATAL" ;;
        *) echo "LOG" ;;
    esac
}

# Internal: log color
function _log_color() {
    case $1 in
        0) echo "$color_debug" ;;
        1) echo "$color_info" ;;
        2) echo "$color_warn" ;;
        3) echo "$color_error" ;;
        4) echo "$color_fatal" ;;
        *) echo "$color_reset" ;;
    esac
}

# Internal: main log function
function _log() {
    local level=$1
    shift
    local msg="$*"
    if [ "$level" -lt "$LOG_LEVEL" ]; then
        return
    fi
    local level_name=$(_log_level_name $level)
    local color=$(_log_color $level)
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    # Only color the [LEVEL] part
    local formatted="[$timestamp] [${color}${level_name}${color_reset}] $msg"
    echo -e "$formatted"
    if [ -n "$LOG_FILE" ]; then
        echo "[$timestamp] [$level_name] $msg" >> "$LOG_FILE"
    fi
}

# Public log functions (now always include [LEVEL])
function log_debug() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local msg="[$timestamp] [DEBUG] ${color_debug}*${color_reset} $*"
    echo -en "$msg\r\n"
    LAST_LOG_MSG="$msg"
    LAST_LOG_LEVEL="DEBUG"
    if [ -n "$LOG_FILE" ]; then
        echo "[$timestamp] [DEBUG] $*" >> "$LOG_FILE"
    fi
}
function log_info() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local msg="[$timestamp] [INFO] ${color_info}*${color_reset} $*"
    echo -en "$msg\r\n"
    LAST_LOG_MSG="$msg"
    LAST_LOG_LEVEL="INFO"
    if [ -n "$LOG_FILE" ]; then
        echo "[$timestamp] [INFO] $*" >> "$LOG_FILE"
    fi
}
function log_warn() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local msg="[$timestamp] [WARN] ${color_warn}*${color_reset} $*"
    echo -en "$msg\r\n"
    LAST_LOG_MSG="$msg"
    LAST_LOG_LEVEL="WARN"
    if [ -n "$LOG_FILE" ]; then
        echo "[$timestamp] [WARN] $*" >> "$LOG_FILE"
    fi
}
function log_error() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local msg="[$timestamp] [ERROR] ${color_error}*${color_reset} $*"
    echo -en "$msg\r\n"
    LAST_LOG_MSG="$msg"
    LAST_LOG_LEVEL="ERROR"
    if [ -n "$LOG_FILE" ]; then
        echo "[$timestamp] [ERROR] $*" >> "$LOG_FILE"
    fi
}
function log_fatal() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local msg="[$timestamp] [FATAL] ${color_fatal}*${color_reset} $*"
    echo -en "$msg\r\n"
    LAST_LOG_MSG="$msg"
    LAST_LOG_LEVEL="FATAL"
    if [ -n "$LOG_FILE" ]; then
        echo "[$timestamp] [FATAL] $*" >> "$LOG_FILE"
    fi
}

# Legacy aliases for backward compatibility with old logging function names
log_begin_msg()   { log_info "$@"; }
log_daemon_msg()  { log_info "$@"; }
log_warning_msg() { log_warn "$@"; }
log_failure_msg() { log_error "$@"; }
log_end_msg() {
    # Accepts optional status code, default to $?
    local status=${1:-$?}
    local color_status
    local status_text

    if [ "$status" -eq 0 ]; then
        color_status="${color_info}"
        status_text="[${color_status}OK${color_reset}]"
    else
        color_status="${color_error}"
        status_text="[${color_status}fail${color_reset}]"
    fi

    # Move cursor up and clear line
    tput cuu1 2>/dev/null || true
    tput el   2>/dev/null || true

    # Print the last log message with the status at the end
    local msg="${LAST_LOG_MSG:-}"
    if [ -n "$msg" ]; then
        echo -e "${msg} ${status_text}"
        if [ -n "$LOG_FILE" ]; then
            # Remove color codes for log file
            local clean_msg=$(echo -e "$msg" | sed 's/\x1b\[[0-9;]*m//g')
            # Only the word OK/fail is appended, not colored, for log file
            if [ "$status" -eq 0 ]; then
                echo "${clean_msg} [OK]" >> "$LOG_FILE"
            else
                echo "${clean_msg} [fail]" >> "$LOG_FILE"
            fi
        fi
    else
        # Fallback if no previous message
        echo -e "${status_text}"
        if [ -n "$LOG_FILE" ]; then
            if [ "$status" -eq 0 ]; then
                echo "[OK]" >> "$LOG_FILE"
            else
                echo "[fail]" >> "$LOG_FILE"
            fi
        fi
    fi
}

# Usage examples:
#   log_info "Starting service"
#   log_warn "Low disk space"
#   log_error "Failed to start"
#   set_log_file "/tmp/vttctl.log"
#   LOG_LEVEL=0 ./vttctl.sh   # To enable debug logs
#   LOG_LEVEL=0 ./vttctl.sh   # To enable debug logs
