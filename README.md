<p align="center"><img src="site/assets/bellhop.svg" width="112" alt="Bellhop"></p>

# Bellhop

**Every menu bar icon, one hover away.** Bellhop tucks your Mac's menu bar icons out of the way, keeps the few you
use most, and opens any of them, or anything in their menus, from one list. Press ⌃⌥Space to search every menu bar
item and run it from the keyboard.

[bellhop.pages.dev](https://bellhop.pages.dev)

## Install

Download `Bellhop.dmg` from the [latest release](https://github.com/tmass1/bellhop/releases/latest) and drag Bellhop
to Applications, or:

```bash
brew install --cask tmass1/tap/bellhop
```

macOS 14 or later, Apple silicon and Intel. Signed with a Developer ID and notarized. Bellhop asks for Accessibility
access on first launch: that's how it reads and presses menu bar items. It never records your screen.

## What it does

- **Tucks the menu bar.** Bellhop sizes its own divider so macOS collapses every icon left of it behind the overflow
  arrow. It never moves or redraws other apps' icons.
- **Keepers.** Drag an icon into "In the Menu Bar" in the Bellhop panel and Bellhop shows it next to its own icon, in
  your order.
- **The Bellhop panel.** Rest on Bellhop's icon to list every icon; rest on one to open its menu beside it.
- **The palette.** ⌃⌥Space searches icons and every item in their menus, recents first. Quit, Delete, Sign Out and
  Reset ask twice.
- **The `bellhop` command.** `bellhop list`, `search`, `menu`, `run`, `keep` and `tuck`, with `--json`. It talks to
  the running app over a local socket, so it needs no permission of its own.

## Privacy

Accessibility is the only permission. No analytics, no accounts. What you search and run stays in
`~/Library/Application Support/Bellhop`. The only network request is Sparkle's daily look at the update feed on GitHub.

## Building

Swift Package Manager, no Xcode project. `make run` builds and opens `dist/Bellhop.app`; `make test` and `make lint`
run the tests and SwiftLint. `make release` cuts a release (see `scripts/release.sh`). The plan is in
[docs/PLAN.md](docs/PLAN.md).

MIT licensed.
