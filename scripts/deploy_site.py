#!/usr/bin/env python3
"""The only way to put the Bellhop website (bellhop.pages.dev, on Cloudflare Pages) live. `make site` runs it.

    scripts/deploy_site.py --check   every check, plus a look at the live site; no build and no deploy. Run it first.
    scripts/deploy_site.py           checks, tests, build, type "deploy", deploy, then checks the live site
    scripts/deploy_site.py --yes     answers the questions itself: only after Tommy says yes in chat; never skips a stop
    --live-commit <commit>           names the live commit by hand, when neither Cloudflare nor the site can tell

It deploys the committed site/ folder (never unsaved edits) plus a generated /version.json that names the commit, so
the live site itself says what's on it. docs/DEPLOY.md explains each step and stop in plain language.
"""
import argparse
import datetime
import json
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

from deploylib import MAIN, REPO, Console, Repo, Stop, fail, questions, require_live_work, resolve_live, short

PROJECT = "bellhop"
SITE_URL = "https://bellhop.pages.dev"
SITE_DIR = "site"
# Uncommitted changes here stop the deploy: the site itself and the code that checks and ships it.
BUILD_PATHS = (SITE_DIR, "scripts/deploy_site.py", "scripts/deploylib.py")
# Must never show their real contents on the live site. The site answers unknown paths with the landing page, so
# "hidden" means a 404 or the landing page, nothing else.
HIDDEN = ("/CLAUDE.md", "/AGENTS.md", "/HANDOFF.md", "/README.md", "/docs/PLAN.md", "/docs/DEPLOY.md", "/.git/config",
          "/.git/HEAD", "/.claude/settings.json", "/Makefile", "/scripts/release.sh", "/design/mocks/site.html",
          "/design/mocks/index.html", "/version.json.bak")
# Pages that must stay behind a sign-in. The site has none today; add paths here if that changes.
PRIVATE = ()
# Files that should never be published, whatever folder they end up in.
NEVER_PUBLISH = re.compile(r"(^|/)\.|\.(md|py|sh|swift|env|pem|key|p12)$", re.I)
LINK = re.compile(r"""(?:href|src)\s*=\s*["']([^"']+)["']""", re.I)


# Cloudflare and the web, behind small seams so tests can fake them.

class Cloudflare:
    def run(self, args, capture=True):
        try:
            return subprocess.run(["wrangler", *args], cwd=REPO, capture_output=capture, text=True)
        except FileNotFoundError:
            raise Stop("wrangler (Cloudflare's command-line tool) isn't installed on this Mac.\n"
                       "Fix: brew install cloudflare-wrangler, sign in with `wrangler login`, then run this again.")

    def production_deployments(self):
        """Production deploys, newest first."""
        result = self.run(["pages", "deployment", "list", "--project-name", PROJECT, "--environment", "production",
                           "--json"])
        if result.returncode != 0:
            raise Stop("Couldn't ask Cloudflare what's live:\n    "
                       + (result.stderr or result.stdout).strip().replace("\n", "\n    ")
                       + "\nFix: if it says you're signed out, run `wrangler login` yourself, then run this again.")
        return parse_deployments(result.stdout)

    def deploy(self, directory, commit, message):
        result = self.run(["pages", "deploy", str(directory), "--project-name", PROJECT, "--branch", MAIN,
                           "--commit-hash", commit, "--commit-message", message, "--commit-dirty=false"],
                          capture=False)
        if result.returncode != 0:
            raise Stop("Cloudflare didn't accept the upload (its message is above). The live site hasn't changed.")


def parse_deployments(text):
    """`wrangler pages deployment list --json` output, without any warnings it prints first."""
    start = re.search(r"^\[", text, re.M)
    try:
        data = json.loads(text[start.start():]) if start else None
    except ValueError:
        data = None
    if not isinstance(data, list):
        raise Stop(f"Cloudflare's answer wasn't readable:\n    {text.strip()[:300]}")
    return [d for d in data if d.get("Environment", "Production") == "Production"]


