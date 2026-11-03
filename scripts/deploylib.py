"""Checks shared by Bellhop's two production deploys: the website (scripts/deploy_site.py) and app releases
(scripts/release_guard.py, run by scripts/release.sh).

The one mistake they guard against: shipping from a branch, checkout or Mac that's missing work already live, which
would quietly take that work back out. docs/DEPLOY.md explains each stop in plain language.
"""
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
MAIN = "main"
REMOTE = "origin"


class Stop(Exception):
    """A reason the deploy can't go ahead. Nothing skips it, --yes included: fix the cause and run again."""


class Repo:
    def __init__(self, path=REPO):
        self.path = Path(path)

    @classmethod
    def here(cls):
        """The checkout the command is run from (a worktree checks itself), else the one holding these scripts."""
        top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip()
        return cls(top or REPO)

    def git(self, *args, check=True):
        result = subprocess.run(["git", *args], cwd=self.path, capture_output=True, text=True)
        if check and result.returncode != 0:
            raise RuntimeError(f"git {' '.join(args)} failed: {result.stderr.strip()}")
        return result.stdout.strip()

    def head(self):
        return self.git("rev-parse", "HEAD")

    def branch(self):
        """The checked-out branch, or None when HEAD is detached."""
        return self.git("symbolic-ref", "--short", "-q", "HEAD", check=False) or None

    def resolve(self, rev):
        """The full hash for a commit (short hashes and tags work), or None if this copy doesn't have it."""
        return self.git("rev-parse", "--verify", "--quiet", f"{rev}^{{commit}}", check=False) or None

    def contains(self, ancestor, descendant="HEAD"):
        return subprocess.run(["git", "merge-base", "--is-ancestor", ancestor, descendant], cwd=self.path,
                              capture_output=True).returncode == 0

    def log(self, *revs, paths=()):
        """One line per commit: short hash and subject, newest first."""
        out = self.git("log", "--format=%h %s", *revs, "--", *paths)
        return out.splitlines() if out else []

    def subject(self, rev):
        return self.git("log", "-1", "--format=%s", rev)

    def branches_containing(self, commit):
        out = self.git("branch", "-a", "--format=%(refname:short)", "--contains", commit, check=False)
        return [b for b in out.splitlines() if b and not b.endswith("/HEAD") and b != REMOTE]

    def uncommitted(self, paths=()):
        """Changed, staged or new (not ignored) files, as `git status --short` lines."""
        out = self.git("status", "--porcelain", "--untracked-files=all", "--", *paths)
        return out.splitlines() if out else []

    def fetch(self):
        """Fetches from GitHub without changing any branch here. False when GitHub couldn't be reached."""
        return subprocess.run(["git", "fetch", "--quiet", "--tags", REMOTE], cwd=self.path,
                              capture_output=True).returncode == 0


def short(sha):
    return sha[:7]


def best_branch(branches):
    """The branch to suggest merging from: main first, then a local branch, then anything."""
    for name in (MAIN, f"{REMOTE}/{MAIN}"):
        if name in branches:
            return name
    local = [b for b in branches if "/" not in b]
    return (local or branches or [None])[0]


def require_live_work(repo, live, what):
    """Stops unless HEAD already contains `live` (a full hash), the commit `what` describes, e.g. "the live website".

    Lists the commits that would be lost and the branch to merge them from.
    """
    if repo.contains(live):
        return
    missing = repo.log(f"HEAD..{live}")
    holder = best_branch(repo.branches_containing(live))
    lines = [f"This branch is missing work that's already in {what} (commit {short(live)}).",
             f"Shipping from here would take these {len(missing)} commit(s) back out:"]
    lines += [f"    {c}" for c in missing[:20]]
    if len(missing) > 20:
        lines.append(f"    … and {len(missing) - 20} more")
    if holder:
        lines.append(f"Fix: merge {holder} into this branch (git merge {holder}), then run this again.")
    else:
        lines.append(f"Fix: no branch here has that commit any more. Merge it directly (git merge {short(live)}), "
                     "then run this again.")
    raise Stop("\n".join(lines))


