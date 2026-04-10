#!/usr/bin/env bash

DIR="$1"
cd "$DIR"

pwd

# convert heic to png
for f in *.heic; do
    if test -f "$f"; then
        magick "$f" -quality 95 "${f%.heic}.png"
        rm "$f"
    fi
done

for img in *.jpg *.png *.jpeg *.heic; do
    if test -f "$img"; then
        # Move low-resolution images
        height=$(identify -format "%h" "$img")
        if test "$height" -lt 1800; then
            if ! [ -d "upscale" ]; then
                mkdir -p upscale
            fi
            mv "$img" upscale/
            continue
        fi

        # Move files without "cleanup" in the name
        if ! [[ "$img" =~ cleanup ]]; then
            if ! [ -d "check" ]; then
                mkdir -p check
            fi
            mv "$img" check/
        fi
    fi
done