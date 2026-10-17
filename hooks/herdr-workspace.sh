#!/bin/sh
set -eu

usage() {
  printf 'usage: herdr-workspace.sh open [--no-focus] <workspace-path> [workspace-name]\n       herdr-workspace.sh close <workspace-path> [workspace-name]\n' >&2
  exit 2
}

[ "${1:-}" = "open" ] || [ "${1:-}" = "close" ] || usage
action=$1
shift

focus=1
if [ "$action" = "open" ] && [ "${1:-}" = "--no-focus" ]; then
  focus=0
  shift
fi

path=${1:-}
name=${2:-}

[ -n "$path" ] || usage

herdr_bin=${HERDR_BIN_PATH:-herdr}

if ! command -v "$herdr_bin" >/dev/null 2>&1; then
  printf 'herdr-workspace: herdr not found on PATH\n' >&2
  exit 0
fi

if ! "$herdr_bin" status >/dev/null 2>&1; then
  printf 'herdr-workspace: herdr server is not running; skipping\n' >&2
  exit 0
fi

realpath_path=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$path")
label=${name:-$(basename "$realpath_path")}
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/grove-herdr"
state_file="$state_dir/workspaces.json"

python3 - "$action" "$realpath_path" "$label" "$state_file" "$herdr_bin" "$focus" <<'PY'
import json
import os
import subprocess
import sys

action, path, label, state_file, herdr_bin, focus = sys.argv[1:]
focus = focus == "1"


def load_state():
    try:
        with open(state_file) as fh:
            data = json.load(fh)
        if isinstance(data, dict):
            return data
    except FileNotFoundError:
        return {}
    except Exception:
        return {}
    return {}


def save_state(data):
    os.makedirs(os.path.dirname(state_file), exist_ok=True)
    tmp = state_file + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    os.replace(tmp, state_file)


def herdr(*args):
    result = subprocess.run(
        [herdr_bin, *args],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        message = (result.stderr or result.stdout).strip()
        raise RuntimeError(message or f"herdr {' '.join(args)} failed")
    payload = json.loads(result.stdout)
    return payload.get("result", payload)


def snapshot_cwds():
    try:
        snapshot = herdr("api", "snapshot").get("snapshot", {})
    except Exception:
        return {}
    cwds = {}
    for agent in snapshot.get("agents", []):
        workspace_id = agent.get("workspace_id")
        cwd = agent.get("cwd") or agent.get("foreground_cwd")
        if workspace_id and cwd:
            cwds.setdefault(workspace_id, set()).add(os.path.realpath(cwd))
    return cwds


def find_workspace(workspaces, remembered_id=None, cwds_by_workspace=None):
    if remembered_id:
        for workspace in workspaces:
            if workspace.get("workspace_id") == remembered_id:
                return workspace
    cwds_by_workspace = cwds_by_workspace or {}
    for workspace in workspaces:
        workspace_id = workspace.get("workspace_id")
        if path in cwds_by_workspace.get(workspace_id, set()):
            return workspace
        worktree = workspace.get("worktree") or {}
        checkout = worktree.get("checkout_path")
        if checkout and os.path.realpath(checkout) == path:
            return workspace
    return None


try:
    listed = herdr("workspace", "list")
    workspaces = listed.get("workspaces", [])
    state = load_state()
    remembered_id = state.get(path)
    cwds_by_workspace = snapshot_cwds()

    if action == "open":
        existing = find_workspace(workspaces, remembered_id, cwds_by_workspace)
        if existing:
            if focus:
                herdr("workspace", "focus", existing["workspace_id"])
            state[path] = existing["workspace_id"]
            save_state(state)
            verb = "focused" if focus else "found"
            print(
                f"herdr-workspace: {verb} {existing['workspace_id']} ({existing.get('label', label)})"
            )
            raise SystemExit(0)

        created = herdr(
            "workspace",
            "create",
            "--cwd",
            path,
            "--label",
            label,
            "--focus" if focus else "--no-focus",
        )
        workspace = created.get("workspace") or created
        workspace_id = workspace.get("workspace_id")
        if workspace_id:
            state[path] = workspace_id
            save_state(state)
            print(f"herdr-workspace: opened {workspace_id} ({label}) at {path}")
        else:
            print("herdr-workspace: created a workspace but got no workspace_id", file=sys.stderr)
        raise SystemExit(0)

    existing = find_workspace(workspaces, remembered_id, cwds_by_workspace)
    if existing:
        herdr("workspace", "close", existing["workspace_id"])
        print(f"herdr-workspace: closed {existing['workspace_id']} ({existing.get('label', label)})")
    elif remembered_id:
        print(f"herdr-workspace: remembered {remembered_id} is already gone")
    else:
        print(f"herdr-workspace: no Herdr workspace found for {path}")

    if path in state:
        del state[path]
        save_state(state)
except Exception as exc:
    print(f"herdr-workspace: {exc}", file=sys.stderr)
    raise SystemExit(0)
PY