def fetch(url):
    """(status, body, final URL) after redirects; status 0 when the site couldn't be reached."""
    request = urllib.request.Request(url, headers={"Cache-Control": "no-cache", "User-Agent": "bellhop-deploy-check"})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return response.status, response.read(), response.geturl()
    except urllib.error.HTTPError as error:
        return error.code, error.read(), error.geturl()
    except (urllib.error.URLError, TimeoutError, ConnectionError):
        return 0, b"", url


def served_version(get):
    """The live site's /version.json as a dict, or None (sites deployed before this script have none)."""
    status, body, _ = get(f"{SITE_URL}/version.json?t={int(time.time())}")
    if status != 200:
        return None
    try:
        data = json.loads(body)
    except ValueError:
        return None  # the landing page, served for any unknown path
    return data if isinstance(data, dict) and isinstance(data.get("commit"), str) else None


# The steps.

def find_live(repo, cloudflare, get, named, fetched, console):
    """Every commit that counts as live, as {full hash: where it came from}, and Cloudflare's current deploy.

    Cloudflare's latest production deploy and the site's /version.json usually agree. They differ after a rollback in
    the dashboard; then the branch has to contain both, which is the safe side.
    """
    live = {}
    deployments = cloudflare.production_deployments()
    current = deployments[0] if deployments else None
    if current and current.get("Source"):
        live[resolve_live(repo, current["Source"], "Cloudflare", fetched)] = \
            f"Cloudflare's latest production deploy, {current.get('Status', 'date unknown')}"
    served = served_version(get)
    if served:
        live.setdefault(resolve_live(repo, served["commit"], "The live site's /version.json", fetched),
                        "the live site's /version.json")
    if named:
        live.setdefault(resolve_live(repo, named, "--live-commit", fetched), "named with --live-commit")
    if not live:
        if not deployments:
            console.note("Nothing has been deployed to production yet, so there's no live work to lose.")
            return live, None
        raise Stop("Can't tell which commit is live: Cloudflare didn't record one and the site has no /version.json.\n"
                   "Fix: look up the live deploy in the Cloudflare dashboard "
                   f"({current.get('Build', 'Pages › bellhop')}), find the commit it came from, and run this again "
                   "with --live-commit <commit>.")
    for full, where in live.items():
        console.ok(f'Live now: commit {short(full)} "{repo.subject(full)}" ({where}).')
    return live, current


def export_site(repo, commit, dest):
    """The committed site/ folder at `commit`, written to `dest`. Unsaved edits on disk never reach it."""
    archive = subprocess.run(["git", "archive", "--format=tar", f"{commit}:{SITE_DIR}"], cwd=repo.path,
                             capture_output=True, check=True)
    subprocess.run(["tar", "-x", "-C", str(dest)], input=archive.stdout, check=True)
    return Path(dest)


def validate_site(directory):
    """Problems that would make the live site broken or leak something: a missing page or image, or a file that
    shouldn't be public."""
    directory = Path(directory)
    problems = []
    if not (directory / "index.html").is_file():
        problems.append("site/index.html is missing")
    for path in sorted(p for p in directory.rglob("*") if p.is_file()):
        rel = path.relative_to(directory).as_posix()
        if NEVER_PUBLISH.search(rel):
            problems.append(f"site/{rel} shouldn't be published (hidden file, notes or code)")
        if path.suffix.lower() not in (".html", ".css"):
            continue
        for url in LINK.findall(path.read_text(errors="replace")):
            if re.match(r"^(?:[a-z][a-z0-9+.-]*:|//|#)", url, re.I):
                continue  # another site, mailto:, data:, or a spot on this page
            target_path = url.split("#")[0].split("?")[0]
            if not target_path:
                continue
            target = directory / target_path.lstrip("/") if target_path.startswith("/") else path.parent / target_path
            if target.is_dir():
                target = target / "index.html"
            if not target.resolve().is_file() or directory.resolve() not in target.resolve().parents:
                problems.append(f"site/{rel} links to {url}, which isn't in the site")
    return problems


def run_tests(console):
    result = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "scripts/tests", "-t", "scripts"],
                            cwd=REPO, capture_output=True, text=True)
    summary = (result.stderr.strip().splitlines() or ["(no output)"])
    if result.returncode != 0:
        raise Stop("The deploy script's own tests failed:\n    " + result.stderr.strip().replace("\n", "\n    "))
    ran = next((line for line in summary if line.startswith("Ran ")), "tests ran")
    console.ok(f"Deploy tests pass ({ran.removeprefix('Ran ').split(' in ')[0]}).")


