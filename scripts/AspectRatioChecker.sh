#!/usr/bin/env bash

# $1 = width
# $2 = height

#get aspect ratio multiplied by 1000 to check for decimal
value10="$((90 * $1/$2))"
dec=${value10: -1}

#check if aspect ratio is x:9
if [ "$dec" = "0" ]; then
    #get height in aspect ratio
    ratio="$((9 * $1/$2))"

    #check if aspect ratio is 16:9
    if [ "$ratio" = "16" ]; then
        echo "$HOME/Pictures/wallpapers/16-9"
        exit 0

    #check if aspect ratio is 21:9
    elif [ "$ratio" = "21" ]; then
        echo "$HOME/Pictures/wallpapers/21-9"
        exit 0

    #check if aspect ratio is 32:9
    elif [ "$ratio" = "32" ]; then
        echo "$HOME/Pictures/wallpapers/32-9"
        exit 0

    #check if aspect ratio is 4:3
    elif [ "$ratio" = "12" ]; then
        echo "$HOME/Pictures/wallpapers/4-3"
        exit 0
    fi

else
    value10="$((100 * $1/$2))"
    dec=${value10: -1}
    #check if aspect ratio is x:10
    if [ "$dec" = "0" ]; then
        #get height in aspect ratio
        ratio="$((10 * $1/$2))"

        #check if aspect ratio is 16:10
        if [ "$ratio" = "16" ]; then
            echo "$HOME/Pictures/wallpapers/16-10"
            exit 0
        
        #check if aspect ratio is 21:10
        elif [ "$ratio" = "21" ]; then
            echo "$HOME/Pictures/wallpapers/21-10"
            exit 0

        #check if aspect ratio is 32:10
        elif [ "$ratio" = "32" ]; then
            echo "$HOME/Pictures/wallpapers/32-10"
            exit 0

        #check if aspect ratio is 3:2
        elif [ "$ratio" = "15" ]; then
            echo "$HOME/Pictures/wallpapers/3-2"
            exit 0        
        fi
    fi    
fi

#----------vertical displays----------

value10="$((90 * $2/$1))"
dec=${value10: -1}

#check if aspect ratio is 9:x
if [ "$dec" = "0" ]; then
    #get width in aspect ratio
    ratio="$((9 * $2/$1))"

    #check if aspect ratio is 9:16
    if [ "$ratio" = "16" ]; then
        echo "$HOME/Pictures/wallpapers/9-16"
        exit 0

    #check if aspect ratio is 9:21
    elif [ "$ratio" = "21" ]; then
            echo "$HOME/Pictures/wallpapers/9-21"
            exit 0

    #check if aspect ratio is 9:32
    elif [ "$ratio" = "32" ]; then
        echo "$HOME/Pictures/wallpapers/9-32"
        exit 0

    #check if aspect ratio is 3:4
    elif [ "$ratio" = "12" ]; then
        echo "$HOME/Pictures/wallpapers/3-4"
        exit 0    
    fi

else
    value10="$((100 * $2/$1))"
    dec=${value10: -1}
    #check if aspect ratio is x:10
    if [ "$dec" = "0" ]; then
        #get width in aspect ratio
        ratio="$((10 * $2/$1))"

        #check if aspect ratio is 10:16
        if [ "$ratio" = "16" ]; then
            echo "$HOME/Pictures/wallpapers/10-16"
            exit 0

        #check if aspect ratio is 10:21
        elif [ "$ratio" = "21" ]; then
            echo "$HOME/Pictures/wallpapers/10-21"  
            exit 0

        #check if aspect ratio is 10:32
        elif [ "$ratio" = "32" ]; then
            echo "$HOME/Pictures/wallpapers/10-32"
            exit 0

        #check if aspect ratio is 2:3
        elif [ "$ratio" = "15" ]; then
            echo "$HOME/Pictures/wallpapers/2-3"
            exit 0
        fi
    fi    
fi

#default folder if aspect ratio doesn't match any known ratios
echo "$HOME/Pictures/wallpapers/16-9"
exit 0