#!/usr/bin/env bash

variations=$(dev/variations-checker.sh)
if [[ "$variations" == *"<"* ]] || [[ "$variations" == *">"* ]]; then
    echo "Variations found:"
    echo "$variations"
    exit 1
else
    echo "No variations found. All good!"
fi

echo "generating spreadsheet and adding to readme..."
dev/spreadsheet-generator.sh

echo "All checks passed successfully! Copying to final directory..."
dev/wallpaper-updater.sh
