#!/usr/bin/env bash
# csv_to_markdown.sh — Convert a CSV file to a Markdown table.
#
# Usage:
#   ./csv_to_markdown.sh input.csv
#   ./csv_to_markdown.sh input.csv -o output.md
#   cat data.csv | ./csv_to_markdown.sh -

set -euo pipefail

usage() {
  echo "Usage: $0 [input.csv|-] [-o output.md]"
  echo ""
  echo "  input.csv   Path to CSV file (use '-' to read from stdin)"
  echo "  -o FILE     Write output to FILE instead of stdout"
  echo "  -h          Show this help message"
  exit 1
}

# --- Argument parsing ---
INPUT=""
OUTPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) OUTPUT="$2"; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "Unknown option: $1"; usage ;;
    *)  INPUT="$1"; shift ;;
  esac
done

if [[ -z "$INPUT" ]]; then
  usage
fi

# --- Read CSV into a temp file (handle stdin) ---
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

if [[ "$INPUT" == "-" ]]; then
  cat > "$TMPFILE"
else
  if [[ ! -f "$INPUT" ]]; then
    echo "Error: file not found: $INPUT" >&2
    exit 1
  fi
  cp "$INPUT" "$TMPFILE"
fi

# --- Parse CSV and build markdown ---
generate_markdown() {
  local file="$1"
  local -a rows=()

  # Read all rows into an array
  while IFS= read -r line; do
    rows+=("$line")
  done < "$file"

  if [[ ${#rows[@]} -eq 0 ]]; then
    echo "Error: CSV file is empty" >&2
    exit 1
  fi

  # Parse a CSV row into fields (handles quoted fields with commas)
  parse_row() {
    local row="$1"
    local -a fields=()
    local field=""
    local in_quotes=false
    local char

    for (( i=0; i<${#row}; i++ )); do
      char="${row:$i:1}"
      if [[ "$in_quotes" == true ]]; then
        if [[ "$char" == '"' ]]; then
          # Check for escaped quote ("")
          local next="${row:$((i+1)):1}"
          if [[ "$next" == '"' ]]; then
            field+='"'
            ((i++))
          else
            in_quotes=false
          fi
        else
          field+="$char"
        fi
      else
        if [[ "$char" == '"' ]]; then
          in_quotes=true
        elif [[ "$char" == ',' ]]; then
          fields+=("$field")
          field=""
        else
          field+="$char"
        fi
      fi
    done
    fields+=("$field")

    # Print fields separated by a null byte so caller can read them
    printf '%s\0' "${fields[@]}"
  }

  # Parse all rows into a 2D structure
  local -a all_fields=()
  local -a row_lengths=()
  local num_cols=0

  for row in "${rows[@]}"; do
    local -a fields=()
    while IFS= read -r -d '' field; do
      fields+=("$field")
    done < <(parse_row "$row")
    row_lengths+=("${#fields[@]}")
    all_fields+=("${fields[@]}")
    if [[ ${#fields[@]} -gt $num_cols ]]; then
      num_cols=${#fields[@]}
    fi
  done

  # Calculate column widths
  local -a col_widths=()
  for (( c=0; c<num_cols; c++ )); do
    col_widths[$c]=1
  done

  local field_idx=0
  for (( r=0; r<${#rows[@]}; r++ )); do
    local len="${row_lengths[$r]}"
    for (( c=0; c<len; c++ )); do
      local val="${all_fields[$field_idx]}"
      if [[ ${#val} -gt ${col_widths[$c]} ]]; then
        col_widths[$c]=${#val}
      fi
      ((field_idx++))
    done
  done

  # Helper: pad a string to a given width
  pad() {
    local str="$1"
    local width="$2"
    printf "%-${width}s" "$str"
  }

  # Build output
  local output=""
  field_idx=0

  for (( r=0; r<${#rows[@]}; r++ )); do
    local len="${row_lengths[$r]}"
    local line="| "
    for (( c=0; c<num_cols; c++ )); do
      local val=""
      if [[ $c -lt $len ]]; then
        val="${all_fields[$field_idx]}"
        ((field_idx++))
      fi
      line+="$(pad "$val" "${col_widths[$c]}") | "
    done
    output+="${line}"$'\n'

    # After the header row, insert the separator
    if [[ $r -eq 0 ]]; then
      local sep="| "
      for (( c=0; c<num_cols; c++ )); do
        sep+="$(printf '%0.s-' $(seq 1 "${col_widths[$c]}")) | "
      done
      output+="${sep}"$'\n'
    fi
  done

  echo -n "$output"
}

# --- Write output ---
MARKDOWN=$(generate_markdown "$TMPFILE")

if [[ -n "$OUTPUT" ]]; then
  echo "$MARKDOWN" > "$OUTPUT"
  echo "Markdown table written to: $OUTPUT"
else
  echo "$MARKDOWN"
fi