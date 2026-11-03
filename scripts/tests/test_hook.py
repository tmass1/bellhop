"""Tests for .claude/hooks/block_raw_deploy.py: raw production deploys are blocked, everything else runs."""
import importlib.util
import json
import subprocess
import sys
import unittest
from pathlib import Path

HOOK = Path(__file__).resolve().parents[2] / ".claude" / "hooks" / "block_raw_deploy.py"
spec = importlib.util.spec_from_file_location("block_raw_deploy", HOOK)
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)

BLOCKED_SITE = [
    "wrangler pages deploy site --project-name bellhop --branch main --commit-dirty=true",
    "npx wrangler pages deploy site --project-name bellhop",
    "cd ~/Dropbox/Claude/Valet && CLOUDFLARE_ACCOUNT_ID=1 npx wrangler pages deploy site",
    "pnpm dlx wrangler pages publish site",
    "/opt/homebrew/bin/wrangler pages deploy /tmp/site",
    "wrangler --cwd site pages deploy .",
    "wrangler pages deployment create site",
    'bash -c "wrangler pages deploy site"',
    "zsh -c 'cd x; npx wrangler pages deploy site'",
    "echo start; wrangler pages deploy site | tee log",
    "echo $(wrangler pages deploy site)",
    "echo `wrangler pages deploy site`",
    'wrangler pages deploy "site',  # unbalanced quote
    "bash <<'EOF'\nwrangler pages deploy site\nEOF",  # a here-document fed to a shell is a script
    "cat notes.txt; zsh -s <<EOF\nnpx wrangler pages deploy site\nEOF",
]
BLOCKED_RELEASE = [
    "gh release create v0.1.5 dist/Bellhop.zip --repo tmass1/bellhop",
    "gh release upload v0.1.4 dist/appcast.xml --clobber",
    "gh release edit v0.1.3 --latest",
    "gh release delete v0.1.4 --yes",
    "gh -R tmass1/bellhop release create v1",
]
ALLOWED = [
    "make site",
    "make site-check",
    "scripts/deploy_site.py --check",
    "python3 scripts/deploy_site.py --yes",
    "make release-check",
    "scripts/release.sh --check",
    "wrangler pages deployment list --project-name bellhop --json",
    "wrangler pages project list",
    "gh release view --repo tmass1/bellhop",
    "gh release list",
    'grep -n "wrangler pages deploy" Makefile',
    'git commit -m "Stop using wrangler pages deploy by hand"',
    "echo wrangler pages deploy",
    "rg 'gh release create' scripts",
    # Here-document bodies are text (a commit message, a script), even with an apostrophe that leaves a quote open.
    "git commit -q -F - <<'EOF'\nShip only what's live\n\nThe hook blocks wrangler pages deploy and gh release create."
    "\nEOF",
    "python3 - <<'EOF'\nprint('wrangler pages deploy')\nEOF\necho done",
    "",
]


class HookTests(unittest.TestCase):
    def test_raw_site_deploys_are_blocked(self):
        for command in BLOCKED_SITE:
            with self.subTest(command=command):
                self.assertEqual(hook.reason(command), hook.SITE)

    def test_raw_releases_are_blocked(self):
        for command in BLOCKED_RELEASE:
            with self.subTest(command=command):
                self.assertEqual(hook.reason(command), hook.RELEASE)

    def test_everything_else_runs(self):
        for command in ALLOWED:
            with self.subTest(command=command):
                self.assertIsNone(hook.reason(command))

    def run_hook(self, command):
        event = json.dumps({"tool_name": "Bash", "tool_input": {"command": command}})
        return subprocess.run([sys.executable, str(HOOK)], input=event, capture_output=True, text=True)

    def test_blocking_exits_2_and_points_to_the_safe_command(self):
        result = self.run_hook("npx wrangler pages deploy site --project-name bellhop")
        self.assertEqual(result.returncode, 2)
        self.assertIn("make site", result.stderr)

    def test_allowed_exits_0_quietly(self):
        result = self.run_hook("make site-check")
        self.assertEqual((result.returncode, result.stderr), (0, ""))

    def test_settings_run_the_hook_for_bash(self):
        settings = json.loads((HOOK.parent.parent / "settings.json").read_text())
        entry = settings["hooks"]["PreToolUse"][0]
        self.assertEqual(entry["matcher"], "Bash")
        self.assertIn("block_raw_deploy.py", entry["hooks"][0]["command"])


if __name__ == "__main__":
    unittest.main()
