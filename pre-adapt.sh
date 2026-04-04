#!/usr/bin/env bash

DIR="$(dirname "$(realpath "$1")")"

# convert heic to png
for f in $DIR/*.heic
    if test -f $f
        magick "$f" -quality 95 (path change-extension .png $f)
    end
end
rm $DIR/*.heic

mkdir -p $DIR/upscale $DIR/check

for img in $DIR/*.jpg $DIR/*.png $DIR/*.jpeg $DIR/*.heic 
    if test -f $img
        # Move low-resolution images
        set height (identify -format "%h" $img)
        if test $height -lt 1800
            mv $img $DIR/upscale/
            continue
        end

        # Move files without "cleanup" in the name
        if not string match -q "*cleanup*" $img
            mv $img $DIR/check/
        end
    end
end