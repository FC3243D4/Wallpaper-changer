#!/usr/bin/env bash

mkdir -p ./temporary

cp -r ./sfw/16-9/* ./temporary/
cp -r ./nsfw/16-9/* ./temporary/

./dev/wallpaper_stats.sh ./temporary --spreadsheet

sed '/| RANK |/,$d' README.md > README.md.tmp
./dev/table-converter.sh stats.csv >> README.md.tmp
mv README.md.tmp README.md

rm -rf ./temporary