# Valet

Mac menu bar app: search and run any menu bar icon, or any item inside its menu, from the keyboard.
The full plan, including scope, architecture, risks and milestones, is in `docs/PLAN.md`. Read it before starting a milestone.

## Current milestone

**Milestone 3: Valet menu and divider** (in progress; the ⌘-drag follow test waits for the Cinema Display). Milestone 0's mocks were approved Oct 21 (`design/mocks/`). Milestones 1 and 2 are verified on the M5 Max (macOS 27); the M1 MacBook run is still pending, so keep `valet-probe` until then. Update this line when a milestone is done.

## Stack

- Swift 6, Swift Package Manager. AppKit shell with SwiftUI views. No `.xcodeproj` in the repo.
- Targets (folder names avoid `Valet`/`valet` because macOS disks are case-insensitive):
  - `ValetCore`: library, no UI. All Accessibility work lives here.
  - `ValetApp`: the app (status item, palette, settings). `scripts/bundle.sh` packages it as `dist/Valet.app`.
  - `ValetCLI`: the `valet` CLI (swift-argument-parser). It talks to the running app over a Unix socket.
  - `valet-probe`: throwaway spike tool for milestone 1. Delete it once ValetCore replaces it.
  - `ValetCoreTests`: unit tests.
- The repo lives in Dropbox. `.build` and `dist` carry `com.dropbox.ignored`; don't run git on both Macs at once.
- Bundle ID `com.tommymassaro.valet`. Dev builds sign with the Developer ID cert (Makefile default for `CODESIGN_IDENTITY`).
- Dependencies: KeyboardShortcuts (sindresorhus), swift-argument-parser, Sparkle 2 (from v0.1). Ask before adding any others.

## Commands

- `make test`: unit tests
- `make lint`: SwiftLint
- `make run`: builds `dist/Valet.app`, signs it with `$CODESIGN_IDENTITY`, and opens it
- `make probe`: builds and runs `valet-probe`, writing JSON to `probe-output/`

## Rules

- Accessibility API only. Never use ScreenCaptureKit, `CGWindowListCreateImage` or anything that needs Screen Recording.
- Never move, drag or redraw other apps' icons. Valet condenses the bar only by sizing its own divider item, which makes macOS collapse the icons to its left. Press items with `AXPress`, not synthesized mouse events.
- All AX calls run off the main thread inside an actor, with `AXUIElementSetMessagingTimeout` set per app.
- Put AX behind a protocol so ValetCore is testable without a live menu bar. Tests use JSON fixtures in `Tests/Fixtures/`, captured from real probe output.
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
- Desktop-first UI, native macOS look. Mockups for the palette, Valet menu, divider and notch panel come before UI code. They live in `design/mocks/`.
