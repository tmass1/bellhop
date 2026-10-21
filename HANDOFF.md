# Valet: Claude Code handoff

Set up the Mac and the repo once, then paste the kickoff prompt into Claude Code.

## 1. Set up the Mac

1. **Xcode.** Install it from the [Mac App Store](https://apps.apple.com/us/app/xcode/id497799835), open it once so it can finish installing components, then run:

   ```bash
   sudo xcode-select -s /Applications/Xcode.app
   sudo xcodebuild -license accept
   ```

2. **Homebrew.** Check with `brew --version`. If it's missing, install it:

   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

3. **SwiftLint and the GitHub CLI.** Install both, then sign in to GitHub:

   ```bash
   brew install swiftlint gh
   gh auth login
   ```

4. **Claude Code.** You already have it. If you set up the other MacBook later, install it with:

   ```bash
   curl -fsSL https://claude.ai/install.sh | bash
   ```

5. **Dev signing certificate.** This lets macOS keep the Accessibility permission across rebuilds.
   1. Open Keychain Access and choose Keychain Access › Certificate Assistant › Create a Certificate…
   2. Name it `Valet Dev`. Set Identity Type to **Self-Signed Root** and Certificate Type to **Code Signing**. Click Create.
   3. Add it to your shell:

      ```bash
      echo 'export CODESIGN_IDENTITY="Valet Dev"' >> ~/.zshrc && source ~/.zshrc
      ```

## 2. Create the repo

From the folder where you keep your projects:

```bash
mkdir valet && cd valet && git init
mkdir docs
```

Copy the three files into it:

- `CLAUDE.md` → repo root
- `docs/PLAN.md` → `docs/`
- `HANDOFF.md` → repo root (optional; useful when you set up the second MacBook)

Then make the first commit and create the private GitHub repo:

```bash
git add . && git commit -m "Add plan and Claude Code guide"
gh repo create tmass1/valet --private --source=. --remote=origin --push
```

## 3. Start Claude Code

```bash
claude
```

Paste this prompt:

```text
Read CLAUDE.md and docs/PLAN.md. We're starting milestone 1, the Accessibility probe spike. Its job is to answer the biggest unknown before we build anything: does macOS 27's single-window menu bar still list every icon through Accessibility?

1. Set up the Swift package skeleton with the targets in CLAUDE.md (ValetCore, Valet, valet, valet-probe, ValetCoreTests), a Makefile with test, lint, run and probe targets, a .swiftlint.yml, a .gitignore for SwiftPM and dist/, and an MIT LICENSE.
2. Build the valet-probe executable. For every running app, read kAXExtrasMenuBarAttribute and output JSON with: app name, bundle ID, PID, and for each menu bar item its title, description, identifier, frame, a hidden flag, the reason it's hidden, and its AXMenu tree if the menu is readable while closed.
3. Work out the hidden flag from the notch (NSScreen.auxiliaryTopLeftArea and auxiliaryTopRightArea), from the end of the frontmost app's menus, and from zero-size or off-screen frames.
4. Also record the macOS version, which apps don't expose a menu while closed, and how many milliseconds each app took.
5. On first run, if Accessibility isn't granted, print exactly where to turn it on and exit cleanly.

Don't press any menu items yet; this milestone only reads. When it runs, stop and show me a summary of the output so we can check it against my real menu bar before writing ValetCore.
```

## 4. After milestone 1

When the probe output matches your real menu bar on both machines:

- Save one or two probe outputs to `Tests/Fixtures/` as test data.
- Update "Current milestone" in `CLAUDE.md`.
- Tell Claude Code to start milestone 2 (ValetCore).

If the probe shows icons missing on macOS 27, bring the output back to the plan. The fallback options are in the Risks table in `docs/PLAN.md`.
