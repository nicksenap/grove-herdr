#!/bin/sh
set -eu

path=${1:-}
name=${2:-}

[ -n "$path" ] || {
  printf 'usage: post-create.sh <workspace-path> [workspace-name]\n' >&2
  exit 2
}

hook_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
helper="$hook_dir/herdr-workspace.sh"

# Env vars that mean a coding agent, not a human, ran `gw create`.
# Add one only after confirming it in that agent's real environment.
AGENT_MARKERS="PI_CODING_AGENT CLAUDECODE"

agent_marker() {
  for var in $AGENT_MARKERS; do
    eval "value=\${$var:-}"
    if [ -n "$value" ]; then
      printf '%s\n' "$var"
      return 0
    fi
  done
  return 1
}

skip() {
  printf 'herdr-workspace: skipped open (%s); open with: %s open %s %s (or set GROVE_HERDR_OPEN=1)\n' \
    "$1" "$helper" "$path" "$name"
  exit 0
}

case "${GROVE_HERDR_OPEN:-}" in
  1) ;;
  0) skip "GROVE_HERDR_OPEN=0" ;;
  *)
    if [ -n "${GROVE_HERDR_OPEN:-}" ]; then
      printf 'herdr-workspace: ignoring GROVE_HERDR_OPEN=%s (expected 1 or 0); auto-detecting\n' \
        "$GROVE_HERDR_OPEN" >&2
    fi
    if marker=$(agent_marker); then
      skip "agent context: $marker"
    fi
    ;;
esac

"$helper" open "$path" "$name" || true
