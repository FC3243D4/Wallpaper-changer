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
    # 👤 CHARACTER MODE

    find "$dir" -type f -name "*.png" | awk -F/ -v mode="$mode" '
    {
        file = $NF
        sub(/\.png$/, "", file)

        is_nsfw = (file ~ /^nsfw-/)

        sub(/^nsfw-/, "", file)

        if (!match(file, /-([0-9]+)$/, arr)) next
        n = arr[1] + 0

        name = substr(file, 1, RSTART-1)

        # allow 1–2 parts (handles chi-chi)
        split(name, parts, "-")
        if (length(parts) > 2) next

        char = name

        if (is_nsfw) {
            if (n > max_nsfw[char])
                max_nsfw[char] = n
        } else {
            if (n > max_sfw[char])
                max_sfw[char] = n
        }
    }
    END {
        for (c in max_sfw) {
            sfw = max_sfw[c] + 0
            nsfw = max_nsfw[c] + 0

            if (mode == "sfw")
                print sfw, c
            else if (mode == "nsfw")
                print nsfw, c
            else
                print (sfw + nsfw), c
        }

        # include characters that exist only in nsfw
        for (c in max_nsfw) {
            if (!(c in max_sfw)) {
                nsfw = max_nsfw[c]

                if (mode == "nsfw")
                    print nsfw, c
                else if (mode == "all")
                    print nsfw, c
            }
        }
    }' | sort -nr
fi
