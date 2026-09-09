#!/bin/sh
set -u

INSTALL_DIR=${GROVE_HERDR_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/grove-herdr}
HERDR_CONFIG=${HERDR_CONFIG_PATH:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr/config.toml}
GROVE_DIR=${GROVE_DIR:-$HOME/.grove}
GROVE_CONFIG=${GROVE_CONFIG:-$GROVE_DIR/config.toml}

abs_dir() {
  CDPATH= cd -- "$1" && pwd
}

discover_plugin_root() {
  if ! command -v herdr >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    return 0
  fi
  herdr plugin list --json 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
plugins = data.get("result", data).get("plugins", [])
for plugin in plugins:
    if plugin.get("plugin_id") == "grove.workspace":
        root = plugin.get("plugin_root") or ""
        if root:
            print(root)
        break
'
}

script_path=$0
case "$script_path" in
  /*) ;;
  *) script_path=$(pwd)/$script_path ;;
esac

here=""
if [ -f "$script_path" ]; then
  here=$(abs_dir "$(dirname -- "$script_path")")
fi

plugin_root=$(discover_plugin_root)
if [ -z "$plugin_root" ] && [ -n "$here" ] && [ -f "$here/herdr-plugin.toml" ]; then
  plugin_root=$here
elif [ -z "$plugin_root" ] && [ -f "$INSTALL_DIR/herdr-plugin.toml" ]; then
  plugin_root=$INSTALL_DIR
fi

configure=""
if [ -n "$here" ] && [ -f "$here/scripts/configure.py" ]; then
  configure="$here/scripts/configure.py"
elif [ -n "$plugin_root" ] && [ -f "$plugin_root/scripts/configure.py" ]; then
  configure="$plugin_root/scripts/configure.py"
fi

failed=0
warned=0

pass() {
  printf 'PASS  %s\n' "$1"
}

fail() {
  printf 'FAIL  %s\n' "$1"
  failed=$((failed + 1))
}

warn() {
  printf 'WARN  %s\n' "$1"
  warned=$((warned + 1))
}

on_path() {
  command -v "$1" >/dev/null 2>&1
}

printf 'Checking grove-herdr install\n\n'

if on_path herdr; then
  pass "herdr is on PATH ($(command -v herdr))"
else
  fail "herdr is not on PATH"
fi

if on_path gw; then
  pass "gw is on PATH ($(command -v gw))"
else
  fail "gw is not on PATH"
fi

if on_path python3; then
  pass "python3 is on PATH ($(command -v python3))"
else
  fail "python3 is not on PATH"
fi

if on_path git; then
  pass "git is on PATH ($(command -v git))"
else
  warn "git is not on PATH (only needed for curl | sh install/update)"
fi

if [ -n "$plugin_root" ] && [ -f "$plugin_root/herdr-plugin.toml" ]; then
  pass "plugin files are at $plugin_root"
else
  fail "plugin files not found (install.sh clones to $INSTALL_DIR)"
fi

if [ -n "$plugin_root" ]; then
  for hook in herdr-create.sh herdr-workspace.sh post-create.sh pre-delete.sh; do
    path="$plugin_root/hooks/$hook"
    if [ -x "$path" ]; then
      pass "hooks/$hook is executable"
    elif [ -f "$path" ]; then
      fail "hooks/$hook exists but is not executable"
    else
      fail "hooks/$hook is missing"
    fi
  done
fi

if on_path herdr; then
  plugin_list=$(herdr plugin list 2>/dev/null || true)
  if printf '%s\n' "$plugin_list" | grep -Fq 'grove.workspace'; then
    if printf '%s\n' "$plugin_list" | grep 'grove.workspace' | grep -Fq 'enabled'; then
      pass "Herdr plugin grove.workspace is linked and enabled"
    else
      fail "Herdr plugin grove.workspace is installed but disabled"
    fi
    if [ -n "$plugin_root" ] && printf '%s\n' "$plugin_list" | grep -F "grove.workspace" | grep -Fq "[local:$plugin_root]"; then
      pass "Herdr plugin root is $plugin_root"
    elif printf '%s\n' "$plugin_list" | grep -Fq 'grove.workspace'; then
      warn "grove.workspace is installed from a different path than $plugin_root"
    fi
  else
    fail "Herdr plugin grove.workspace is not installed"
  fi

  if herdr status >/dev/null 2>&1; then
    pass "Herdr server is running"
  else
    warn "Herdr server is not running (start herdr, then prefix+shift+g)"
  fi
fi

if [ -n "$configure" ] && command -v python3 >/dev/null 2>&1; then
  herdr_out=$(python3 "$configure" herdr-check --config "$HERDR_CONFIG" 2>/dev/null || true)
  if printf '%s\n' "$herdr_out" | grep -Eq '^PASS[[:space:]]'; then
    pass "prefix+shift+g opens the Grove popup"
  elif [ -f "$HERDR_CONFIG" ] && grep -Fq 'plugin pane open --plugin grove.workspace --entrypoint create' "$HERDR_CONFIG"; then
    pass "prefix+shift+g opens the Grove popup"
  else
    fail "prefix+shift+g is not bound to Grove ($HERDR_CONFIG)"
  fi

  grove_out=$(python3 "$configure" grove-check --config "$GROVE_CONFIG" --plugin-root "${plugin_root:-$INSTALL_DIR}" 2>/dev/null || true)
  if printf '%s\n' "$grove_out" | grep -Eq '^PASS[[:space:]]+post_create'; then
    pass "Grove post_create opens a Herdr workspace"
  elif [ -f "$GROVE_CONFIG" ] && grep -Fq 'post-create.sh' "$GROVE_CONFIG"; then
    pass "Grove post_create opens a Herdr workspace"
  else
    fail "Grove post_create is not wired ($GROVE_CONFIG)"
  fi
  if printf '%s\n' "$grove_out" | grep -Eq '^PASS[[:space:]]+pre_delete'; then
    pass "Grove pre_delete closes the Herdr workspace"
  elif [ -f "$GROVE_CONFIG" ] && grep -Fq 'pre-delete.sh' "$GROVE_CONFIG"; then
    pass "Grove pre_delete closes the Herdr workspace"
  else
    fail "Grove pre_delete is not wired ($GROVE_CONFIG)"
  fi
elif [ -f "$HERDR_CONFIG" ] && grep -Fq 'plugin pane open --plugin grove.workspace --entrypoint create' "$HERDR_CONFIG"; then
  pass "prefix+shift+g opens the Grove popup"
  if [ -f "$GROVE_CONFIG" ] && grep -Fq 'post-create.sh' "$GROVE_CONFIG"; then
    pass "Grove post_create opens a Herdr workspace"
  else
    fail "Grove post_create is not wired ($GROVE_CONFIG)"
  fi
  if [ -f "$GROVE_CONFIG" ] && grep -Fq 'pre-delete.sh' "$GROVE_CONFIG"; then
    pass "Grove pre_delete closes the Herdr workspace"
  else
    fail "Grove pre_delete is not wired ($GROVE_CONFIG)"
  fi
else
  fail "could not check Herdr/Grove config"
fi

printf '\n'
if [ "$failed" -eq 0 ]; then
  if [ "$warned" -eq 0 ]; then
    printf 'All checks passed. prefix+shift+g should open Grove.\n'
  else
    printf 'Ready, with %s warning(s). prefix+shift+g should open Grove.\n' "$warned"
  fi
  exit 0
fi

printf '%s check(s) failed. Fix: curl -fsSL https://raw.githubusercontent.com/nicksenap/grove-herdr/main/install.sh | sh\n' "$failed"
exit 1
