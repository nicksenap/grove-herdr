#!/bin/sh
# post_create gate: does the hook open a Herdr workspace?
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
hook="$root/hooks/post-create.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/grove-herdr-post-create-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

# The tests run inside agents; never inherit their markers or an override.
unset PI_CODING_AGENT CLAUDECODE GROVE_HERDR_OPEN || true

bin="$tmp/bin"
mkdir -p "$bin" "$tmp/workspace"
cat > "$bin/herdr" <<'STUB'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "${GROVE_HERDR_TEST_STATE:?}/calls"
case "$1 ${2:-}" in
  "status "*) exit 0 ;;
  "workspace list")
    if [ -n "${GROVE_HERDR_TEST_EXISTING:-}" ]; then
      printf '{"result":{"workspaces":[{"workspace_id":"w-0","worktree":{"checkout_path":"%s"}}]}}\n' "$GROVE_HERDR_TEST_EXISTING"
    else
      printf '{"result":{"workspaces":[]}}\n'
    fi
    ;;
  "api snapshot") printf '{"result":{"snapshot":{"agents":[]}}}\n' ;;
  "workspace create") printf '{"result":{"workspace":{"workspace_id":"w-1"}}}\n' ;;
  *) printf '{}\n' ;;
esac
STUB
chmod +x "$bin/herdr"
export HERDR_BIN_PATH="$bin/herdr"

ws="$tmp/workspace"
case_dir=""
out=""
err=""
code=0

# run_hook <case-name> [VAR=value ...]; helper_no_focus=1 runs `herdr-workspace.sh open --no-focus` instead.
helper_no_focus=0
run_hook() {
  case_dir="$tmp/cases/$1"
  shift
  mkdir -p "$case_dir/state" "$case_dir/xdg"
  : > "$case_dir/state/calls"
  code=0
  if [ "$helper_no_focus" = 1 ]; then
    env GROVE_HERDR_TEST_STATE="$case_dir/state" XDG_STATE_HOME="$case_dir/xdg" "$@" \
      "$root/hooks/herdr-workspace.sh" open --no-focus "$ws" feature >"$case_dir/out" 2>"$case_dir/err" || code=$?
  else
    env GROVE_HERDR_TEST_STATE="$case_dir/state" XDG_STATE_HOME="$case_dir/xdg" "$@" \
      "$hook" "$ws" feature >"$case_dir/out" 2>"$case_dir/err" || code=$?
  fi
  out=$(cat "$case_dir/out")
  err=$(cat "$case_dir/err")
}

assert_opened() {
  [ "$code" = 0 ] || fail "$1: exit $code"
  grep -q '^workspace create' "$case_dir/state/calls" || fail "$1: expected workspace create; calls: $(cat "$case_dir/state/calls")"
  [ -f "$case_dir/xdg/grove-herdr/workspaces.json" ] || fail "$1: expected state file"
}

assert_skipped() {
  [ "$code" = 0 ] || fail "$1: exit $code"
  [ ! -s "$case_dir/state/calls" ] || fail "$1: herdr was called: $(cat "$case_dir/state/calls")"
  [ ! -e "$case_dir/xdg/grove-herdr" ] || fail "$1: state written for a skipped open"
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] || fail "$1: expected one stdout line, got: $out"
  printf '%s\n' "$out" | grep -Fq 'herdr-workspace: skipped open' || fail "$1: missing skip line: $out"
  printf '%s\n' "$out" | grep -Fq "open with: $root/hooks/herdr-workspace.sh open" || fail "$1: missing manual open command: $out"
  printf '%s\n' "$out" | grep -Fq 'GROVE_HERDR_OPEN=1' || fail "$1: missing override hint: $out"
}

# assert_create_flag <case-name> <expected-flag> <forbidden-flag>
assert_create_flag() {
  create=$(grep '^workspace create' "$case_dir/state/calls")
  printf '%s\n' "$create" | grep -Eq -- "(^| )$2( |\$)" || fail "$1: expected $2; got: $create"
  ! printf '%s\n' "$create" | grep -Eq -- "(^| )$3( |\$)" || fail "$1: unexpected $3; got: $create"
}

run_hook human
assert_opened "no markers"
assert_create_flag "no markers" --focus --no-focus

run_hook pi PI_CODING_AGENT=1
assert_skipped "PI_CODING_AGENT"
printf '%s\n' "$out" | grep -Fq 'agent context: PI_CODING_AGENT' || fail "PI_CODING_AGENT: reason missing: $out"

run_hook claude CLAUDECODE=1
assert_skipped "CLAUDECODE"
printf '%s\n' "$out" | grep -Fq 'agent context: CLAUDECODE' || fail "CLAUDECODE: reason missing: $out"

run_hook empty-marker PI_CODING_AGENT=
assert_opened "empty marker"

run_hook force PI_CODING_AGENT=1 GROVE_HERDR_OPEN=1
assert_opened "marker + GROVE_HERDR_OPEN=1"

# An agent opening its workspace itself, in the background.
helper_no_focus=1
run_hook helper-no-focus
assert_opened "helper open --no-focus"
assert_create_flag "helper open --no-focus" --no-focus --focus

run_hook helper-no-focus-existing GROVE_HERDR_TEST_EXISTING="$ws"
[ "$code" = 0 ] || fail "existing, helper --no-focus: exit $code"
! grep -q '^workspace focus' "$case_dir/state/calls" || fail "existing, helper --no-focus: focused: $(cat "$case_dir/state/calls")"
! grep -q '^workspace create' "$case_dir/state/calls" || fail "existing, helper --no-focus: created a duplicate"
helper_no_focus=0

run_hook human-existing GROVE_HERDR_TEST_EXISTING="$ws"
grep -q '^workspace focus w-0' "$case_dir/state/calls" || fail "existing, no markers: expected focus; calls: $(cat "$case_dir/state/calls")"

run_hook never GROVE_HERDR_OPEN=0
assert_skipped "GROVE_HERDR_OPEN=0"
printf '%s\n' "$out" | grep -Fq 'GROVE_HERDR_OPEN=0' || fail "GROVE_HERDR_OPEN=0: reason missing: $out"

run_hook empty-override GROVE_HERDR_OPEN=
assert_opened "empty GROVE_HERDR_OPEN"

run_hook bad-human GROVE_HERDR_OPEN=yes
assert_opened "invalid override, no marker"
printf '%s\n' "$err" | grep -Fq "ignoring GROVE_HERDR_OPEN=yes" || fail "invalid override: no warning: $err"

run_hook bad-agent GROVE_HERDR_OPEN=yes CLAUDECODE=1
assert_skipped "invalid override, marker"
printf '%s\n' "$err" | grep -Fq "ignoring GROVE_HERDR_OPEN=yes" || fail "invalid override + marker: no warning: $err"

printf 'post_create gate tests passed.\n'
