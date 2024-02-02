#!/usr/bin/env bash

DIR_STRUCTURE=(
    "backups/"
    ".vttctl_home/"
)

for dir in ${DIR_STRUCTURE[@]}; do
    mkdir -p $dir
done