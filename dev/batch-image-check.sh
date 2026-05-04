#!/usr/bin/env bash

flag=$1
shift
folder=$1
shift
for folders in "$@"; do
    check=$folder$folders
    echo "Checking $check..."
    result=$(./dev/check_image.sh "$flag" "$check")
    if [[ $result == *"|"* ]]; then
        echo "$result"
        break
    else
        echo ""
        echo "no issues found in $check"
    fi
    echo "-----------------------------"
done