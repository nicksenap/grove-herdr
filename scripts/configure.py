#!/usr/bin/env python3
"""Idempotent Herdr + Grove config wiring for grove-herdr."""

from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path

PLUGIN_ID = "grove.workspace"
ENTRYPOINT = "create"
DEFAULT_KEY = "prefix+shift+g"
CREATE_COMMAND_NEEDLE = f"plugin pane open --plugin {PLUGIN_ID} --entrypoint {ENTRYPOINT}"
HOOK_TIMEOUTS = {"post_create": "15s", "pre_delete": "10s"}

HEADER_RE = re.compile(r"^\[+[^\]]+\]+\s*$", re.M)
NEW_WORKTREE_RE = re.compile(r"(?m)^(?P<indent>[ \t]*)new_worktree\s*=\s*(?P<value>[^\n#]+)")
KEY_LINE_RE = re.compile(r'(?m)^[ \t]*key\s*=\s*(?P<q>["\'])(?P<value>.*)(?P=q)\s*$')
COMMAND_LINE_RE = re.compile(r'(?m)^[ \t]*command\s*=\s*(?P<q>["\'])(?P<value>.*)(?P=q)\s*$')


def fail(message: str) -> None:
    raise SystemExit(message)


def newline_for(text: str) -> str:
    return "\r\n" if "\r\n" in text else "\n"


def ensure_trailing_newline(text: str, nl: str) -> str:
    if not text:
        return ""
    return text if text.endswith(nl) else text + nl


