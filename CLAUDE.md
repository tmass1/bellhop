# Valet

Mac menu bar app: search and run any menu bar icon, or any item inside its menu, from the keyboard.
The full plan, including scope, architecture, risks and milestones, is in `docs/PLAN.md`. Read it before starting a milestone.

## Current milestone

**Milestone 1: Accessibility probe (spike).** Update this line when a milestone is done.

## Stack

- Swift 6, Swift Package Manager. AppKit shell with SwiftUI views. No `.xcodeproj` in the repo.
- Targets:
  - `ValetCore`: library, no UI. All Accessibility work lives here.
  - `Valet`: the app (status item, palette, settings).
  - `valet`: the CLI (swift-argument-parser). It talks to the running app over a Unix socket.
  - `valet-probe`: throwaway spike tool for milestone 1. Delete it once ValetCore replaces it.
  - `ValetCoreTests`: unit tests.
- Dependencies: KeyboardShortcuts (sindresorhus), swift-argument-parser, Sparkle 2 (from v0.1). Ask before adding any others.

## Commands

- `make test`: unit tests
- `make lint`: SwiftLint
- `make run`: builds `dist/Valet.app`, signs it with `$CODESIGN_IDENTITY`, and opens it
- `make probe`: builds and runs `valet-probe`, writing JSON to `probe-output/`

## Rules

- Accessibility API only. Never use ScreenCaptureKit, `CGWindowListCreateImage` or anything that needs Screen Recording.
- Never move, hide or drag other apps' icons. Press items with `AXPress`, not synthesized mouse events.
- All AX calls run off the main thread inside an actor, with `AXUIElementSetMessagingTimeout` set per app.
- Put AX behind a protocol so ValetCore is testable without a live menu bar. Tests use JSON fixtures in `Tests/Fixtures/`, captured from real probe output.
- No network calls except Sparkle's update check. No analytics.
- No GPL code. Don't copy from Ice or Thaw. Coat Check is MIT: reuse is fine with attribution in `NOTICE`.
- macOS 14 minimum. Test on macOS 27 first.
- Ask before any destructive menu action in testing (Quit, Delete, Sign Out, Reset). Use harmless items like toggles or "About" when checking that AXPress works.
- Run `make test` and `make lint` before every commit. Keep commits small, one concern each.

## Working with Tommy

- He tests on real hardware: an M5 Max MacBook Pro and an M1 MacBook Pro. Each time you change UI or Accessibility behavior, give him exact steps to check it.
- Stop at the end of each milestone and show what's done against its "Done when" line in the plan. Don't start the next milestone without a go-ahead.
- He's a product designer and design engineer. Keep explanations short. Flag product or UX tradeoffs instead of deciding them silently.
- Desktop-first UI, native macOS look. Mockups for the palette, hanger and notch panel come before UI code.
