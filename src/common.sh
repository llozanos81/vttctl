# Common helper functions for vttctl

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