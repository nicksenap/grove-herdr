#!/bin/sh
set -eu

path=${1:-}
name=${2:-}

[ -n "$path" ] || {
  printf 'usage: pre-delete.sh <workspace-path> [workspace-name]\n' >&2
  exit 2
}

hook_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
"$hook_dir/herdr-workspace.sh" close "$path" "$name" || true
