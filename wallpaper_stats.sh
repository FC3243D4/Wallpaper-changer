#!/usr/bin/env bash

mode="all"
dir="."
individual=0
top_n=0
show_percentage=0
details=0
details_group=0
spreadsheet=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --nsfw) mode="nsfw" ;;
        --sfw)  mode="sfw" ;;
        --all)  mode="all" ;;
        --individual) individual=1 ;;
        --percentage) show_percentage=1 ;;
        --details) details=1 ;;
        --details-group) details_group=1 ;;
        --spreadsheet) spreadsheet=1 ;;
        --top)
            shift
            top_n="$1"
            ;;
        --help)
            echo "Usage: $0 [--nsfw|--sfw|--all] [--individual] [--details|--details-group] [--percentage] [--top N] [--spreadsheet] [directory]"
            exit 0
            ;;
        *)
            dir="$1"
            ;;
    esac
    shift
done

# mutually exclusive flags
if [[ "$details" -eq 1 && "$details_group" -eq 1 ]]; then
    echo "Error: --details and --details-group are mutually exclusive"
    exit 1
fi

run_pipeline() {
find "$dir" -type f -name "*.png" | awk -F/ -v mode="$mode" -v individual="$individual" '

function camel_to_words(str,    _out, _len, _i, _c, _prev, _nxt) {
    _out = ""
    _len = length(str)
    for (_i = 1; _i <= _len; _i++) {
        _c    = substr(str, _i, 1)
        _prev = (_i > 1)    ? substr(str, _i-1, 1) : ""
        _nxt  = (_i < _len) ? substr(str, _i+1, 1) : ""

        if (_i > 1 && _c ~ /[A-Z]/ && (_prev ~ /[a-z0-9]/ || _nxt ~ /[a-z]/)) {
            _out = _out "-" tolower(_c)
        } else {
            _out = _out tolower(_c)
        }
    }
    return _out
}

{
    file = $NF
    sub(/\.png$/, "", file)

    if (file ~ /-group-/) next

    serie = $(NF-1)

    is_nsfw = (file ~ /^nsfw-/)

    if (mode == "nsfw" && !is_nsfw) next
    if (mode == "sfw" && is_nsfw) next

    sub(/^nsfw-/, "", file)

    # mawk-compatible: strip trailing -NUMBER to get n and names_part
    tmp = file
    gsub(/[^-]*$/, "", tmp)          # e.g. "bulma-7-" -> keep prefix with trailing dash
    n_str = substr(file, length(tmp)+1)
    n = n_str + 0
    if (n == 0) next                 # no trailing number, skip

    names_part = substr(file, 1, length(tmp)-1)   # drop trailing dash
    nchars = split(names_part, chars, "-")

    if (individual && nchars > 1) next

    is_group = (nchars > 1)

    for (i = 1; i <= nchars; i++) {
        char = chars[i]
        pretty = camel_to_words(char)
        key = serie "/" pretty

        if (is_group) {
            if (is_nsfw)
                group_nsfw[key]++
            else
                group_sfw[key]++
        } else {
            if (is_nsfw) {
                if (n > max_nsfw[key])
                    max_nsfw[key] = n
            } else {
                if (n > max_sfw[key])
                    max_sfw[key] = n
            }
        }
    }
}

END {
    # Collect every key seen across all four maps
    for (k in max_sfw)    all_keys[k] = 1
    for (k in max_nsfw)   all_keys[k] = 1
    for (k in group_sfw)  all_keys[k] = 1
    for (k in group_nsfw) all_keys[k] = 1

    for (k in all_keys) {
        sfw_i  = (k in max_sfw)    ? max_sfw[k]    : 0
        nsfw_i = (k in max_nsfw)   ? max_nsfw[k]   : 0
        sfw_g  = (k in group_sfw)  ? group_sfw[k]  : 0
        nsfw_g = (k in group_nsfw) ? group_nsfw[k] : 0

        print (sfw_i + sfw_g + nsfw_i + nsfw_g) "|" sfw_i "|" nsfw_i "|" sfw_g "|" nsfw_g "|" k
    }
}
' | sort -t'|' -nr -k1,1 | awk -F'|' \
    -v top="$top_n" \
    -v showp="$show_percentage" \
    -v details="$details" \
    -v dgroup="$details_group" \
    -v spreadsheet="$spreadsheet" '

BEGIN {
    if (spreadsheet)
        print "RANK,TOTAL,SFW_INDIVIDUAL,SFW_GROUP,NSFW_INDIVIDUAL,NSFW_GROUP,NSFW_PERCENT,CHARACTER,SERIE"
    else if (dgroup && showp)
        printf "%-4s %-7s %-7s %-7s %-7s %-7s %-7s %-35s %-20s\n",
               "#","TOTAL","SFW-I","NSFW-I","SFW-G","NSFW-G","NSFW%","CHARACTER","SERIE"
    else if (dgroup)
        printf "%-4s %-7s %-7s %-7s %-7s %-7s %-35s %-20s\n",
               "#","TOTAL","SFW-I","NSFW-I","SFW-G","NSFW-G","CHARACTER","SERIE"
    else if (details && showp)
        printf "%-4s %-7s %-7s %-7s %-7s %-35s %-20s\n",
               "#","TOTAL","SFW","NSFW","NSFW%","CHARACTER","SERIE"
    else if (details)
        printf "%-4s %-7s %-7s %-7s %-35s %-20s\n",
               "#","TOTAL","SFW","NSFW","CHARACTER","SERIE"
    else if (showp)
        printf "%-4s %-7s %-7s %-35s %-20s\n",
               "#","TOTAL","NSFW%","CHARACTER","SERIE"
    else
        printf "%-4s %-7s %-35s %-20s\n",
               "#","TOTAL","CHARACTER","SERIE"
}

{
    total  = $1
    sfw_i  = $2
    nsfw_i = $3
    sfw_g  = $4
    nsfw_g = $5
    name   = $6

    split(name, parts, "/")
    serie = parts[1]
    character = parts[2]

    sfw = sfw_i + sfw_g
    nsfw = nsfw_i + nsfw_g
    percent = (total > 0) ? (nsfw / total * 100) : 0

    if (spreadsheet) {
        printf "%d,%d,%d,%d,%d,%d,%.1f,%s,%s\n",
               NR,total,sfw_i,sfw_g,nsfw_i,nsfw_g,percent,character,serie
    }
    else if (dgroup && showp)
        printf "%-4d %-7d %-7d %-7d %-7d %-7d %6.1f%% %-35s %-20s\n",
               NR,total,sfw_i,nsfw_i,sfw_g,nsfw_g,percent,character,serie
    else if (dgroup)
        printf "%-4d %-7d %-7d %-7d %-7d %-7d %-35s %-20s\n",
               NR,total,sfw_i,nsfw_i,sfw_g,nsfw_g,character,serie
    else if (details && showp)
        printf "%-4d %-7d %-7d %-7d %6.1f%% %-35s %-20s\n",
               NR,total,sfw,nsfw,percent,character,serie
    else if (details)
        printf "%-4d %-7d %-7d %-7d %-35s %-20s\n",
               NR,total,sfw,nsfw,character,serie
    else if (showp)
        printf "%-4d %-7d %6.1f%% %-35s %-20s\n",
               NR,total,percent,character,serie
    else
        printf "%-4d %-7d %-35s %-20s\n",
               NR,total,character,serie

    if (top > 0 && NR >= top)
        exit
}
'
}

# Run
if [[ "$spreadsheet" -eq 1 ]]; then
    run_pipeline > stats.csv
    echo "Saved to stats.csv"
else
    run_pipeline
fi