def quote_toml(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def sections(text: str) -> list[tuple[str, int, int]]:
    matches = list(HEADER_RE.finditer(text))
    out: list[tuple[str, int, int]] = []
    for i, match in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        out.append((match.group(0).strip(), match.start(), end))
    return out


def section_body(text: str, header: str, start: int, end: int) -> str:
    first_nl = text.find("\n", start)
    if first_nl == -1 or first_nl >= end:
        return ""
    return text[first_nl + 1 : end]


def create_command(herdr_bin: str) -> str:
    return f"{herdr_bin} plugin pane open --plugin {PLUGIN_ID} --entrypoint {ENTRYPOINT}"


def is_our_create_command(command: str) -> bool:
    collapsed = " ".join(command.split())
    return CREATE_COMMAND_NEEDLE in collapsed


def backup_if_changed(path: Path, old: str, new: str) -> None:
    if old == new:
        return
    if not path.exists() or old == "":
        return
    shutil.copy2(path, path.with_name(path.name + ".grove-herdr.bak"))


def write_if_changed(path: Path, old: str, new: str) -> bool:
    if old == new:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    backup_if_changed(path, old, new)
    path.write_text(new, encoding="utf-8")
    return True


def upsert_new_worktree(text: str) -> tuple[str, list[str]]:
    nl = newline_for(text)
    changes: list[str] = []
    found = [s for s in sections(text) if s[0] == "[keys]"]
    if not found:
        block = f"[keys]{nl}new_worktree = \"\"{nl}"
        if text.strip():
            text = ensure_trailing_newline(text, nl) + nl + block
        else:
            text = block
        return text, ["added [keys] new_worktree = \"\""]

    header, start, end = found[0]
    body = section_body(text, header, start, end)
    match = NEW_WORKTREE_RE.search(body)
    if not match:
        insert_at = text.find("\n", start)
        insert_at = insert_at + 1 if insert_at != -1 else start + len(header)
        text = text[:insert_at] + f'new_worktree = ""{nl}' + text[insert_at:]
        changes.append("set new_worktree = \"\"")
        return text, changes

    current = match.group("value").strip()
    if current in {'""', "''"}:
        return text, changes

    body_start = text.find("\n", start) + 1
    abs_start = body_start + match.start()
    abs_end = body_start + match.end()
    indent = match.group("indent")
    text = text[:abs_start] + f'{indent}new_worktree = ""' + text[abs_end:]
    changes.append("cleared keys.new_worktree")
    return text, changes


def command_tables(text: str) -> list[tuple[int, int, str]]:
    return [
        (start, end, text[start:end])
        for header, start, end in sections(text)
        if header == "[[keys.command]]"
    ]


def table_key(block: str) -> str | None:
    match = KEY_LINE_RE.search(block)
    return match.group("value") if match else None


def table_command(block: str) -> str | None:
    match = COMMAND_LINE_RE.search(block)
    return match.group("value") if match else None


def render_command_table(herdr_bin: str, nl: str) -> str:
    command = create_command(herdr_bin)
    return (
        f"[[keys.command]]{nl}"
        f'key = "{DEFAULT_KEY}"{nl}'
        f'type = "shell"{nl}'
        f"command = {quote_toml(command)}{nl}"
        f'description = "create Grove workspace"{nl}'
    )


def upsert_command_binding(text: str, herdr_bin: str) -> tuple[str, list[str]]:
    nl = newline_for(text)
    wanted = render_command_table(herdr_bin, nl)
    changes: list[str] = []
    tables = command_tables(text)
    matching = [item for item in tables if table_key(item[2]) == DEFAULT_KEY]

    if not matching:
        text = ensure_trailing_newline(text, nl)
        if text and not text.endswith(nl + nl):
            text = text + nl
        text = text + wanted
        changes.append(f"bound {DEFAULT_KEY} to Grove create popup")
        return text, changes

    first_start, first_end, first_block = matching[0]
    current_command = table_command(first_block) or ""
    if first_block.strip() != wanted.strip():
        text = text[:first_start] + wanted + text[first_end:]
        if is_our_create_command(current_command):
            changes.append(f"updated {DEFAULT_KEY} Grove binding")
        else:
            changes.append(f"replaced {DEFAULT_KEY} binding with Grove create popup")
        delta = len(wanted) - (first_end - first_start)
        tables = command_tables(text)
        matching = [item for item in tables if table_key(item[2]) == DEFAULT_KEY]

    extras = matching[1:]
    if extras:
        for start, end, _block in reversed(extras):
            text = text[:start] + text[end:]
        changes.append(f"removed duplicate {DEFAULT_KEY} bindings")
    return text, changes


def upsert_herdr(text: str, herdr_bin: str) -> tuple[str, list[str]]:
    nl = newline_for(text)
    if not text.strip():
        text = ""
    text, changes = upsert_new_worktree(text)
    text, extra = upsert_command_binding(text, herdr_bin)
    changes.extend(extra)
    return ensure_trailing_newline(text, nl), changes


def hook_script(plugin_root: str, name: str) -> str:
    return str(Path(plugin_root).resolve() / "hooks" / name)


def hook_command(plugin_root: str, script_name: str) -> str:
    return f"{hook_script(plugin_root, script_name)} {{path}} {{name}}"


def is_our_hook(command: str, plugin_root: str, script_name: str) -> bool:
    if not command:
        return False
    if script_name in command and str(Path(plugin_root).resolve()) in command:
        return True
    return "grove-herdr" in command and script_name in command


def extract_inline_command(value: str) -> str | None:
    match = re.search(r'command\s*=\s*(["\'])(.*?)\1', value)
    if match:
        return match.group(2)
    match = re.search(r'^\s*(["\'])(.*?)\1\s*$', value)
    if match:
        return match.group(2)
    value = value.strip()
    return value or None


def extract_hook_command(text: str, hook: str) -> tuple[str | None, str]:
    """Return (command, form) where form is missing|string|inline|table."""
    for header, start, end in sections(text):
        if header == f"[hooks.{hook}]":
            body = section_body(text, header, start, end)
            match = COMMAND_LINE_RE.search(body)
            return (match.group("value") if match else None), "table"
        if header != "[hooks]":
            continue
        body = section_body(text, header, start, end)
        assign = re.search(
            rf"(?m)^[ \t]*{re.escape(hook)}\s*=\s*(?P<value>.+?)\s*$",
            body,
        )
        if not assign:
            continue
        value = assign.group("value").strip()
        if value.startswith("{"):
            return extract_inline_command(value), "inline"
        return extract_inline_command(value), "string"
    return None, "missing"


def replace_hook_assignment(text: str, hook: str, command: str) -> str:
    nl = newline_for(text)
    inline = (
        f"{hook} = {{command = {quote_toml(command)}, "
        f'timeout = "{HOOK_TIMEOUTS[hook]}", on_failure = "warn"}}'
    )
    for header, start, end in sections(text):
        if header == f"[hooks.{hook}]":
            body_start = text.find("\n", start) + 1
            body = text[body_start:end]
            match = COMMAND_LINE_RE.search(body)
            if match:
                abs_start = body_start + match.start()
                abs_end = body_start + match.end()
                indent = re.match(r"[ \t]*", match.group(0)).group(0)
                return (
                    text[:abs_start]
                    + f"{indent}command = {quote_toml(command)}"
                    + text[abs_end:]
                )
            return text[:end] + f"command = {quote_toml(command)}{nl}" + text[end:]
        if header != "[hooks]":
            continue
        body_start = text.find("\n", start) + 1
        body = text[body_start:end]
        assign = re.search(
            rf"(?m)^[ \t]*{re.escape(hook)}\s*=\s*.+?\s*$",
            body,
        )
        if not assign:
            continue
        abs_start = body_start + assign.start()
        abs_end = body_start + assign.end()
        indent = re.match(r"[ \t]*", assign.group(0)).group(0)
        return text[:abs_start] + indent + inline + text[abs_end:]
    return text


def insert_hook_assignment(text: str, hook: str, command: str) -> str:
    nl = newline_for(text)
    inline = (
        f"{hook} = {{command = {quote_toml(command)}, "
        f'timeout = "{HOOK_TIMEOUTS[hook]}", on_failure = "warn"}}{nl}'
    )
    hooks = [s for s in sections(text) if s[0] == "[hooks]"]
    if not hooks:
        block = f"[hooks]{nl}{inline}"
        if text.strip():
            return ensure_trailing_newline(text, nl) + nl + block
        return block

    _header, start, end = hooks[0]
    insert_at = end
    while insert_at > start and text[insert_at - 1] in "\r\n":
        insert_at -= 1
    prefix = text[:insert_at]
    suffix = text[insert_at:]
    if prefix and not prefix.endswith(nl):
        prefix += nl
    return prefix + nl + inline + suffix


def upsert_grove(text: str, plugin_root: str) -> tuple[str, list[str], list[str]]:
    nl = newline_for(text)
    changes: list[str] = []
    skipped: list[str] = []
    if not text.strip():
        text = ""

    for hook, script_name in (
        ("post_create", "post-create.sh"),
        ("pre_delete", "pre-delete.sh"),
    ):
        wanted = hook_command(plugin_root, script_name)
        current, form = extract_hook_command(text, hook)
        if form == "missing" or current is None:
            text = insert_hook_assignment(text, hook, wanted)
            changes.append(f"set hooks.{hook}")
            continue
        if is_our_hook(current, plugin_root, script_name):
            if current != wanted:
                text = replace_hook_assignment(text, hook, wanted)
                changes.append(f"updated hooks.{hook} path")
            continue
        skipped.append(
            f"left hooks.{hook} unchanged ({current})"
        )
    return ensure_trailing_newline(text, nl), changes, skipped


def apply_herdr(path: Path, herdr_bin: str) -> list[str]:
    old = path.read_text(encoding="utf-8") if path.exists() else ""
    new, changes = upsert_herdr(old, herdr_bin)
    if write_if_changed(path, old, new):
        return changes or ["updated Herdr config"]
    return []


def apply_grove(path: Path, plugin_root: str) -> tuple[list[str], list[str]]:
    old = path.read_text(encoding="utf-8") if path.exists() else ""
    new, changes, skipped = upsert_grove(old, plugin_root)
    if write_if_changed(path, old, new):
        return (changes or ["updated Grove config"]), skipped
    return [], skipped


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    herdr = sub.add_parser("herdr")
    herdr.add_argument("--config", required=True)
    herdr.add_argument("--herdr-bin", required=True)

    grove = sub.add_parser("grove")
    grove.add_argument("--config", required=True)
    grove.add_argument("--plugin-root", required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.cmd == "herdr":
        changes = apply_herdr(Path(args.config), args.herdr_bin)
        if changes:
            for line in changes:
                print(line)
        else:
            print("Herdr config already wired")
        return 0

    changes, skipped = apply_grove(Path(args.config), args.plugin_root)
    if changes:
        for line in changes:
            print(line)
    else:
        print("Grove hooks already wired")
    for line in skipped:
        print(f"skip: {line}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
