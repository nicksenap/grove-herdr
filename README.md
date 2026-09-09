# grove-herdr

[Grove](https://github.com/nicksenap/grove) workspace create, inside [Herdr](https://herdr.dev).

`prefix+shift+g` asks for a name, runs `gw create`, then opens that path as a Herdr workspace.

Needs `gw`, `herdr` 0.8.0+, `git`, and `python3`.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/nicksenap/grove-herdr/main/install.sh | sh
```

From a clone: `./install.sh`

Safe to re-run. It will not overwrite Grove hooks that already do something else.

## Update

Same command as install. It pulls the latest `main` into `~/.local/share/grove-herdr` and re-wires only if something changed.

```bash
curl -fsSL https://raw.githubusercontent.com/nicksenap/grove-herdr/main/install.sh | sh
```

Herdr has no `plugin update`. Re-running install is the update.

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

## What install changes

- Links this directory as Herdr plugin `grove.workspace`
- Binds `prefix+shift+g` to the Grove popup and clears Herdr’s stock worktree key
- Sets Grove `post_create` / `pre_delete` so Herdr workspaces open and close with `gw create` / `gw delete`

Theme, other keybindings, and Grove presets are left alone.
