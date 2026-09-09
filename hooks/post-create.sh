#!/bin/sh
set -eu

path=${1:-}
name=${2:-}

[ -n "$path" ] || {
  printf 'usage: post-create.sh <workspace-path> [workspace-name]\n' >&2
  exit 2
}

hook_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
"$hook_dir/herdr-workspace.sh" open "$path" "$name" || true
