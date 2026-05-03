#!/usr/bin/env bash

echo "Checking for variation existance in sfw folder"

listsSfw=()

for folder in sfw/*; do
    name="sfw-"
    realpath=$(realpath "$folder")
    if [ -d "$folder" ]; then
        cd "$realpath"
        name=$name$(basename "$folder")
        find . -type f | sort > /tmp/"$name".txt
        cd ../..
        listsSfw+=("/tmp/$name.txt")
    fi
done


for list in "${listsSfw[@]}"; do
    if [ "$list" != "/tmp/sfw-16-9.txt" ]; then
        diff -3 "$list" "/tmp/sfw-16-9.txt" > /tmp/diff.txt
        if [ -s /tmp/diff.txt ]; then
            echo "Variations found between /tmp/sfw-16-9.txt and $list:"
            cat /tmp/diff.txt
        else
            echo "No variations found between /tmp/sfw-16-9.txt and $list."
        fi
    fi
done

echo ""
echo "Checking for variation existance in nsfw folder"

listsNsfw=()

for folder in nsfw/*; do
    name="nsfw-"
    realpath=$(realpath "$folder")
    if [ -d "$folder" ]; then
        cd "$realpath"
        name=$name$(basename "$folder")
        find . -type f | sort > /tmp/"$name".txt
        cd ../..
        listsNsfw+=("/tmp/$name.txt")
    fi
done


for list in "${listsNsfw[@]}"; do
    if [ "$list" != "/tmp/nsfw-16-9.txt" ]; then
        diff -3 "$list" "/tmp/nsfw-16-9.txt" > /tmp/diff.txt
        if [ -s /tmp/diff.txt ]; then
            echo "Variations found between /tmp/nsfw-16-9.txt and $list:"
            cat /tmp/diff.txt
        else
            echo "No variations found between /tmp/nsfw-16-9.txt and $list."
        fi
    fi
done

for list in "${listsSfw[@]}" "${listsNsfw[@]}"; do
    rm "$list"
done