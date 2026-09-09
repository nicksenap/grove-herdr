#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configure="$root/scripts/configure.py"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/grove-herdr-install-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  actual=$1
  expected=$2
  message=$3
  [ "$actual" = "$expected" ] || fail "$message"$'\n'"expected:\n$expected\nactual:\n$actual"
}

assert_file_eq() {
  python3 - "$1" "$2" "$3" <<'PY'
import pathlib, sys
left = pathlib.Path(sys.argv[1]).read_text()
right = pathlib.Path(sys.argv[2]).read_text()
if left != right:
    raise SystemExit(f"{sys.argv[3]}\n--- a\n{left}\n--- b\n{right}")
PY
}

run_herdr() {
  python3 "$configure" herdr --config "$1" --herdr-bin "$2"
}

run_grove() {
  python3 "$configure" grove --config "$1" --plugin-root "$2"
}

plugin_root=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$tmp/plugin")
mkdir -p "$plugin_root/hooks"
touch "$plugin_root/hooks/post-create.sh" "$plugin_root/hooks/pre-delete.sh"

# Empty Herdr config.
herdr_config="$tmp/herdr.toml"
run_herdr "$herdr_config" /opt/homebrew/bin/herdr >/dev/null
grep -Fq 'new_worktree = ""' "$herdr_config" || fail "missing new_worktree"
grep -Fq 'key = "prefix+shift+g"' "$herdr_config" || fail "missing keybinding"
grep -Fq 'plugin pane open --plugin grove.workspace --entrypoint create' "$herdr_config" || fail "missing create command"

cp "$herdr_config" "$tmp/herdr.first"
out=$(run_herdr "$herdr_config" /opt/homebrew/bin/herdr)
assert_eq "$out" "Herdr config already wired" "second herdr install should be a no-op"
assert_file_eq "$herdr_config" "$tmp/herdr.first" "re-running herdr wiring changed config.toml"

# Existing unrelated prefix+shift+g binding is replaced once, then stable.
cat > "$herdr_config" <<'EOF'
onboarding = false

[keys]
prefix = "ctrl+b"
new_worktree = "prefix+shift+g"

[[keys.command]]
key = "prefix+shift+g"
type = "popup"
command = "lazygit"
description = "lazygit"

[[keys.command]]
key = "prefix+shift+g"
type = "shell"
command = "echo duplicate"
EOF
run_herdr "$herdr_config" /usr/local/bin/herdr >/dev/null
grep -Fq 'new_worktree = ""' "$herdr_config" || fail "did not clear stock new_worktree"
grep -Fq '/usr/local/bin/herdr plugin pane open --plugin grove.workspace --entrypoint create' "$herdr_config" || fail "did not replace binding"
grep -Fvq 'lazygit' "$herdr_config" || fail "left old binding"
count=$(grep -c 'key = "prefix+shift+g"' "$herdr_config")
[ "$count" = 1 ] || fail "expected one prefix+shift+g binding, got $count"
cp "$herdr_config" "$tmp/herdr.replaced"
run_herdr "$herdr_config" /usr/local/bin/herdr >/dev/null
assert_file_eq "$herdr_config" "$tmp/herdr.replaced" "herdr replace path was not idempotent"

# Empty Grove config.
grove_config="$tmp/grove.toml"
run_grove "$grove_config" "$plugin_root" >/dev/null
grep -Fq "$plugin_root/hooks/post-create.sh {path} {name}" "$grove_config" || fail "missing post_create"
grep -Fq "$plugin_root/hooks/pre-delete.sh {path} {name}" "$grove_config" || fail "missing pre_delete"
cp "$grove_config" "$tmp/grove.first"
out=$(run_grove "$grove_config" "$plugin_root")
assert_eq "$out" "Grove hooks already wired" "second grove install should be a no-op"
assert_file_eq "$grove_config" "$tmp/grove.first" "re-running grove wiring changed config.toml"

# Existing Grove settings plus our hooks with an old path should update once.
mkdir -p "$tmp/old-grove-herdr/hooks"
cat > "$grove_config" <<EOF
repo_dirs = ["/work"]

