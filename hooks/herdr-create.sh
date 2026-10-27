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

original_stty=$(stty -g)
restore_terminal() {
  stty "$original_stty" 2>/dev/null || true
}
trap restore_terminal EXIT
trap 'exit 130' HUP INT TERM

raw_mode() {
  stty -echo -icanon min 1 time 0
}

# Reads a workspace name into $name. Returns 1 on Escape.
prompt_name() {
  printf '\033[2J\033[H\n\n'
  printf '%*s%s\n' "$pad" "" "create grove workspace"
  printf '%*s%s' "$pad" "" "name: "

  name=""
  raw_mode
  while IFS= read -r -n 1 key; do
    case "$key" in
      $'\e')
        restore_terminal
        return 1
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

  name=$(printf '%s' "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
}

# After a failed create: Enter retries, Escape (or q) closes. Returns 1 to close.
ask_retry() {
  printf '\n%s\n' "Enter: try another name   Esc: close"
  raw_mode
  while IFS= read -r -n 1 key; do
    case "$key" in
      "")
        restore_terminal
        return 0
        ;;
      $'\e'|q)
        restore_terminal
        return 1
        ;;
    esac
  done
  restore_terminal
  return 1
}

while true; do
  prompt_name || exit 0
  [[ -n "$name" ]] || exit 0

  printf '\033[2J\033[H'
  status=0
  gw create "$name" || status=$?
  (( status == 0 )) && exit 0
  # 130: the user hit Ctrl-C in gw; treat it as a cancel, not a failure.
  (( status == 130 )) && exit 0

  printf '\n\033[31mgw create "%s" failed (exit %d)\033[0m\n' "$name" "$status"
  ask_retry || exit "$status"
done