def site_url(rel):
    """The address Cloudflare serves a file at: it drops index.html and .html."""
    if rel == "index.html" or rel.endswith("/index.html"):
        return f"{SITE_URL}/{rel.removesuffix('index.html')}"
    return f"{SITE_URL}/{rel.removesuffix('.html')}"


def check_live_site(get, console, built=None, commit=None, sleep=time.sleep, wait=150):
    """Public pages load (and match what was built), hidden paths show nothing real, private pages stay private.

    Returns the problems found; an empty list means all good.
    """
    problems = []
    if commit:
        deadline = time.monotonic() + wait
        while (served_version(get) or {}).get("commit") != commit:
            if time.monotonic() > deadline:
                problems.append(f"/version.json still doesn't show {short(commit)} after {wait} s")
                break
            sleep(5)
        else:
            console.ok(f"/version.json shows {short(commit)}: the new version is live.")
    status, landing, _ = get(f"{SITE_URL}/")
    public = [] if status == 200 else [f"the landing page answers {status or 'nothing'}"]
    files = [p for p in sorted(Path(built).rglob("*")) if p.is_file() and p.name != "version.json"] if built else []
    for path in files:
        rel = path.relative_to(built).as_posix()
        status, body, _ = get(site_url(rel))
        if status != 200:
            public.append(f"/{rel} answers {status or 'nothing'}")
        elif body != path.read_bytes():
            public.append(f"/{rel} doesn't match what was built")
    problems += public
    if not public:
        names = ", ".join(f"/{p.relative_to(built).as_posix()}" for p in files) if built else "/"
        console.ok(f"Public pages load: {names}.")
    leaks = []
    for path in HIDDEN:
        status, body, _ = get(f"{SITE_URL}{path}")
        if status == 200 and body != landing:
            leaks.append(path)
    problems += [f"{path} shows something other than the landing page; it should stay hidden" for path in leaks]
    if not leaks:
        console.ok(f"Hidden stays hidden: {len(HIDDEN)} private paths (CLAUDE.md, .git, docs, mocks…) only show the "
                   "landing page.")
    for path in PRIVATE:
        status, _, final = get(f"{SITE_URL}{path}")
        if status not in (401, 403) and final == f"{SITE_URL}{path}":
            problems.append(f"{path} should need a sign-in but answered {status}")
    if not PRIVATE:
        console.note("Private pages: none on this site (nothing on it needs a sign-in).")
    return problems


def show_changes(repo, base, console):
    """What this deploy adds on top of what's live."""
    out = console.out
    if base is None:
        out("\n  What this deploy adds: the whole site (nothing is live yet).")
        return
    commits = repo.log(f"{base}..HEAD", paths=(SITE_DIR,))
    if not commits:
        out(f"\n  What this deploy adds: nothing in site/ has changed since the live version ({short(base)}).")
        out("    Deploying would only add /version.json, which records the commit.")
        return
    out(f"\n  What this deploy adds ({len(commits)} commit(s) that touch site/, since {short(base)}):")
    for line in commits:
        out(f"    {line}")
    for line in repo.git("diff", "--stat", base, "HEAD", "--", SITE_DIR).splitlines():
        out(f"    {line}")