def resolve_live(repo, sha, where, fetched):
    """The full hash for a live commit reported by `where`; stops if this copy has never seen it."""
    full = repo.resolve(sha)
    if full:
        return full
    hint = "" if fetched else " (GitHub couldn't be reached just now, so this copy may simply be out of date)"
    raise Stop(f"{where} says commit {sha} is live, but this copy doesn't have that commit{hint}.\n"
               "It was probably deployed from another branch, checkout or Mac that hasn't pushed it.\n"
               "Fix: push that work to GitHub from wherever it was deployed, then run this again here "
               "(it fetches from GitHub on its own).")


def questions(repo, fetched, unpushed_is_stop=False):
    """Things that need a yes before going ahead: not on main, commits GitHub doesn't have, GitHub ahead of here.

    With `unpushed_is_stop`, commits GitHub doesn't have stop the run instead (app releases tag the commit on GitHub,
    so it has to be there).
    """
    asks = []
    branch = repo.branch()
    if branch is None:
        asks.append("This copy isn't on any branch (a detached HEAD). Production normally ships from main.")
    elif branch != MAIN:
        asks.append(f'You\'re on branch "{branch}", not main. Production normally ships from main; afterwards '
                    f"{branch} needs merging into main.")
    if not fetched:
        asks.append("GitHub couldn't be reached, so this can't check for newer work there.")
    unpushed = repo.log("HEAD", "--not", f"--remotes={REMOTE}")
    if unpushed:
        text = f"{len(unpushed)} commit(s) here aren't on GitHub yet:\n" + "\n".join(f"    {c}" for c in unpushed[:10])
        if unpushed_is_stop:
            raise Stop(text + "\nFix: push them first (git push), once Tommy says to.")
        asks.append(text + "\n  They'll go live from this Mac only; push them afterwards when Tommy says.")
    if repo.resolve(f"{REMOTE}/{MAIN}"):
        ahead = repo.log(f"HEAD..{REMOTE}/{MAIN}")
        if ahead:
            asks.append(f"GitHub's main has {len(ahead)} commit(s) this copy doesn't:\n"
                        + "\n".join(f"    {c}" for c in ahead[:10])
                        + "\n  They aren't live yet, so nothing is lost, but they won't be in this deploy either.")
    return asks


class Console:
    """Plain-language output plus the yes/no and typed confirmations. `assume_yes` is --yes: only after a yes in
    chat, and it never skips a Stop."""

    def __init__(self, assume_yes=False, out=print, ask=input, interactive=None):
        self.assume_yes = assume_yes
        self.out = out
        self.ask = ask
        self.interactive = sys.stdin.isatty() if interactive is None else interactive

    def ok(self, text):
        self.out(f"  ✓ {text}")

    def note(self, text):
        self.out(f"  · {text}")

    def confirm(self, text):
        self.out(f"  ? {text}")
        if self.assume_yes:
            self.out("    → yes (--yes)")
            return
        if not self.interactive:
            raise Stop("This needs a yes, and there's no one at the keyboard to give it. Run it in Terminal, or "
                       "pass --yes once Tommy has said yes in chat.")
        if self.ask("    Go ahead? [y/N] ").strip().lower() not in ("y", "yes"):
            raise Stop("Stopped: you said no.")

    def type_word(self, word, prompt):
        if self.assume_yes:
            self.out(f'  {prompt} → "{word}" (--yes)')
            return
        if not self.interactive:
            raise Stop(f'This needs you to type "{word}". Run it in Terminal, or pass --yes once Tommy has said yes '
                       "in chat.")
        if self.ask(f'  {prompt} Type "{word}" to go ahead: ').strip() != word:
            raise Stop("Stopped: nothing was deployed.")


def fail(stop):
    """Prints a Stop and returns the exit code for it."""
    print("\n  STOP")
    for line in str(stop).splitlines():
        print(f"    {line}")
    print("\n  Nothing was deployed or published. docs/DEPLOY.md explains each stop.")
    return 1
