#!/usr/bin/env bash

mode="all"
dir="."
serie_mode=0

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --nsfw) mode="nsfw" ;;
        --sfw)  mode="sfw" ;;
        --all)  mode="all" ;;
        --serie) serie_mode=1 ;;
        --help)
            echo "Usage: $0 [--nsfw | --sfw | --all] [--serie] [directory]"
            exit 0
            ;;
        *)
            dir="$arg"
            ;;
    esac
done

if [ "$serie_mode" -eq 1 ]; then
    # 📁 SERIES MODE (real file count)

    if [ "$mode" = "nsfw" ]; then
        find "$dir" -type f -name "*nsfw*.png"
    elif [ "$mode" = "sfw" ]; then
        find "$dir" -type f -name "*.png" ! -name "*nsfw*"
    else
        find "$dir" -type f -name "*.png"
    fi |
    awk -F/ '
    {
        # parent directory = series
        serie = $(NF-1)
        count[serie]++
    }
    END {
        for (s in count)
            print count[s], s
    }' | sort -nr

else
    # 👤 CHARACTER MODE (max index method)

    find "$dir" -type f -name "*.png" | awk -F/ -v mode="$mode" '
    {
        file = $NF
        sub(/\.png$/, "", file)

        is_nsfw = (file ~ /^nsfw-/)

        if (mode == "nsfw" && !is_nsfw) next
        if (mode == "sfw" && is_nsfw) next

        sub(/^nsfw-/, "", file)

        if (!match(file, /-([0-9]+)$/, arr)) next
        n = arr[1] + 0

        name = substr(file, 1, RSTART-1)

        split(name, parts, "-")
        if (length(parts) > 2) next

        if (n > max[name])
            max[name] = n
    }
    END {
        for (c in max)
            print max[c], c
    }' | sort -nr
fi
