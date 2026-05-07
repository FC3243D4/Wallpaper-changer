#!/usr/bin/env bash

IGNORED=("upscale" "check")

process_dir() {
    local dir="$1"
    local has_subdirs=false

    for subdir in "$dir"/*/; do
        [ -d "$subdir" ] || continue
        dirname=$(basename "$subdir")
        [[ " ${IGNORED[*]} " == *" $dirname "* ]] && continue
        has_subdirs=true
        break
    done

    if [ "$has_subdirs" = true ]; then
        for subdir in "$dir"/*/; do
            [ -d "$subdir" ] || continue
            dirname=$(basename "$subdir")
            [[ " ${IGNORED[*]} " == *" $dirname "* ]] && continue
            echo "Processing subdirectory: $subdir"
            process_dir "$subdir"
        done
        echo "processed directory: $dir"
        ./dev/pre-adapt.sh "$dir"
    else
        echo "Processing directory: $dir"
        ./dev/pre-adapt.sh "$dir"
    fi
}

DIR="$1"
pwd

for dir in "$DIR"*/; do
    [ -d "$dir" ] || continue
    dirname=$(basename "$dir")
    [[ " ${IGNORED[*]} " == *" $dirname "* ]] && continue
    process_dir "$dir"
done