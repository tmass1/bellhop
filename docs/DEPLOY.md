# Deploying Bellhop

Bellhop has two things that go out to the public, and each has one safe way to ship it:

| What | Where people see it | Check first | Then ship |
|---|---|---|---|
| The website | bellhop.pages.dev (Cloudflare Pages) | `make site-check` | `make site` |
| The app | GitHub release → Sparkle updates and Homebrew | `make release-check` | `make release` |

Both exist to stop one mistake: shipping from a branch, a checkout or a Mac that doesn't have work that's already
live. The upload would quietly replace the live version with an older one, and whatever was missing would disappear.
The rules for agents are in `AGENTS.md`.

## The website: what `make site` does

1. **Checks that nothing is half-saved.** If anything in `site/` (or the deploy scripts) has changes that aren't
   committed, it stops. Only committed work goes live, never edits sitting on disk.
2. **Asks Cloudflare what's live.** Cloudflare remembers which commit each deploy came from. The live site also
   publishes a small file, `/version.json`, that names its commit. It reads both.
3. **Makes sure this branch has everything that's live.** If the live commit isn't in this branch, it stops and lists
   the work that would vanish, plus the branch to merge.
4. **Asks before going ahead** if you're not on `main`, if some commits here aren't on GitHub yet, or if GitHub has
   newer commits than this copy. These are questions, not stops: you answer yes or no.
5. **Runs the tests and the site check.** The site check makes sure the page and its images are there, every link
   points at a real file, and nothing private (notes, code, hidden files) is in the folder.
6. **Shows what the deploy adds**: the commits and files changed since the live version. Then it asks you to type
   `deploy`.
7. **Deploys** the committed `site/` folder, plus `/version.json`, and notes the commit and branch in Cloudflare.
8. **Checks the live site**:
   - `/version.json` shows the new commit;
   - every page and image loads and matches what was built;
   - private paths (`/CLAUDE.md`, `/.git/config`, the docs, the design mocks…) only ever show the landing page.
   - Nothing on the site needs a sign-in today. If that changes, list those pages in `PRIVATE` in
     `scripts/deploy_site.py`, and the check will make sure they stay locked.
9. **Prints how to roll back**, and a to-do list: a release note if it goes with an app version, merging into `main`
   if you deployed from a side branch, and pushing to GitHub.

`make site-check` does steps 1–6 and looks at the live site as it is now. It builds and deploys nothing, so it's
always safe to run.

## The app: what `make release` adds

`scripts/release.sh` already refused to reuse a version number. Before it builds anything, it now also:

- stops if anything in the repo isn't committed (the release is built from these files);
- asks GitHub for the latest release, and stops if this branch doesn't have all of that release's commits;
- stops if commits here aren't on GitHub yet, because the release is tagged on GitHub at the commit that was built;
- asks about side branches and newer work on GitHub, as the website does;
- runs the tests, shows the commits since the last release, and asks you to type `release`.

## What each stop means and how to fix it

| It says | What happened | Fix |
|---|---|---|
| Changes that aren't committed | Some files are edited but not saved into git. | Commit them, or put them back. |
| This branch is missing work that's already live | Someone (maybe you, on the other Mac) deployed newer work from elsewhere. | Merge the branch it names (usually `main`), then run the check again. |
| This copy doesn't have that commit | The live version came from a copy that never pushed to GitHub. | Push from that copy, then run again here. |
| Can't tell which commit is live | Cloudflare didn't record one and the site has no `/version.json`. | Find the commit in the Cloudflare dashboard, then run with `--live-commit <commit>`. |
| Commits aren't on GitHub yet (release only) | The release tag has to point at a commit GitHub has. | Push, then run again. |
| The tests failed / the site check found problems | Something's broken. | Fix it, commit, run again. |
| This needs a yes / you to type "deploy" | It's running with no one at the keyboard. | Run it in Terminal, or an agent adds `--yes` after you say yes in chat. |

`--yes` only answers the questions. No flag skips a stop.

## Rolling back

**Website.** When a deploy finishes, the command prints a link to the previous deploy in the Cloudflare dashboard. Open
it, choose **⋯ → Rollback to this deployment**, and the old version is back within a minute. Git doesn't change, so
fix the problem in a new commit and deploy again. Redeploying an older commit with `make site` is blocked on purpose,
since that's exactly the "missing live work" case. To undo a change through git instead, revert it on `main` and
deploy.

**App.** An update can't be taken back from Macs that already installed it. Ship a fixed version. To stop more Macs
getting the bad one in the meantime, edit the previous release on GitHub and tick **Set as the latest release**: the
update feed and the download links follow "latest".

## Not covered

- The hook in `.claude/hooks/block_raw_deploy.py` stops Claude Code from running the raw commands. Other tools, and
  people typing in Terminal, aren't blocked. The rule in `AGENTS.md` is what counts.
- Preview deploys (a Cloudflare address other than the live one) aren't set up. The hook blocks raw `wrangler pages
  deploy` for any branch, so ask for preview support if you want it.
- Cloudflare settings, the domain and sign-in are managed in the Cloudflare dashboard. These scripts don't touch them.
