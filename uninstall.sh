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

abs_dir() {
  CDPATH= cd -- "$1" && pwd
}

ensure_checkout() {
  command -v git >/dev/null 2>&1 || die "uninstall.sh needs git on PATH to fetch configure.py"
  if [ -d "$INSTALL_DIR/.git" ]; then
    git -C "$INSTALL_DIR" fetch --quiet origin 2>/dev/null || true
  else
    mkdir -p "$(dirname -- "$INSTALL_DIR")"
    git clone --quiet "$REPO_URL" "$INSTALL_DIR"
  fi
  [ -f "$INSTALL_DIR/scripts/configure.py" ] || die "clone at $INSTALL_DIR is missing scripts/configure.py"
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

if [ -n "$here" ] && [ -f "$here/scripts/configure.py" ]; then
  plugin_root=$here
elif [ -f "$INSTALL_DIR/scripts/configure.py" ]; then
  plugin_root=$INSTALL_DIR
else
  ensure_checkout
  exec "$INSTALL_DIR/uninstall.sh"
fi

configure="$plugin_root/scripts/configure.py"

need_python() {
  command -v python3 >/dev/null 2>&1 || die "uninstall.sh needs python3 on PATH"
}

need_python

printf '==> unlinking Herdr plugin\n'
if command -v herdr >/dev/null 2>&1; then
  plugin_list=$(herdr plugin list 2>/dev/null || true)
  if printf '%s\n' "$plugin_list" | grep -Fq 'grove.workspace'; then
    herdr plugin unlink grove.workspace >/dev/null 2>&1 || true
    herdr plugin uninstall grove.workspace >/dev/null 2>&1 || true
    printf '    unlinked grove.workspace\n'
  else
    printf '    grove.workspace not installed\n'
  fi
else
  printf '    herdr not on PATH; skipped plugin unlink\n'
fi

printf '==> removing Herdr keybinding\n'
python3 "$configure" herdr-uninstall --config "$HERDR_CONFIG" | sed 's/^/    /'

printf '==> removing Grove lifecycle hooks\n'
python3 "$configure" grove-uninstall \
  --config "$GROVE_CONFIG" \
  --plugin-root "${plugin_root:-$INSTALL_DIR}" | sed 's/^/    /'

if command -v herdr >/dev/null 2>&1 && herdr status >/dev/null 2>&1; then
  herdr server reload-config >/dev/null 2>&1 || \
    printf '    herdr is running; reload config if the keybinding is still bound\n'
fi

printf '\nGrove Workspace is uninstalled. Re-run this script any time; it is safe.\n'
printf 'The checkout at %s is left in place.\n' "${plugin_root:-$INSTALL_DIR}"
printf 'Delete that directory yourself if you want the files gone.\n'
