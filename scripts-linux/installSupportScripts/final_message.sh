#!/usr/bin/env bash
# final_message.sh
# Prints the post-install usage instructions.
# Meant to be SOURCED from install-Linux.sh; relies on $useXrandr,
# $copyScripts, $copyNsfw, and $wallpapersRepo being set by earlier modules.

echo "Installation complete!"

if [ "$useXrandr" = true ]; then
    if [ "$copyScripts" = true ]; then
        cat << EOF

Open the wallpaper menu anytime with:
$HOME/.config/WallpaperChanger/WallpaperMenuXrandr.sh

Or apply a random wallpaper directly:
$HOME/.config/WallpaperChanger/WallpaperApplicatorXrandr.sh random

EOF
        if [ "$copyNsfw" = true ]; then
            cat << EOF
Since you installed the nsfw wallpapers too, you can target either set specifically:
$HOME/.config/WallpaperChanger/WallpaperApplicatorXrandr.sh random sfw
$HOME/.config/WallpaperChanger/WallpaperApplicatorXrandr.sh random nsfw

The same goes for the automatic changer, which cycles wallpapers every 30 minutes (edit the script if you'd like a different interval):
$HOME/.config/WallpaperChanger/WallpaperRandomAutoXrandr.sh sfw
$HOME/.config/WallpaperChanger/WallpaperRandomAutoXrandr.sh nsfw
EOF
        else
            echo "To start the automatic wallpaper changer (cycles every 30 minutes — edit the script if you'd like a different interval), run:"
            echo "$HOME/.config/WallpaperChanger/WallpaperRandomAutoXrandr.sh"
        fi

        cat << EOF

Heads up: the first run will build a cache of your wallpapers' aspect ratios to speed things up. If you add or remove wallpapers later, delete $HOME/.cache/wallpaper_ratios.cache so the script picks up the changes.

Wallpapers are applied across all connected displays at the correct aspect ratio, and on supported OpenRGB devices the dominant color is applied automatically.
EOF
    fi
else
    if [ "$copyScripts" = true ]; then
        cat << EOF

Open the wallpaper menu anytime with:
$HOME/.config/WallpaperChanger/WallpaperMenu.sh

Start the automatic wallpaper changer (cycles every 30 minutes — edit the script if you'd like a different interval):
$HOME/.config/WallpaperChanger/WallpaperRandomAuto.sh

Or apply a random wallpaper directly:
$HOME/.config/WallpaperChanger/WallpaperApplication.sh random

EOF
        if [ "$copyNsfw" = true ]; then
            cat << EOF
Since you installed the nsfw wallpapers too, you can target either set specifically:
$HOME/.config/WallpaperChanger/WallpaperApplicator.sh random sfw
$HOME/.config/WallpaperChanger/WallpaperApplicator.sh random nsfw

The automatic changer supports the same filtering:
$HOME/.config/WallpaperChanger/WallpaperRandomAuto.sh sfw
$HOME/.config/WallpaperChanger/WallpaperRandomAuto.sh nsfw
EOF
        fi

        cat << EOF

Wallpapers are applied across all connected displays at the correct aspect ratio, and on supported OpenRGB devices the dominant color is applied automatically.

EOF
        if [ "$wallpapersRepo" = false ]; then
            cat << EOF
Note: you'll need to add your own wallpapers to $HOME/Pictures/wallpapers, sorted into folders named after their aspect ratio (16-9, 21-9, etc.) so the script can find them.

EOF
        fi

        cat << EOF
Heads up: the first run will build a cache of your wallpapers' aspect ratios to speed things up. If you add or remove wallpapers later, delete $HOME/.cache/wallpaper_ratios.cache so the script picks up the changes.

EOF
    fi
fi

cat << EOF
If the wallpaper menu feels slow to load, it's likely because it's processing a lot of high-resolution images. Try running generateWallpaperThumbnails.sh first to see if that helps — if it does, you can install a watcher that generates thumbnails automatically for any wallpaper you add to the 16-9 folder, by running:
./install-Linux.sh --thumbnails

To update your scripts or wallpapers from the repo in the future without running the full installation again, you can use:
./install-Linux.sh --update-scripts
./install-Linux.sh --update-wallpapers

Running into issues, or want to suggest something? Feel free to open an issue on the GitHub repository.
EOF