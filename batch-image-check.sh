#!/usr/bin/env bash

flag=$1
shift
for folder in "$@"; do
    ./check_image.sh "$flag" "$folder"
    echo ""
    echo "Finished checking $folder"
    echo "-----------------------------"
done