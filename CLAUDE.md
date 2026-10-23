# Bellhop

Mac menu bar app: search and run any menu bar icon, or any item inside its menu, from the keyboard.
The full plan, including scope, architecture, risks and milestones, is in `docs/PLAN.md`. Read it before starting a milestone.

## Current milestone

**Milestone 5: v0.1 release** (v0.1.1 out Oct 23; Sparkle update verified on the M5 Max; the clean install on the M1 is still open). The app was renamed from Valet to Bellhop on Oct 22 (Laravel Valet already installs a `valet` command); the local folder is still `~/Dropbox/Claude/Valet`. Milestones 3 (Bellhop panel, divider, keepers) and 4 (command palette) are done on the M5 Max as of Oct 22; the ⌘-drag test on the Cinema Display and the M1 run are still open, so keep `bellhop-probe` until then. Update this line when a milestone is done.

## Stack

- Swift 6, Swift Package Manager. AppKit shell with SwiftUI views. No `.xcodeproj` in the repo.
- Targets (folder names avoid `Bellhop`/`bellhop` because macOS disks are case-insensitive):
  - `BellhopCore`: library, no UI. All Accessibility work lives here.
  - `BellhopApp`: the app (status item, palette, settings). `scripts/bundle.sh` packages it as `dist/Bellhop.app`.
  - `BellhopCLI`: the `bellhop` CLI (swift-argument-parser). It talks to the running app over a Unix socket.
  - `bellhop-probe`: throwaway spike tool for milestone 1. Delete it once BellhopCore replaces it.
  - `BellhopCoreTests`: unit tests.
- The repo lives in Dropbox. `.build` and `dist` carry `com.dropbox.ignored`; don't run git on both Macs at once.
- Bundle ID `com.tommymassaro.bellhop`. Dev builds sign with the Developer ID cert (Makefile default for `CODESIGN_IDENTITY`).
- Dependencies: KeyboardShortcuts (sindresorhus), swift-argument-parser, Sparkle 2 (from v0.1). Ask before adding any others.

## Commands

- `make test`: unit tests
- `make lint`: SwiftLint
- `make run`: builds `dist/Bellhop.app`, signs it with `$CODESIGN_IDENTITY`, and opens it
- `make probe`: builds and runs `bellhop-probe`, writing JSON to `probe-output/`

## Rules

- Accessibility API only. Never use ScreenCaptureKit, `CGWindowListCreateImage` or anything that needs Screen Recording.
- Never move, drag or redraw other apps' icons. Bellhop condenses the bar only by sizing its own divider item, which makes macOS collapse the icons to its left. Keepers are Bellhop's own items showing an app's icon or status text, never a copy of its menu bar glyph. Press items with `AXPress`, not synthesized mouse events.
- All AX calls run off the main thread inside an actor, with `AXUIElementSetMessagingTimeout` set per app.
- Put AX behind a protocol so BellhopCore is testable without a live menu bar. Tests use JSON fixtures in `Tests/Fixtures/`, captured from real probe output.
- No network calls except Sparkle's update check. No analytics.
- No GPL code. Don't copy from Ice or Thaw. Coat Check is MIT: reuse is fine with attribution in `NOTICE`.
- macOS 14 minimum. Test on macOS 27 first.
- Ask before any destructive menu action in testing (Quit, Delete, Sign Out, Reset). Use harmless items like toggles or "About" when checking that AXPress works.
- Run `make test` and `make lint` before every commit. Keep commits small, one concern each.
- New fixtures go through `tools/scrub-fixture.py`: menus can hold clipboard history, chat titles and tokens.

## Working with Tommy

- He tests on real hardware: an M5 Max MacBook Pro and an M1 MacBook Pro. Each time you change UI or Accessibility behavior, give him exact steps to check it.
- Stop at the end of each milestone and show what's done against its "Done when" line in the plan. Don't start the next milestone without a go-ahead.
- He's a product designer and design engineer. Keep explanations short. Flag product or UX tradeoffs instead of deciding them silently.
- Desktop-first UI, native macOS look. Mockups for the palette, Bellhop menu, divider and notch panel come before UI code. They live in `design/mocks/`.
