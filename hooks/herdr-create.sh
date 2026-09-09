#!/usr/bin/env bash
set -euo pipefail

cols=${COLUMNS:-}
if [[ -z "$cols" ]]; then
  size=$(stty size 2>/dev/null || true)
  cols=${size##* }
fi
cols=${cols:-72}

pad=2
if (( cols > 40 )); then
  pad=$(( (cols - 36) / 2 ))
fi

printf '\033[2J\033[H\n\n'
printf '%*s%s\n' "$pad" "" "create grove workspace"
printf '%*s%s' "$pad" "" "name: "

name=""
original_stty=$(stty -g)
restore_terminal() {
  stty "$original_stty" 2>/dev/null || true
}
trap restore_terminal EXIT
trap 'exit 130' HUP INT TERM
stty -echo -icanon min 1 time 0

while IFS= read -r -n 1 key; do
  case "$key" in
    $'\e')
      exit 0
      ;;
    "")
      break
      ;;
    $'\177'|$'\b')
      if [[ -n "$name" ]]; then
        name=${name%?}
        printf '\b \b'
      fi
      ;;
    [[:print:]])
      name+=$key
      printf '%s' "$key"
      ;;
  esac
done

restore_terminal
trap - EXIT HUP INT TERM

name=$(printf '%s' "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
[[ -n "$name" ]] || exit 0

printf '\033[2J\033[H'
exec gw create "$name"
