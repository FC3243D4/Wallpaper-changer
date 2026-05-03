#!/usr/bin/env bash

flag=$1
shift
for folder in "$@"; do
    ./dev/check_image.sh "$flag" "$folder"
    echo ""
    echo "Finished checking $folder"
    echo "-----------------------------"
done