def run(args, repo, cloudflare, get, console, tests=run_tests, sleep=time.sleep):
    out = console.out
    out(f"Bellhop website → production ({SITE_URL})" + ("   [--check: nothing gets built or deployed]"
                                                        if args.check else ""))
    out("")

    # 1. Only committed work goes live.
    dirty = repo.uncommitted(BUILD_PATHS)
    if dirty:
        raise Stop("These files go into the site (or check it) and have changes that aren't committed:\n"
                   + "\n".join(f"    {line}" for line in dirty)
                   + "\nFix: commit them, or put them back, then run this again. Only committed work is deployed.")
    console.ok("Nothing uncommitted in site/ or the deploy scripts.")

    # 2. What's live, and 3. does this branch have all of it?
    fetched = repo.fetch()
    live, current = find_live(repo, cloudflare, get, args.live_commit, fetched, console)
    for commit in live:
        require_live_work(repo, commit, "the live website")
    if live:
        console.ok("This branch already has everything that's live.")

    # 4. Things that need a yes.
    asks = questions(repo, fetched)
    if not asks:
        console.ok("On main, everything is pushed, and GitHub has nothing newer.")

    # 5. Tests and the site check.
    tests(console)
    head = repo.head()
    with tempfile.TemporaryDirectory(prefix="bellhop-site-") as scratch:
        problems = validate_site(export_site(repo, head, scratch))
    if problems:
        raise Stop("The site check found problems:\n" + "\n".join(f"    {p}" for p in problems))
    console.ok("Site check: index.html is there, every link and image points at a real file, nothing private.")

    # 6. What it adds.
    base = next(iter(live), None)  # Cloudflare's latest deploy when it has one
    show_changes(repo, base, console)

    if args.check:
        out("\n  The live site right now:")
        problems = check_live_site(get, console)
        for problem in problems:
            out(f"  ✗ {problem}")
        if asks:
            out("\n  A real deploy will ask about:")
            for ask in asks:
                out(f"  ? {ask}")
        out("\n  Check passed: a deploy from here wouldn't remove anything that's live.")
        out("  To deploy: make site (it asks you to type \"deploy\" before anything goes live).")
        return 1 if problems else 0

    out("")
    for ask in asks:
        console.confirm(ask)
    branch = repo.branch() or "detached"
    with tempfile.TemporaryDirectory(prefix="bellhop-site-") as scratch:
        built = export_site(repo, head, scratch)
        (built / "version.json").write_text(json.dumps({
            "commit": head, "branch": branch,
            "deployedAt": datetime.datetime.now(datetime.UTC).replace(microsecond=0).isoformat()}, indent=2) + "\n")
        console.ok(f"Built commit {short(head)} from {branch}: the committed site/ folder plus /version.json.")
        out("")
        console.type_word("deploy", f"Ready to put {short(head)} live on {SITE_URL}.")

        # 7. Deploy, with the commit and branch recorded in Cloudflare.
        message = f"{repo.subject(head)} [{branch}]"[:200]
        cloudflare.deploy(built, head, message)

        # 8. Check the live site.
        out("\n  Checking the live site:")
        problems = check_live_site(get, console, built=built, commit=head, sleep=sleep)

    # 9. Rollback and to-dos.
    for problem in problems:
        out(f"  ✗ {problem}")
    out("\n  To roll back:" if not problems else "\n  SOMETHING LOOKS WRONG. Roll back now:")
    if current:
        out(f"    Open {current.get('Build')}")
        out(f"    (the deploy that was live before, commit {current.get('Source')}), then ⋯ → Rollback to this "
            "deployment.")
        out("    The old version is back within a minute. Git doesn't change: fix forward with a new commit and "
            "deploy again.")
    else:
        out("    This was the first deploy. To take it down, use the Cloudflare dashboard (Pages › bellhop).")
    out("\n  To do:")
    out("    • Release note: if this goes with an app version, mention it in docs/releases/<version>.md.")
    if branch != MAIN:
        out(f"    • Merge {branch} into main: this went live from a side branch, and main doesn't have it yet.")
    if repo.log("HEAD", "--not", "--remotes=origin"):
        out("    • Push to GitHub when Tommy says (git push), so other copies get this commit.")
    return 1 if problems else 0


def main(argv=None):
    parser = argparse.ArgumentParser(description="Deploy the Bellhop website to production, safely.")
    parser.add_argument("--check", action="store_true", help="run every check; build and deploy nothing")
    parser.add_argument("--yes", action="store_true", help="answer yes to the questions (only after a yes in chat)")
    parser.add_argument("--live-commit", metavar="COMMIT", help="the live commit, when Cloudflare can't tell")
    args = parser.parse_args(argv)
    try:
        return run(args, Repo.here(), Cloudflare(), fetch, Console(assume_yes=args.yes))
    except Stop as stop:
        return fail(stop)
    except KeyboardInterrupt:
        return fail(Stop("Stopped."))


if __name__ == "__main__":
    sys.exit(main())