[presets.backend]
repos = ["api"]

[hooks]
post_create = {command = "$tmp/old-grove-herdr/hooks/post-create.sh {path} {name}", timeout = "15s", on_failure = "warn"}
pre_delete = {command = "$tmp/old-grove-herdr/hooks/pre-delete.sh {path} {name}", timeout = "10s", on_failure = "warn"}
EOF
run_grove "$grove_config" "$plugin_root" >/dev/null
grep -Fq "$plugin_root/hooks/post-create.sh {path} {name}" "$grove_config" || fail "did not update old grove-herdr hook path"
grep -Fq 'repo_dirs = ["/work"]' "$grove_config" || fail "lost unrelated grove settings"
cp "$grove_config" "$tmp/grove.updated"
run_grove "$grove_config" "$plugin_root" >/dev/null
assert_file_eq "$grove_config" "$tmp/grove.updated" "grove path update was not idempotent"

# Foreign hooks are left alone.
cat > "$grove_config" <<'EOF'
[hooks]
post_create = "./scripts/workspace-created {path}"
pre_delete = "./scripts/workspace-closing {path}"
EOF
cp "$grove_config" "$tmp/grove.foreign"
out=$(run_grove "$grove_config" "$plugin_root" 2>&1)
printf '%s\n' "$out" | grep -q 'left hooks.post_create unchanged' || fail "should skip foreign post_create"
assert_file_eq "$grove_config" "$tmp/grove.foreign" "overwrote foreign Grove hooks"

# Full install.sh with stubbed herdr/gw: first run writes, second run is a no-op.
bin="$tmp/bin"
state="$tmp/herdr-state"
mkdir -p "$bin" "$state"
: > "$state/plugin-list"
cat > "$bin/herdr" <<'EOF'
#!/bin/sh
set -eu
state_dir=${GROVE_HERDR_TEST_STATE:?}
list_file=$state_dir/plugin-list
root_file=$state_dir/plugin-root
cmd=${1:-}
case "$cmd" in
  plugin)
    sub=${2:-}
    case "$sub" in
      list)
        cat "$list_file"
        ;;
      unlink|uninstall)
        : > "$list_file"
        ;;
      link)
        path=$3
        printf 'grove.workspace (Grove Workspace) enabled [local:%s]\n' "$path" > "$list_file"
        printf '%s\n' "$path" > "$root_file"
        ;;
      *)
        exit 0
        ;;
    esac
    ;;
  status)
    exit 1
    ;;
  server)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
cat > "$bin/gw" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$bin/herdr" "$bin/gw"

herdr_home="$tmp/herdr-home"
grove_home="$tmp/grove-home"
mkdir -p "$herdr_home" "$grove_home"
export PATH="$bin:$PATH"
export GROVE_HERDR_TEST_STATE="$state"
export HERDR_CONFIG_PATH="$herdr_home/config.toml"
export GROVE_DIR="$grove_home"
export GROVE_CONFIG="$grove_home/config.toml"

"$root/install.sh" >/dev/null
grep -Fq 'grove.workspace' "$state/plugin-list" || fail "install.sh did not link plugin"
grep -Fq 'new_worktree = ""' "$HERDR_CONFIG_PATH" || fail "install.sh did not wire herdr keys"
grep -Fq 'post-create.sh {path} {name}' "$GROVE_CONFIG" || fail "install.sh did not wire grove hooks"
cp "$HERDR_CONFIG_PATH" "$tmp/install.herdr"
cp "$GROVE_CONFIG" "$tmp/install.grove"
cp "$state/plugin-list" "$tmp/install.plugin-list"

"$root/install.sh" >/dev/null
assert_file_eq "$HERDR_CONFIG_PATH" "$tmp/install.herdr" "second install.sh changed herdr config"
assert_file_eq "$GROVE_CONFIG" "$tmp/install.grove" "second install.sh changed grove config"
assert_file_eq "$state/plugin-list" "$tmp/install.plugin-list" "second install.sh relinked the plugin"

printf 'Install idempotency tests passed.\n'
