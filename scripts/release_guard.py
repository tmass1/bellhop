#!/usr/bin/env python3
"""The live-work check for app releases. scripts/release.sh runs it before building anything that gets published.

    scripts/release_guard.py --version 0.1.5 --check   print every check, ask nothing
    scripts/release_guard.py --version 0.1.5           the same, then the questions and "type release"
    --yes                                              answers them itself: only after Tommy says yes in chat

"Live" for the app is the latest GitHub release: it's what Sparkle offers every copy and what Homebrew installs. A
release built from a branch that's missing that release's commits would ship an update that takes those fixes back out.
"""
import argparse
import json
import subprocess
import sys

from deploylib import REMOTE, Console, Repo, Stop, fail, questions, require_live_work, resolve_live, short

RELEASE_REPO = "tmass1/bellhop"


def latest_release(run=subprocess.run):
    """The tag of the latest published release, or None if there isn't one yet."""
    try:
        result = run(["gh", "release", "view", "--repo", RELEASE_REPO, "--json", "tagName"], capture_output=True,
                     text=True)
    except FileNotFoundError:
        raise Stop("The GitHub command-line tool (gh) isn't installed. Fix: brew install gh, then gh auth login.")
    if result.returncode != 0:
        if "release not found" in result.stderr:
            return None
        raise Stop("Couldn't ask GitHub for the latest release:\n    " + result.stderr.strip()
                   + "\nFix: if it says you're signed out, run `gh auth login` yourself, then run this again.")
    return json.loads(result.stdout)["tagName"]


def tag_commit(repo, tag):
    """The commit GitHub's tag points at (peeled, for annotated tags), as a hash."""
    out = repo.git("ls-remote", REMOTE, f"refs/tags/{tag}", f"refs/tags/{tag}^{{}}", check=False)
    refs = dict(reversed(line.split("\t")) for line in out.splitlines() if "\t" in line)
    sha = refs.get(f"refs/tags/{tag}^{{}}") or refs.get(f"refs/tags/{tag}")
    if not sha:
        raise Stop(f"GitHub says {tag} is the latest release, but it has no {tag} tag to say which commit it was.\n"
                   "Fix: look up the release on GitHub, find its commit, and tag it (git tag <tag> <commit>).")
    return sha


def run(args, repo, console, latest=latest_release):
    out = console.out
    out(f"Bellhop {args.version} → production (GitHub release, Sparkle updates, Homebrew)"
        + ("   [--check: nothing gets built or published]" if args.check else ""))
    out("")

    dirty = repo.uncommitted()
    if dirty:
        raise Stop("These files have changes that aren't committed, and the release would be built from them:\n"
                   + "\n".join(f"    {line}" for line in dirty[:20])
                   + "\nFix: commit them, or put them back, then run this again. Only committed work is released.")
    console.ok("Nothing uncommitted.")

    fetched = repo.fetch()
    tag = latest()
    live = None
    if tag:
        live = resolve_live(repo, tag_commit(repo, tag), f"GitHub's latest release ({tag})", fetched)
        console.ok(f'Live now: {tag}, commit {short(live)} "{repo.subject(live)}".')
        require_live_work(repo, live, f"release {tag}, the live app")
        console.ok(f"This branch already has everything in {tag}.")
    else:
        console.note("No release has been published yet, so there's no live work to lose.")

    asks = questions(repo, fetched, unpushed_is_stop=True)
    if not asks:
        console.ok("On main, everything is pushed, and GitHub has nothing newer.")

    commits = repo.log(f"{live}..HEAD") if live else repo.log("HEAD")
    out(f"\n  What {args.version} adds ({len(commits)} commit(s)" + (f" since {tag}" if tag else "") + "):")
    for line in commits[:30]:
        out(f"    {line}")
    if len(commits) > 30:
        out(f"    … and {len(commits) - 30} more")
    if not commits:
        raise Stop(f"Nothing has changed since {tag}. There's nothing to release.")

    if args.check:
        if asks:
            out("\n  A real release will ask about:")
            for ask in asks:
                out(f"  ? {ask}")
        out(f"\n  Check passed: releasing from here wouldn't take anything out of {tag or 'the app'}.")
        return 0
    out("")
    for ask in asks:
        console.confirm(ask)
    console.type_word("release", f"Ready to build and publish Bellhop {args.version} to everyone.")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description="Check that a release has everything already released.")
    parser.add_argument("--version", required=True)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--yes", action="store_true")
    args = parser.parse_args(argv)
    try:
        return run(args, Repo.here(), Console(assume_yes=args.yes))
    except Stop as stop:
        return fail(stop)
    except KeyboardInterrupt:
        return fail(Stop("Stopped."))


if __name__ == "__main__":
    sys.exit(main())
