#!/usr/bin/env bash

CopyNsfw=false

if ! [ -d $HOME/Pictures/wallpapers ]; then
    echo "wallpapers directory not found, exiting..."
    exit 1
fi

read -p "Do you want to copy only the sfw wallpapers? [y/N]" -n 1 -r
echo ""
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    CopyNsfw=true
else
    CopyNsfw=false
fi
#copy wallpapers x:9
if [ -d ./16-9 ]; then
    cp -r ./16-9 $HOME/Pictures/wallpapers/
fi

if [ -d ./21-9 ]; then
    cp -r ./21-9 $HOME/Pictures/wallpapers/
fi

if [ -d ./32-9 ]; then
    cp -r ./32-9 $HOME/Pictures/wallpapers/
fi

if [ -d ./4-3 ]; then
    cp -r ./4-3 $HOME/Pictures/wallpapers/
fi

#copy wallpapers x:10
if [ -d ./16-10 ]; then
    cp -r ./16-10 $HOME/Pictures/wallpapers/
fi

if [ -d ./21-10 ]; then
    cp -r ./21-10 $HOME/Pictures/wallpapers/
fi

if [ -d ./32-10 ]; then
    cp -r ./32-10 $HOME/Pictures/wallpapers/
fi

if [ -d ./3-2 ]; then
    cp -r ./3-2 $HOME/Pictures/wallpapers/
fi

#copy wallpapers 9:x
if [ -d ./9-16 ]; then
    cp -r ./9-16 $HOME/Pictures/wallpapers/
fi

if [ -d ./9-21 ]; then
    cp -r ./9-21 $HOME/Pictures/wallpapers/
fi

if [ -d ./9-32 ]; then
    cp -r ./9-32 $HOME/Pictures/wallpapers/
fi

if [ -d ./3-4 ]; then
    cp -r ./3-4 $HOME/Pictures/wallpapers/
fi

#copy wallpapers 10:x
if [ -d ./10-16 ]; then
    cp -r ./10-16 $HOME/Pictures/wallpapers/
fi

if [ -d ./10-21 ]; then
    cp -r ./10-21 $HOME/Pictures/wallpapers/
fi

if [ -d ./10-32 ]; then
    cp -r ./10-32 $HOME/Pictures/wallpapers/
fi

if [ -d ./2-3 ]; then
    cp -r ./2-3 $HOME/Pictures/wallpapers/
fi

#copy nsfw variants
if [ "$CopyNsfw" = true ]; then
    #copy wallpapers x:9
    if [ -d ./nsfw/16-9 ]; then
        cp -r ./nsfw/16-9 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./21-9 ]; then
        cp -r ./nsfw/21-9 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./32-9 ]; then
        cp -r ./nsfw/32-9 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./4-3 ]; then
        cp -r ./nsfw/4-3 $HOME/Pictures/wallpapers/
    fi

    #copy wallpapers x:10
    if [ -d ./16-10 ]; then
        cp -r ./nsfw/16-10 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./21-10 ]; then
        cp -r ./nsfw/21-10 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./32-10 ]; then
        cp -r ./nsfw/32-10 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./3-2 ]; then
        cp -r ./nsfw/3-2 $HOME/Pictures/wallpapers/
    fi

    #copy wallpapers 9:x
    if [ -d ./9-16 ]; then
        cp -r ./nsfw/9-16 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./9-21 ]; then
        cp -r ./nsfw/9-21 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./9-32 ]; then
        cp -r ./nsfw/9-32 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./3-4 ]; then
        cp -r ./nsfw/3-4 $HOME/Pictures/wallpapers/
    fi

    #copy wallpapers 10:x
    if [ -d ./10-16 ]; then
        cp -r ./nsfw/10-16 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./10-21 ]; then
        cp -r ./nsfw/10-21 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./10-32 ]; then
        cp -r ./nsfw/10-32 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./2-3 ]; then
        cp -r ./nsfw/2-3 $HOME/Pictures/wallpapers/
    fi
fi

