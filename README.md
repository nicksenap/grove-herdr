# grove-herdr

[Grove](https://github.com/nicksenap/grove) workspace create, inside [Herdr](https://herdr.dev).

`prefix+shift+g` asks for a name, runs `gw create`, then opens that path as a Herdr workspace.

Needs `gw`, `herdr` 0.8.0+, `git`, and `python3`.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/nicksenap/grove-herdr/main/install.sh | sh
```

From a clone: `./install.sh`

That is the recommended path. It links the plugin, binds `prefix+shift+g`, and wires Grove `post_create` / `pre_delete` so a Herdr workspace opens and closes with `gw create` / `gw delete`. Safe to re-run. It will not overwrite Grove hooks that already do something else.

You can also install only the plugin with Herdr:

```bash
herdr plugin install nicksenap/grove-herdr
```

That registers `grove.workspace` and nothing else. No keybinding, no Grove hooks, so `prefix+shift+g` still opens Herdr’s stock single-repo worktree dialog. Use the shell script unless you want to wire those by hand.

## Check

```bash
curl -fsSL https://raw.githubusercontent.com/nicksenap/grove-herdr/main/check.sh | sh
```

From a clone: `./check.sh`

Prints PASS/FAIL for `herdr`, `gw`, `python3`, plugin files, the Herdr link, `prefix+shift+g`, and Grove hooks. Exit 0 only if the whole flow is wired. `install.sh` runs this at the end.

## Update

Same command as install. It pulls the latest `main` into `~/.local/share/grove-herdr` and re-wires only if something changed.

```bash
curl -fsSL https://raw.githubusercontent.com/nicksenap/grove-herdr/main/install.sh | sh
```

Herdr has no `plugin update`. Re-running install is the update. `herdr plugin install nicksenap/grove-herdr` again also refreshes a GitHub-managed install, but still will not bind the key or Grove hooks.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/nicksenap/grove-herdr/main/uninstall.sh | sh
```

From a clone: `./uninstall.sh`

Removes the plugin, the `prefix+shift+g` Grove binding, and only the Grove hooks this plugin added. Leaves `~/.local/share/grove-herdr` on disk.

## Use

1. In Herdr, press `prefix+shift+g`.
2. Type a workspace name. Escape cancels.
3. Grove creates the workspace (repo picker included).
4. A Herdr workspace opens on that path.

## Agents

When a coding agent runs `gw create`, the `post_create` hook still lets Grove create the workspace, but it doesn't open or focus a Herdr workspace. It prints one line instead:

```
herdr-workspace: skipped open (agent context: PI_CODING_AGENT); open with: ~/.local/share/grove-herdr/hooks/herdr-workspace.sh open <path> <name> (or set GROVE_HERDR_OPEN=1)
```

Run that `open with:` command to open it later. `gw delete` then closes it as usual.

The hook treats the caller as an agent when one of these is set and non-empty:

| Variable | Agent |
| --- | --- |
| `PI_CODING_AGENT` | Pi |
| `CLAUDECODE` | Claude Code |

`prefix+shift+g` and `gw create` typed by hand still open the workspace.

`GROVE_HERDR_OPEN` overrides detection either way:

- `GROVE_HERDR_OPEN=1` always opens.
- `GROVE_HERDR_OPEN=0` never opens. Set it in the environment of an agent that isn't detected.
- Unset or empty means auto-detect. Any other value is ignored with a warning.
