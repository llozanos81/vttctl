#!/bin/sh

# Function to get the size of a directory
get_directory_size() {
  local dir=$1
  local size=$(busybox du -skh "$dir" | busybox awk '{print $1}')
  echo "$size"
}

# Recursive function to process directories and their sizes
process_directory() {
  local dir=$1
  local size=$(get_directory_size "$dir")
  echo "$size $dir"

  for sub_dir in "$dir"/*; do
    if [ -d "$sub_dir" ]; then
      process_directory "$sub_dir"
    fi
  done
}

# Check if the argument for the number of top directories is provided
if [ -n "$1" ]; then
  TOP_COUNT="$1"
else
  TOP_COUNT=10  # Default to top 10 directories if no argument is provided
fi

# Check if the root directory argument is provided
if [ -n "$2" ]; then
  ROOT_DIR="$2"
else
  ROOT_DIR="."  # Default to the current directory if no root directory argument is provided
fi

# Start processing from the specified root directory
process_directory "$ROOT_DIR"

# Sort and get the top N lines based on the provided argument
echo "--- Top $TOP_COUNT Directories ---"
process_directory "$ROOT_DIR" | busybox sort -hr | busybox head -n "$TOP_COUNT"
