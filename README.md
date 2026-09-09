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

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/nicksenap/grove-herdr/main/uninstall.sh | sh
```

Or from a clone: `./uninstall.sh`

Also idempotent. It unlinks `grove.workspace`, removes only this plugin's `prefix+shift+g` binding and Grove hooks, and leaves everything else. The checkout under `~/.local/share/grove-herdr` stays on disk.

## Versioning

Herdr does not have a plugin registry or `plugin update`. Versioning is:

- `version` in `herdr-plugin.toml` — display metadata (`0.1.0` today)
- `min_herdr_version` — oldest Herdr that can load the plugin (`0.8.0`)
- Git — `herdr plugin install owner/repo --ref <tag-or-sha>` pins a revision; reinstalling replaces the managed checkout. There is no separate update command.

This installer uses `herdr plugin link` on a git checkout, so `./install.sh` fast-forwards that clone. Bump `version` in the manifest when behavior changes.

## Usage

1. Press `prefix+shift+g` in Herdr.
2. Type a Grove workspace name. Escape dismisses.
3. Grove runs `gw create <name>` (repo picker included).
4. A Herdr workspace opens on that path.

## Layout

```text
install.sh                 One-shot, re-runnable installer
uninstall.sh               Inverse of install.sh; also re-runnable
scripts/configure.py       Idempotent Herdr + Grove config wiring
herdr-plugin.toml          Herdr plugin manifest (id: grove.workspace)
hooks/
  herdr-create.sh          Popup: type a name, then gw create
  herdr-workspace.sh       Open/focus/close a matching Herdr workspace
  post-create.sh           Grove post_create → herdr-workspace.sh open
  pre-delete.sh            Grove pre_delete → herdr-workspace.sh close
```
