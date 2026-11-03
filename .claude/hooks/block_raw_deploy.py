#!/usr/bin/env python3
"""Claude Code hook (PreToolUse, Bash): blocks raw production deploy commands and points to the safe ones.

The website goes live only through `make site` (scripts/deploy_site.py) and the app only through `make release`
(scripts/release.sh), because they refuse to ship from a copy that's missing live work. See AGENTS.md.

Reads the hook's JSON on stdin; exit 2 blocks the command and shows the message to the agent. It's a guardrail for
the obvious ways in (wrangler, npx wrangler, bash -c "…", gh release …), not a wall: the rule is in AGENTS.md.
"""
import json
import os
import re
import shlex
import sys

# Words that run the next word as the command.
WRAPPERS = {"sudo", "env", "command", "exec", "time", "nohup", "npx", "bunx", "pnpx", "xargs", "caffeinate"}
# Package runners that take a subcommand before the tool: `pnpm dlx wrangler`, `npm exec wrangler`, `yarn wrangler`.
RUNNERS = {"pnpm": {"dlx", "exec"}, "npm": {"exec", "x"}, "yarn": {"dlx", "exec"}, "bun": {"x"}}
SHELLS = {"sh", "bash", "zsh", "dash", "fish"}

SITE = ("The Bellhop website goes live only through `make site` (scripts/deploy_site.py). Run `make site-check` "
        "first and show Tommy the output, and deploy only when he names production. See AGENTS.md.")
RELEASE = ("Bellhop releases go out only through `make release` (scripts/release.sh). Run `make release-check` first "
           "and show Tommy the output, and release only when he says to. See AGENTS.md.")


def words(argv):
    """The words after the program, without flags (and without the values of `--flag value` pairs we can't tell
    apart, which is fine: subcommands come before those)."""
    return [w for w in argv[1:] if not w.startswith("-")]


def unwrap(argv):
    """Drops leading VAR=value assignments and wrapper commands, so `FOO=1 npx wrangler …` reads as `wrangler …`."""
    while argv:
        head = os.path.basename(argv[0])
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", argv[0]):
            argv = argv[1:]
        elif head in WRAPPERS:
            argv = argv[1:]
            while argv and argv[0].startswith("-"):
                argv = argv[1:]
        elif head in RUNNERS and len(argv) > 1:
            argv = argv[2:] if argv[1] in RUNNERS[head] else argv[1:]
        else:
            return argv
    return argv


def drop_heredocs(command):
    """Removes here-document bodies (a commit message, a Python script) so their text isn't read as commands. A body
    fed to a shell (`bash <<EOF`) is a script, so it stays."""
    kept, end = [], None
    for line in command.split("\n"):
        if end is not None:
            if line.strip() == end:
                end = None
            elif feeds_shell:
                kept.append(line)
            continue
        kept.append(line)
        match = re.search(r"<<-?\s*(['\"]?)(\w+)\1", line)
        if match:
            end = match.group(2)
            feeds_shell = re.search(r"(^|[;&|(]\s*|/)(ba|z|da|fi)?sh\s+(-\w+\s+)*<<", line) is not None
    return "\n".join(kept)


def segments(command):
    """Simple commands in a shell line, split at ; && || | & ( ) and newlines."""
    lexer = shlex.shlex(command.replace("`", " ; ").replace("\n", " ; "), posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    current = []
    for token in lexer:
        if token and set(token) <= set(";&|()<>"):
            if current:
                yield current
            current = []
        elif token != "$":
            current.append(token)
    if current:
        yield current


def reason(command, depth=0):
    """Why `command` is blocked, or None."""
    command = drop_heredocs(command)
    try:
        parts = list(segments(command))
    except ValueError:  # unbalanced quotes: judge the raw text instead
        if re.search(r"wrangler\b.*\bpages\s+(deploy|publish)\b", command):
            return SITE
        if re.search(r"\bgh\s+release\s+(create|upload|edit|delete)\b", command):
            return RELEASE
        return None
    for argv in parts:
        argv = unwrap(argv)
        if not argv:
            continue
        program = os.path.basename(argv[0])
        rest = words(argv)
        if program in SHELLS or program == "eval":
            if program == "eval":
                script = " ".join(argv[1:])
            else:
                script = argv[argv.index("-c") + 1] if "-c" in argv[:-1] else ""
            found = reason(script, depth + 1) if script and depth < 3 else None
            if found:
                return found
        elif program in ("wrangler", "wrangler.js") and "pages" in rest:
            sub = rest[rest.index("pages") + 1:]
            if sub[:1] in (["deploy"], ["publish"]) or sub[:2] == ["deployment", "create"]:
                return SITE
        elif program == "gh" and "release" in rest:
            if rest[rest.index("release") + 1:][:1] in (["create"], ["upload"], ["edit"], ["delete"]):
                return RELEASE
    return None


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return 0
    command = (event.get("tool_input") or {}).get("command") or ""
    found = reason(command)
    if found:
        print(f"Blocked: that's a raw production deploy. {found}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
