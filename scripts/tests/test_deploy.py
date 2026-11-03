"""Tests for the production deploy checks (scripts/deploylib.py, deploy_site.py, release_guard.py).

Each test builds a throwaway git repo with a local "GitHub" (a bare repo as origin) and fakes Cloudflare and the web,
so nothing here touches the network or the real site.
"""
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import deploy_site  # noqa: E402
import release_guard  # noqa: E402
from deploylib import Console, Repo, Stop, questions, require_live_work, resolve_live  # noqa: E402

LANDING = b"<!doctype html><title>Bellhop</title><img src=\"assets/logo.svg\">"


def sh(cwd, *args):
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


class Fixture(unittest.TestCase):
    """A repo whose main has the site (commit `live`), pushed to a local origin."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="bellhop-deploy-test-"))
        self.addCleanup(shutil.rmtree, self.tmp)
        sh(self.tmp, "git", "init", "-q", "--bare", "-b", "main", "origin.git")
        self.work = self.tmp / "work"
        sh(self.tmp, "git", "init", "-q", "-b", "main", "work")
        for key, value in (("user.email", "test@example.com"), ("user.name", "Test"), ("commit.gpgsign", "false"),
                           ("tag.gpgsign", "false")):
            self.git("config", key, value)
        self.write("site/index.html", LANDING)
        self.write("site/assets/logo.svg", b"<svg/>")
        self.live = self.commit("Add the site")
        self.git("remote", "add", "origin", str(self.tmp / "origin.git"))
        self.git("push", "-q", "-u", "origin", "main")
        self.repo = Repo(self.work)
        self.lines = []

    def git(self, *args):
        return sh(self.work, "git", *args)

    def write(self, rel, data):
        path = self.work / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def commit(self, message, rel=None, data=b"x"):
        if rel:
            self.write(rel, data)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)
        return self.git("rev-parse", "HEAD")

    def console(self, yes=True, interactive=False, answers=()):
        answers = list(answers)
        return Console(assume_yes=yes, out=self.lines.append, ask=lambda _: answers.pop(0), interactive=interactive)

    def output(self):
        return "\n".join(self.lines)


class FakeCloudflare:
    def __init__(self, source=None, deployments=None):
        self.deployments = deployments if deployments is not None else [
            {"Id": "abc", "Environment": "Production", "Branch": "main", "Source": source[:7], "Status": "1 day ago",
             "Build": "https://dash.example/abc"}]
        self.deployed = None

    def production_deployments(self):
        return self.deployments

    def deploy(self, directory, commit, message):
        files = {p.relative_to(directory).as_posix(): p.read_bytes() for p in Path(directory).rglob("*") if p.is_file()}
        self.deployed = {"files": files, "commit": commit, "message": message}


class FakeWeb:
    """The live site: serves `files`, and the landing page for any unknown path (as Cloudflare Pages does)."""

    def __init__(self, cloudflare=None, files=None):
        self.cloudflare = cloudflare
        self.files = files if files is not None else {"index.html": LANDING, "assets/logo.svg": b"<svg/>"}
        self.extra = {}

    def __call__(self, url):
        path = url.removeprefix(deploy_site.SITE_URL + "/").split("?")[0]
        files = self.cloudflare.deployed["files"] if self.cloudflare and self.cloudflare.deployed else self.files
        if path in self.extra:
            return 200, self.extra[path], url
        if path in ("", "index"):
            path = "index.html"
        return 200, files.get(path, files["index.html"]), url


def args(**kw):
    return Namespace(**{"check": False, "yes": True, "live_commit": None, **kw})


def no_tests(console):
    console.ok("tests skipped")


class LiveWorkTests(Fixture):
    def test_passes_when_branch_has_live_commit(self):
        self.commit("More", "site/new.txt")
        require_live_work(self.repo, self.live, "the live website")

    def test_stops_and_names_missing_commits_and_branch_to_merge(self):
        self.git("checkout", "-q", "-b", "old", "HEAD~0")
        self.git("checkout", "-q", "main")
        newer = self.commit("Fix the headline", "site/index.html", b"<html>new</html>")
        self.git("checkout", "-q", "old")
        self.git("reset", "-q", "--hard", self.live)
        with self.assertRaises(Stop) as stop:
            require_live_work(self.repo, newer, "the live website")
        text = str(stop.exception)
        self.assertIn("Fix the headline", text)
        self.assertIn("git merge main", text)

    def test_unknown_live_commit_stops_with_push_instructions(self):
        with self.assertRaises(Stop) as stop:
            resolve_live(self.repo, "deadbee", "Cloudflare", fetched=True)
        self.assertIn("push that work", str(stop.exception))


class QuestionTests(Fixture):
    def test_main_and_pushed_needs_no_questions(self):
        self.assertEqual(questions(self.repo, fetched=True), [])

    def test_side_branch_asks(self):
        self.git("checkout", "-q", "-b", "headline")
        asks = questions(self.repo, fetched=True)
        self.assertTrue(any('"headline", not main' in a for a in asks))

    def test_unpushed_commits_ask_or_stop(self):
        self.commit("Local only", "site/x.txt")
        self.assertTrue(any("aren't on GitHub" in a for a in questions(self.repo, fetched=True)))
        with self.assertRaises(Stop):
            questions(self.repo, fetched=True, unpushed_is_stop=True)

    def test_github_ahead_asks(self):
        self.commit("Pushed later", "site/x.txt")
        self.git("push", "-q")
        self.git("reset", "-q", "--hard", "HEAD~1")
        asks = questions(self.repo, fetched=True)
        self.assertTrue(any("GitHub's main has 1 commit" in a for a in asks))

    def test_offline_asks(self):
        self.assertTrue(any("couldn't be reached" in a for a in questions(self.repo, fetched=False)))


class ConsoleTests(Fixture):
    def test_no_keyboard_and_no_yes_stops(self):
        with self.assertRaises(Stop):
            self.console(yes=False).confirm("On a side branch.")
        with self.assertRaises(Stop):
            self.console(yes=False).type_word("deploy", "Ready.")

    def test_typed_word_must_match(self):
        with self.assertRaises(Stop):
            self.console(yes=False, interactive=True, answers=["Deploy"]).type_word("deploy", "Ready.")
        self.console(yes=False, interactive=True, answers=["deploy"]).type_word("deploy", "Ready.")

    def test_saying_no_stops(self):
        with self.assertRaises(Stop):
            self.console(yes=False, interactive=True, answers=["n"]).confirm("On a side branch.")


class SiteTests(Fixture):
    def test_good_site_passes(self):
        self.assertEqual(deploy_site.validate_site(self.work / "site"), [])

    def test_broken_link_and_private_files_are_problems(self):
        self.write("site/index.html", b'<a href="docs/guide.html">x</a><img src="/assets/missing.png">')
        self.write("site/NOTES.md", b"secret")
        self.write("site/.env", b"KEY=1")
        problems = "\n".join(deploy_site.validate_site(self.work / "site"))
        self.assertIn("docs/guide.html", problems)
        self.assertIn("missing.png", problems)
        self.assertIn("NOTES.md", problems)
        self.assertIn(".env", problems)

    def test_links_outside_the_site_are_problems(self):
        self.write("site/index.html", b'<img src="../CLAUDE.md">')
        self.write("CLAUDE.md", b"x")
        self.assertTrue(deploy_site.validate_site(self.work / "site"))

    def test_export_takes_committed_files_only(self):
        self.write("site/index.html", b"unsaved edit")
        out = self.tmp / "out"
        out.mkdir()
        deploy_site.export_site(self.repo, "HEAD", out)
        self.assertEqual((out / "index.html").read_bytes(), LANDING)

    def test_parse_deployments_skips_warnings_and_previews(self):
        text = "▲ [WARNING] update available\n" + json.dumps([
            {"Environment": "Production", "Source": "aaaaaaa"}, {"Environment": "Preview", "Source": "bbbbbbb"}])
        self.assertEqual([d["Source"] for d in deploy_site.parse_deployments(text)], ["aaaaaaa"])

    def test_served_version_ignores_the_landing_page(self):
        self.assertIsNone(deploy_site.served_version(FakeWeb()))
        web = FakeWeb()
        web.extra["version.json"] = json.dumps({"commit": self.live}).encode()
        self.assertEqual(deploy_site.served_version(web)["commit"], self.live)

    def test_hidden_path_with_real_content_is_a_problem(self):
        web = FakeWeb()
        web.extra["CLAUDE.md"] = b"# Bellhop project guide"
        problems = deploy_site.check_live_site(web, self.console())
        self.assertTrue(any("/CLAUDE.md" in p for p in problems))
        self.assertEqual(deploy_site.check_live_site(FakeWeb(), self.console()), [])

    def test_site_urls(self):
        self.assertEqual(deploy_site.site_url("index.html"), deploy_site.SITE_URL + "/")
        self.assertEqual(deploy_site.site_url("docs/index.html"), deploy_site.SITE_URL + "/docs/")
        self.assertEqual(deploy_site.site_url("about.html"), deploy_site.SITE_URL + "/about")
        self.assertEqual(deploy_site.site_url("assets/a.svg"), deploy_site.SITE_URL + "/assets/a.svg")


class DeploySiteRunTests(Fixture):
    def run_site(self, cloudflare, web=None, **kw):
        return deploy_site.run(args(**kw), self.repo, cloudflare, web or FakeWeb(cloudflare), self.console(),
                               tests=no_tests, sleep=lambda _: None)

    def test_check_passes_and_deploys_nothing(self):
        self.commit("New headline", "site/index.html", LANDING + b"<h1>New</h1>")
        self.git("push", "-q")
        cloudflare = FakeCloudflare(self.live)
        self.assertEqual(self.run_site(cloudflare, check=True), 0)
        self.assertIsNone(cloudflare.deployed)
        self.assertIn("New headline", self.output())
        self.assertIn("Check passed", self.output())

    def test_deploy_ships_committed_site_with_version_json(self):
        head = self.commit("New headline", "site/index.html", LANDING + b"<h1>New</h1>")
        self.git("push", "-q")
        cloudflare = FakeCloudflare(self.live)
        self.assertEqual(self.run_site(cloudflare), 0, self.output())
        deployed = cloudflare.deployed
        self.assertEqual(deployed["commit"], head)
        self.assertIn("[main]", deployed["message"])
        self.assertEqual(json.loads(deployed["files"]["version.json"])["commit"], head)
        self.assertIn("Rollback", self.output())

    def test_branch_missing_live_work_stops_before_anything(self):
        newer = self.commit("Fix the headline", "site/index.html", LANDING + b"<h1>Fixed</h1>")
        self.git("push", "-q")
        self.git("checkout", "-q", "-b", "old-copy", self.live)
        cloudflare = FakeCloudflare(newer)
        with self.assertRaises(Stop) as stop:
            self.run_site(cloudflare)
        self.assertIn("Fix the headline", str(stop.exception))
        self.assertIsNone(cloudflare.deployed)

    def test_version_json_counts_as_live_too(self):
        newer = self.commit("Rolled back later", "site/index.html", LANDING + b"<h1>B</h1>")
        self.git("push", "-q")
        self.git("checkout", "-q", "-b", "old-copy", self.live)
        web = FakeWeb()
        web.extra["version.json"] = json.dumps({"commit": newer}).encode()
        with self.assertRaises(Stop):
            self.run_site(FakeCloudflare(self.live), web=web, check=True)

    def test_uncommitted_site_change_stops(self):
        self.write("site/index.html", b"unsaved")
        with self.assertRaises(Stop) as stop:
            self.run_site(FakeCloudflare(self.live), check=True)
        self.assertIn("site/index.html", str(stop.exception))

    def test_unknown_live_commit_needs_live_commit_flag(self):
        cloudflare = FakeCloudflare(deployments=[{"Environment": "Production", "Source": "", "Build": "x"}])
        with self.assertRaises(Stop) as stop:
            self.run_site(cloudflare, check=True)
        self.assertIn("--live-commit", str(stop.exception))
        self.assertEqual(self.run_site(cloudflare, check=True, live_commit=self.live[:7]), 0)

    def test_side_branch_without_yes_stops_at_the_question(self):
        self.git("checkout", "-q", "-b", "headline")
        self.commit("Side change", "site/index.html", LANDING + b"<p>side</p>")
        cloudflare = FakeCloudflare(self.live)
        with self.assertRaises(Stop):
            deploy_site.run(args(yes=False), self.repo, cloudflare, FakeWeb(cloudflare), self.console(yes=False),
                            tests=no_tests)
        self.assertIsNone(cloudflare.deployed)


class ReleaseGuardTests(Fixture):
    def setUp(self):
        super().setUp()
        self.git("tag", "v0.1.0")
        self.git("push", "-q", "origin", "v0.1.0")

    def run_guard(self, **kw):
        return release_guard.run(Namespace(version="0.1.1", check=kw.pop("check", True), yes=True), self.repo,
                                 self.console(), latest=lambda: "v0.1.0")

    def test_new_work_on_main_passes(self):
        self.commit("Fix a crash", "Sources/a.swift")
        self.git("push", "-q")
        self.assertEqual(self.run_guard(), 0)
        self.assertIn("Fix a crash", self.output())

    def test_branch_missing_released_work_stops(self):
        self.git("checkout", "-q", "-b", "old", "HEAD~0")
        self.git("reset", "-q", "--hard", "HEAD")
        self.git("checkout", "-q", "main")
        self.commit("Released fix", "Sources/a.swift")
        self.git("push", "-q")
        self.git("tag", "-f", "v0.1.0")
        self.git("push", "-q", "-f", "origin", "v0.1.0")
        self.git("checkout", "-q", "old")
        self.commit("Other work", "Sources/b.swift")
        with self.assertRaises(Stop) as stop:
            self.run_guard()
        self.assertIn("Released fix", str(stop.exception))

    def test_unpushed_commits_stop_a_release(self):
        self.commit("Not pushed", "Sources/a.swift")
        with self.assertRaises(Stop):
            self.run_guard()

    def test_nothing_new_stops(self):
        with self.assertRaises(Stop):
            self.run_guard()

    def test_uncommitted_changes_stop(self):
        self.write("Sources/a.swift", b"edit")
        with self.assertRaises(Stop):
            self.run_guard()


if __name__ == "__main__":
    unittest.main()
