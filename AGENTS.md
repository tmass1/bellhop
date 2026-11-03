# Bellhop: rules for every agent

The project guide (stack, commands, coding rules) is `CLAUDE.md`. Read it too. This file holds the rules every agent
follows, whichever tool it runs in.

## Production deploys

Bellhop has two production targets:

- **The website**, bellhop.pages.dev (Cloudflare Pages). Deploy it only with `make site` (`scripts/deploy_site.py`).
- **The app**: the GitHub release, which Sparkle updates and Homebrew install from. Publish it only with
  `make release` (`scripts/release.sh`).

Both refuse to ship from a branch, checkout or Mac that's missing work already live. `docs/DEPLOY.md` explains each
step and stop in plain language.

1. Deploy to production only when Tommy names production for this deploy ("deploy the site to production", "release
   0.1.5"). A yes for one deploy doesn't carry over to the next.
2. Run the check first, `make site-check` or `make release-check`, and show Tommy the whole output: what the deploy
   adds, every question it will ask, and the reminders.
3. Never get around a stop. Don't run `wrangler pages deploy`, `gh release create` or the steps inside the scripts by
   hand, and don't edit the checks to make a stop go away. Fix the cause instead, usually by merging the branch that
   holds the live commit, and run the check again.
4. `--yes` only after Tommy says yes in chat to this deploy. It answers the questions; it never skips a stop.
5. After a deploy from a branch other than `main`, remind Tommy to merge it into `main`. Commit and push only when he
   says.

A Claude Code hook (`.claude/hooks/block_raw_deploy.py`) blocks the raw commands. Other tools don't have it, so the
rule above is what counts.
