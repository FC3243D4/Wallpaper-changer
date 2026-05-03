#!/usr/bin/env bash

mkdir -p ./temporary

cp -r ./sfw/16-9/* ./temporary/
cp -r ./nsfw/16-9/* ./temporary/

./dev/wallpaper_stats.sh ./temporary --spreadsheet

rm -rf ./temporary