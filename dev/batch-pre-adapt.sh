#!/usr/bin/env bash

DIR="$1"

pwd

for dir in $DIR*; do
    if test -d "$dir"; then
        echo "Processing directory: $dir"
        ./dev/pre-adapt.sh "$dir"
    fi
done