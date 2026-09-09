# grove-herdr

[Herdr](https://herdr.dev) plugin that lets [Grove](https://github.com/nicksenap/grove) own workspace creation.

Herdr's stock worktree dialog is single-repo. Grove is the opposite: one branch, many repos, one workspace. This plugin replaces that dialog with a Grove popup, then opens a matching Herdr workspace after `gw create`.

```text
prefix+shift+g
        ↓
Grove popup: type a name
        ↓
gw create my-feature
        ↓
Grove post_create
        ↓
herdr workspace create --cwd <grove-path>
```

## Install

Needs `gw`, `herdr` (0.8.0+), `git`, and `python3`.

```bash
curl -fsSL https://raw.githubusercontent.com/nicksenap/grove-herdr/main/install.sh | sh
```

Or from a clone:

```bash
./install.sh
```

The script is idempotent. Re-run it any time. A second run is a no-op if the plugin is already linked, `prefix+shift+g` already opens Grove, and Grove's lifecycle hooks already point here.

It will:

1. Clone or update a checkout (curl path uses `~/.local/share/grove-herdr`)
2. `herdr plugin link` this directory
3. Bind `prefix+shift+g` to the Grove create popup and clear Herdr's stock worktree key
4. Point Grove `post_create` / `pre_delete` at this plugin, unless those hooks already run something else
5. Reload Herdr config when a server is running

Existing unrelated Herdr settings are left alone. If Grove already has custom `post_create` / `pre_delete` hooks, they are not overwritten.

## Usage

1. Press `prefix+shift+g` in Herdr.
2. Type a Grove workspace name. Escape dismisses.
3. Grove runs `gw create <name>` (repo picker included).
4. A Herdr workspace opens on that path.

## Layout

```text
install.sh                 One-shot, re-runnable installer
scripts/configure.py       Idempotent Herdr + Grove config wiring
herdr-plugin.toml          Herdr plugin manifest (id: grove.workspace)
hooks/
  herdr-create.sh          Popup: type a name, then gw create
  herdr-workspace.sh       Open/focus/close a matching Herdr workspace
  post-create.sh           Grove post_create → herdr-workspace.sh open
  pre-delete.sh            Grove pre_delete → herdr-workspace.sh close
```
