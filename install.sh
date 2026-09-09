#!/bin/sh
set -eu

REPO_URL=${GROVE_HERDR_REPO:-https://github.com/nicksenap/grove-herdr.git}
INSTALL_DIR=${GROVE_HERDR_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/grove-herdr}
HERDR_CONFIG=${HERDR_CONFIG_PATH:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr/config.toml}
GROVE_DIR=${GROVE_DIR:-$HOME/.grove}
GROVE_CONFIG=${GROVE_CONFIG:-$GROVE_DIR/config.toml}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "install.sh needs $1 on PATH"
}

abs_dir() {
  CDPATH= cd -- "$1" && pwd
}

ensure_checkout() {
  need git
  if [ -d "$INSTALL_DIR/.git" ]; then
    git -C "$INSTALL_DIR" fetch --quiet origin 2>/dev/null || \
      printf 'warning: could not fetch grove-herdr; using existing checkout\n' >&2
    git -C "$INSTALL_DIR" merge --ff-only --quiet origin/main 2>/dev/null || true
  else
    mkdir -p "$(dirname -- "$INSTALL_DIR")"
    git clone --quiet "$REPO_URL" "$INSTALL_DIR"
  fi
  [ -f "$INSTALL_DIR/herdr-plugin.toml" ] || die "clone at $INSTALL_DIR is missing herdr-plugin.toml"
  [ -x "$INSTALL_DIR/install.sh" ] || chmod +x "$INSTALL_DIR/install.sh"
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

if [ -n "$here" ] && [ -f "$here/herdr-plugin.toml" ]; then
  plugin_root=$here
else
  ensure_checkout
  exec "$INSTALL_DIR/install.sh"
fi

need herdr
need gw
need python3

herdr_bin=$(command -v herdr)
chmod +x \
  "$plugin_root/hooks/herdr-create.sh" \
  "$plugin_root/hooks/herdr-workspace.sh" \
  "$plugin_root/hooks/post-create.sh" \
  "$plugin_root/hooks/pre-delete.sh" \
  "$plugin_root/scripts/configure.py"

printf '==> linking Herdr plugin from %s\n' "$plugin_root"
plugin_list=$(herdr plugin list 2>/dev/null || true)
if printf '%s\n' "$plugin_list" | grep -F "grove.workspace" | grep -Fq "[local:$plugin_root]"; then
  printf '    already linked\n'
else
  herdr plugin unlink grove.workspace >/dev/null 2>&1 || true
  herdr plugin uninstall grove.workspace >/dev/null 2>&1 || true
  herdr plugin link "$plugin_root" --enabled >/dev/null
  printf '    linked grove.workspace\n'
fi

printf '==> wiring Herdr keybinding\n'
python3 "$plugin_root/scripts/configure.py" herdr \
  --config "$HERDR_CONFIG" \
  --herdr-bin "$herdr_bin" | sed 's/^/    /'

printf '==> wiring Grove lifecycle hooks\n'
python3 "$plugin_root/scripts/configure.py" grove \
  --config "$GROVE_CONFIG" \
  --plugin-root "$plugin_root" | sed 's/^/    /'

if herdr status >/dev/null 2>&1; then
  herdr server reload-config >/dev/null 2>&1 || \
    printf '    herdr is running; reload config if the keybinding does not appear\n'
else
  printf '    herdr server not running; keybinding applies on next start\n'
fi

printf '\nGrove Workspace is installed. Re-run this script any time; it is safe.\n'
printf '  plugin: %s\n' "$plugin_root"
printf '  key:    prefix+shift+g\n'
printf '  herdr:  %s\n' "$HERDR_CONFIG"
printf '  grove:  %s\n' "$GROVE_CONFIG"
