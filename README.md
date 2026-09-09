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

## Requirements

- [Grove](https://github.com/nicksenap/grove) (`gw` on `PATH`)
- [Herdr](https://herdr.dev) 0.8.0+
- Python 3 (for the Grove ↔ Herdr workspace bridge)
- macOS or Linux

## Install

```bash
herdr plugin install nicksenap/grove-herdr
```

Then bind the popup in `~/.config/herdr/config.toml` so Grove owns `prefix+shift+g`:

```toml
[keys]
new_worktree = ""

[[keys.command]]
key = "prefix+shift+g"
type = "shell"
command = "herdr plugin pane open --plugin grove.workspace --entrypoint create"
description = "create Grove workspace"
```

Reload Herdr config after editing (`herdr server reload-config`, or restart).

### Optional: open/close Herdr workspaces from Grove

Point Grove's lifecycle hooks at the installed plugin. After `herdr plugin install`, the plugin root is the managed checkout shown by `herdr plugin list`.

```toml
# ~/.grove/config.toml
[hooks]
post_create = {command = "<plugin-root>/hooks/post-create.sh {path} {name}", timeout = "15s", on_failure = "warn"}
pre_delete = {command = "<plugin-root>/hooks/pre-delete.sh {path} {name}", timeout = "10s", on_failure = "warn"}
```

Replace `<plugin-root>` with the path from `herdr plugin list`. If you clone or link the repo yourself, use that path instead.

`post_create` focuses an existing Herdr workspace for that Grove path, or creates one. `pre_delete` closes it on `gw delete`. Both no-op if Herdr is not running.

### Local development

```bash
herdr plugin link /path/to/grove-herdr
```

`herdr plugin install` refuses to overwrite a locally linked plugin. Unlink first if you want to switch to the GitHub install.

## Usage

1. Press `prefix+shift+g` in Herdr.
2. Type a Grove workspace name. Escape dismisses.
3. Grove runs `gw create <name>` (repo picker included).
4. If Grove hooks are configured, a Herdr workspace opens on that path.

## Layout

```text
herdr-plugin.toml          Herdr plugin manifest (id: grove.workspace)
hooks/
  herdr-create.sh          Popup: type a name, then gw create
  herdr-workspace.sh       Open/focus/close a matching Herdr workspace
  post-create.sh           Grove post_create → herdr-workspace.sh open
  pre-delete.sh            Grove pre_delete → herdr-workspace.sh close
```

## Uninstall

```bash
herdr plugin uninstall grove.workspace
```

Remove the `prefix+shift+g` binding and Grove hooks if you added them.
