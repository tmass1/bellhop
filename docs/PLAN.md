# Valet — Menu Bar App Build Plan

Oct 21, 2026 · Tommy Massaro

## Summary

Valet is a free, open-source Mac menu bar app. It keeps your menu bar tidy on any screen: icons you rarely look at tuck away, and every icon stays one click or keystroke away in a vertical list. Horizontal menu bars run out of room on smaller screens; a vertical list doesn't.

macOS 27 (Sept 14, 2026) draws the menu bar as one window with its own overflow arrow, and that broke Bartender, Ice and Hidden Bar. Valet works with the arrow instead of fighting it.

- **Coat Check:** click the hanger, scan a list, hover to find the menu, click the item.
- **Valet:** a menu bar with only what you choose, everything else in Valet's menu, and a hotkey to reach any of it.

Valet makes four bets:

1. **Condense the menu bar.** Valet's divider tucks every icon to its left behind macOS's own overflow arrow. Nothing is dragged or redrawn.
2. **A vertical home for every icon.** The Valet menu lists all icons, tucked ones first, each with its real menu mirrored.
3. **A command palette over the menu bar.** Open any icon, or run an item inside its menu, from the keyboard.
4. **Scriptable by default.** Every action is available from the CLI, Shortcuts and AI agents (MCP). Live status (VPN, sync, usage) comes along for free.

It keeps Coat Check's best traits:

- It asks for one permission, Accessibility.
- It never moves, drags or redraws other apps' icons. It only sizes its own divider.
- It sends no telemetry.
- It's MIT licensed.

"Valet" is a working name: a valet parks your things and brings them back on request.

## Landscape

Every option today is mouse-driven, and macOS 27 broke most of them. The keyboard and search space is open.

| Option | What it does | Gap Valet fills |
| --- | --- | --- |
| [macOS 27 overflow arrow](https://www.macstories.net/stories/macos-27-the-macstories-review/3/) | A double arrow appears when icons don't fit. Clicking it slides the hidden icons out to the left of the notch for a moment. | Mouse only. No search, no access to menu items. macOS 27 and later only. |
| [Coat Check](https://coatcheckformac.com/) | Lists every icon under a hanger, hidden ones first. Mirrors each app's real menu and presses the item you pick. Has a CLI. Free, MIT. | Browse only, with no search or hotkey. Apple silicon only. [macOS 27 support still untested](https://github.com/coreyhaines31/coatcheck/issues/24). |
| Ice, Bartender, Thaw | Hide and rearrange icons into sections and layouts. | [Broken by macOS 27](https://badgeify.app/macos-27-golden-gate-menu-bar-changes/), which draws the menu bar as one window. Valet condenses through macOS's own overflow instead, so it works on 27 without private APIs. |
| [Hidden Bar](https://newreleases.io/project/github/dwarvesf/hidden/release/v1.11) | Collapses icons behind an arrow. v1.11 restored macOS 27 support through a private framework. | Hiding only, with no list, search or menu mirroring. Depends on a private framework on 27. |
| [ChocolateBar](https://www.producthunt.com/p/chocolatebar/chocolatebar) | Adds a second row under the menu bar for overflow icons. | Takes up screen space and is still mouse-driven. |

macOS 27 also changes the ground underneath this kind of app: the menu bar is now drawn as a single window. Coat Check is still checking whether the Accessibility listing it relies on returns every icon on 27, so that is our first spike (see Risks).

## Product principles

These are the tie-breakers when a feature decision is unclear.

1. **Keyboard first, mouse friendly.** Every action is reachable without the trackpad, and the Valet menu still works for people who never touch the hotkey.
2. **Condense, don't rearrange.** Valet only sizes its own divider and draws its own keepers; macOS decides what collapses. Never move, drag or redraw other apps' icons. Never capture the screen.
3. **One permission.** Accessibility only. No Screen Recording, no Input Monitoring.
4. **Idle until summoned.** No polling loops, with one exception: keepers re-read their own apps' status text every 30 seconds. Everything else happens when Valet's menu or the palette opens.
5. **Native, not themed.** Use AppKit and SwiftUI with system materials. Respect Reduce Motion, Reduce Transparency, and light and dark mode.
6. **Scriptable by default.** Anything the UI can do, the CLI, Shortcuts and MCP can do too.
7. **Fail safe.** If macOS changes underneath us, degrade to read-only listing rather than clicking the wrong thing.

## Feature scope

The MVP condenses the menu bar and gives every icon a vertical home, then adds the palette as its keyboard layer.

| Feature | Phase | Why it matters |
| --- | --- | --- |
| Divider: tuck every icon left of it behind macOS's overflow; click Valet to show or hide them | MVP | The core reason to install: a tidy menu bar on a small screen |
| Keepers: bring chosen tucked icons back as Valet's own items, in any order | MVP | Choose any icons to keep, which no macOS 27 tool can do without faking drags |
| Valet menu: every icon, tucked ones first, real menus mirrored, real item pressed | MVP | The vertical home, and the mouse path |
| Command palette on a global hotkey | MVP | Reach any icon or item without hunting |
| Fuzzy search across app names **and** menu item paths | MVP | Typing "awake 1h" finds Midnight Oil › Keep awake for 1 hour |
| Recents and frecency ranking | MVP | Your top three actions sit at the top before you type |
| Accessibility onboarding and launch at login | MVP | Without them, first run fails |
| `valet` CLI with `--json` | MVP | Cheap to add once the core library exists; agents use it right away |
| Pinned items | v1 | Lets you build your own short list |
| Live status line per icon (title or value text) | v1 | Read VPN, timer or disk state without opening anything |
| Notch drop-down panel | v1 | Fixes the problem at the spot that causes it; good portfolio moment |
| App Intents for Shortcuts ("Run menu bar item") | v1 | Automations and Siri can use it with no extra work |
| Sparkle updates, DMG, Homebrew cask | v1 | Required before a public launch |
| Universal binary (Intel on macOS 14 to 26) | v1 | Coat Check doesn't support Intel |
| MCP server (`valet mcp`) | Later | Lets Claude and other agents list and run menu bar actions |
| Hotkeys for individual items | Later | Bind ⌃⌥K to one specific action |
| Better handling for panel-style apps | Later | Coat Check's main limitation; depends on spike results |
| Custom aliases for items | Later | "vpn" maps to whichever VPN app you use |

Out of scope: more than one divider or section, rules based on Wi-Fi or Focus, and a second menu bar. Reordering icons stays the user's job (⌘-drag, as macOS already allows).

## Interaction design

The Valet menu and the divider are the everyday surfaces. The palette is the keyboard layer over the same data, and the notch panel is a v1 shortcut into it.

### Command palette (MVP)

- A floating, non-activating panel in the top third of the active screen, so the app you're in keeps focus.
- **Empty state:** Pinned, then Recent, then "Hidden by the notch", then everything else.
- **Each row:** app icon, path ("Midnight Oil › Keep awake for 1 hour"), and status text right-aligned ("84 GB free").
- **Keys:**
  - Return runs the item.
  - → drills into an app's menu, ← goes back.
  - ⌘Return opens the app's real menu at its icon.
  - ⌘P pins or unpins.
  - Esc closes.
- Disabled items appear dimmed. Toggles show their checkmark. Items with their own app shortcut show it in the row.
- **Destructive items** (Quit, Delete, Sign Out, Reset) need ⌘Return or a second Return, so a mistyped search can't quit something.

### Divider (MVP)

- Valet adds one extra status item, the divider. Icons to its left are tucked; icons to its right stay in the bar.
- When collapsed, the divider is wide enough that macOS 27 collapses it and everything left of it behind the overflow arrow. On macOS 14 to 26, the same width pushes those icons off-screen.
- The divider sits just left of Valet's icon and moves with it, so the rule is one sentence: everything left of Valet is tucked away. You arrange by ⌘-dragging Valet's icon, like any other icon. Valet never moves other icons.
- While arranging ("Show Tucked Icons", or ⌥-click Valet), the divider is a thin line. The rest of the time it's invisible, collapsed with the icons it tucks.

### Keepers (MVP)

- Valet sits next to Apple's items, so every third-party icon is tucked. Each icon you keep comes back as a keeper: an item Valet draws itself, just left of Valet's icon, in whatever order you choose.
- A keeper shows the app's status text when it has one (Burn's "56%"), otherwise the app's icon. Valet can't copy an app's real menu bar glyph without Screen Recording.
- Clicking a keeper opens the app's real menu, mirrored. Panel apps, and menus that only exist while open, press the real tucked icon instead.
- Choose in Arrange Menu Bar… (a board: drag icons between "In your menu bar" and "Tucked away", and along the bar to reorder), or with ⌥ in the Valet menu ("Keep in Menu Bar").
- Approved Oct 22: status text, with the app icon as the fallback.

### Valet menu (MVP)

- Every icon in a vertical list, tucked ones first, each with its real menu as a submenu. Panel apps open on click.
- A "Search…" row at the top shows the hotkey. That row teaches the palette to mouse users.

### Notch panel (v1)

- Hover over the notch briefly, or click it, and a panel grows down from the notch. It shows hidden icons as a grid of app icons with status text.
- Clicking a tile opens the mirrored menu. Off by default on Macs without a notch.
- Black in both light and dark mode, so it reads as the notch growing. It drops a notch-width neck through the menu bar and widens below it, so the menu bar stays readable.

### Settings

- Hotkey, palette density (compact or comfortable), and notch panel on or off.
- Launch at login, apps to ignore, CLI install.
- A plain-language privacy page.

Mock the palette, Valet menu, divider and notch panel before writing any UI code (milestone 0).

## Technical architecture

One shared library, ValetCore, does all the Accessibility work. The app, the CLI and Shortcuts are thin layers over it, so every feature can be scripted from day one.

```
┌─ Valet.app ─────────┐          ┌─ ValetCore (shared library) ─┐
│  Valet menu         │  direct  │  Scanner                     │  read + press   ┌───────────────────┐
│  Command palette    │ ───────► │  Visibility                  │ ──────────────► │ Accessibility API │
│  Notch panel        │          │  Menu mirror                 │                 └─────────┬─────────┘
└─────────────────────┘          │  Search index                │                           │ reads menus
┌─ Outside callers ───┐   IPC    │  Action runner               │                 ┌─────────▼─────────┐
│  valet CLI + MCP    │ ───────► │                              │                 │ Other apps' icons │
│  Shortcuts actions  │          └──────────────────────────────┘                 └───────────────────┘
└─────────────────────┘
```

The app UI calls ValetCore directly. The CLI and MCP reach it through the running app, so only the app needs the Accessibility permission.

### Modules

- **Scanner.** For each running app, calls `AXUIElementCreateApplication(pid)` and reads `kAXExtrasMenuBarAttribute`. For each `AXMenuBarItem`, it records title, description, identifier, position and size.
- **Visibility.** Marks an item hidden when it's under the notch (`NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`) or left of the end of the frontmost app's menus. On macOS 27 it also checks for icons collapsed behind Apple's arrow; the spike decides that rule.
- **Menu mirror.** Walks `AXMenu` children into a tree: title, enabled, checkmark (`AXMenuItemMarkChar`), shortcut (`AXMenuItemCmdChar`) and submenus. It reads the top level up front and submenus only when needed.
- **Search index.** Turns each tree into paths ("Midnight Oil › Keep awake for 1 hour"), fuzzy-matches them, and ranks results by frecency stored in Application Support.
- **Action runner.** Calls `AXPress` on the real menu item. For panel-style apps it presses the icon itself, and it reports success or failure to the caller.
- **Divider.** Valet's own second status item. It switches between a normal width and one wide enough to make macOS collapse everything to its left.
- **Valet.app.** The Valet status item and menu, the divider, a non-activating `NSPanel` for the palette, the notch panel, Settings and onboarding.
- **Outside callers.** The `valet` CLI and `valet mcp` connect over a Unix socket the app owns. App Intents run inside the app process. Neither needs its own Accessibility permission.
- **Libraries:** KeyboardShortcuts (sindresorhus) for the hotkey, swift-argument-parser for the CLI, Sparkle 2 for updates, and the official MCP Swift SDK later.

## Platform, distribution and privacy

Valet ships outside the Mac App Store, signed with a Developer ID and notarized. The sandbox blocks the Accessibility access Valet needs.

- **macOS versions:** 14 Sonoma through 27 Golden Gate. Build and test on 27 first, since it's the current release and where competitors broke. Keep a 26 machine for regression testing.
- **Architectures:** Universal binary (arm64 and x86_64). Intel only matters on macOS 14 to 26, but it costs one build flag.
- **Signing:** Apple Developer Program membership ($99 a year, [enroll here](https://developer.apple.com/programs/enroll/)) for a Developer ID certificate and notarization.
  - Until then, use a stable self-signed dev certificate so macOS keeps the Accessibility permission across rebuilds. Coat Check's README flags this.
- **Updates:** Sparkle 2 with an EdDSA-signed appcast, hosted on Cloudflare alongside the landing page.
- **Install paths:** a DMG from the site, plus a Homebrew cask in your own tap.
- **Build system:** a Swift Package plus a Makefile that assembles `Valet.app`, as Coat Check does. There's no `.xcodeproj` to merge, which suits Claude Code. Open it in Xcode when you need the debugger.

### Permissions and privacy

- Accessibility is the only permission. Check it with `AXIsProcessTrustedWithOptions`, and deep-link to Privacy & Security › Accessibility.
- No Screen Recording. Icons in the palette are app icons, not captured pixels.
- No network calls except Sparkle's update check. No analytics, no accounts.
- Menu titles and usage counts stay on the Mac, in `~/Library/Application Support/Valet/`.
- The CLI talks to the running app over a local socket that only your user account can access. It never asks for its own permission.

## Spike results (Oct 21, M5 Max, macOS 27.0.1)

- **Accessibility still lists every icon on macOS 27**, collapsed ones included. Apple's own items now come from `com.apple.MenuBarAgent`, wrapped in an `AXGroup`.
- **The overflow arrow is visible to Accessibility:** an `AXButton` owned by MenuBarAgent. Icons left of it are collapsed, and report piled-up frames just left of it.
- **Most menus aren't readable while closed:** 6 of 23 icons. Pressing the rest either opens a menu Valet can read and close (Dropbox), or a panel, which shows up as a new window within about 100 ms (Claude, Burn, PIA).
- **A divider works on macOS 27.** A wide status item collapses itself and every icon to its left behind the arrow, and removing it restores the bar exactly.
- **Tucked icons still work through Valet:** it read Dropbox's menu and pressed Tidy › History… while both were collapsed.
- **Placing the divider through its saved position preference didn't land where intended,** so the user places it by ⌘-dragging.

## Risks and spikes

| Risk | Spike to run first | Fallback |
| --- | --- | --- |
| macOS 27's Accessibility listing misses icons that are collapsed behind Apple's arrow | On 27 and 26, dump `kAXExtrasMenuBarAttribute` for every running app. Compare the result with what's actually in the bar. | Press Apple's arrow to expand the bar, then read it. Or read the items owned by Control Center. |
| "Hidden" means something different on 27: icons collapse behind the arrow instead of sitting off-screen | Log `AXPosition` and `AXSize` for collapsed items | Treat a frame that's zero-sized, outside the screen, or under the notch as hidden |
| Some apps don't expose their menu until it's open | Count how many of your own apps expose `AXMenu` children while closed | Open the menu, read it, then cancel it. This causes a flicker, so do it only on demand. |
| Panel-style apps (popovers) can't be mirrored, and pressing a hidden icon opens the panel in an odd place | Test three popover apps on 27 | On 27, expand Apple's arrow first, then press the icon |
| An unresponsive app blocks Accessibility calls | Set `AXUIElementSetMessagingTimeout` per app | Skip that app and mark its results stale |
| Walking every menu of every app is slow | Time a full walk with your real set of apps | Index top-level items eagerly and submenus lazily. Refresh in the background each time the palette opens. |
| The divider stops collapsing icons in a macOS update, or collapses Valet's own icon | Re-run the divider spike on each macOS beta | Fall back to listing only: the Valet menu still reaches every icon |
| On macOS 14 to 26 the divider pushes icons off-screen instead, and pressing them opens menus in odd places | Run the divider spike on the M1 | Open the menu from the Valet menu instead of at the icon |
| A search runs a destructive item by accident | — | Require confirmation for Quit, Delete, Sign Out and Reset (see Interaction design) |
| The default hotkey collides with Spotlight or Raycast | — | Let the user set it, and pick a less common default |

## Milestones

Build in this order. Each milestone ends with something you can run on your own MacBook. No dates yet; they depend on the spike.

0. **Design.** Mock the palette, Valet menu, divider and notch panel.
   - Done when: you've approved the mocks for all four surfaces, in light and dark mode.
1. **Accessibility probe (spike).** A throwaway command-line tool that dumps every menu bar item, its frame, whether it's hidden, and its menu tree as JSON.
   - Done when: the output matches reality on both MacBooks, one on macOS 27 and one on 26 if possible.
2. **ValetCore.** Scanner, visibility detection, menu mirroring and the action runner, with unit tests that run against saved JSON snapshots.
   - Done when: `valet list --json` works, and `valet run "Midnight Oil › Keep awake for 1 hour"` presses the real item.
3. **Valet menu, divider and keepers.** The vertical list, the divider, keepers with the Arrange board, Accessibility onboarding and launch at login.
   - Done when: the divider tucks icons on 27, kept icons appear as keepers in the chosen order, tucked icons are listed first, submenus mirror the real menus, and choosing an item works.
4. **Command palette.** Hotkey, fuzzy search over menu paths, frecency, destructive-item confirmation.
   - Done when: any menu item can be run from the keyboard alone, and the panel feels instant on open (target under 100 ms).
5. **v0.1 release.** Developer ID signing, notarization, DMG, Sparkle, Homebrew cask, landing page.
   - Done when: a clean Mac installs Valet from the site and receives an update through Sparkle.
6. **v1.** Notch panel, pins, status line, App Intents, universal binary.
7. **Later.** MCP server, hotkeys for individual items, panel-app handling, aliases.

## Open decisions

- [ ] **Name.** Keep "Valet"? Check the domain, App Store names and trademarks before the landing page.
- [ ] **Default hotkey.** It must not collide with Spotlight (⌘Space) or Raycast (⌥Space). ⌃⌥Space is the placeholder for now.
- [x] **Divider look.** A thin line, shown only while arranging; invisible otherwise. (Approved Oct 21.)
- [x] **Notch panel style.** Black in both appearances. (Approved Oct 21.)
- [x] **Choosing what stays.** Keepers: tuck everything, keep any icons as Valet's own items. Status text, app icon fallback. (Approved Oct 22.)
- [ ] **Private menus.** Leave clipboard history (CopyClip) and similar menus out of search by default?
- [ ] **Minimum macOS.** 14 like Coat Check, or 15 to cut testing?
- [ ] **Test machines.** Which macOS is each MacBook on? Ideally one runs 27 and one runs 26.
- [ ] **Coat Check's code.** It's MIT, so you can borrow from it with attribution. Or write everything from scratch? Either way, avoid Ice and Thaw, which are GPL.
- [ ] **Business model.** Free and open source, or a free core plus a paid tier for the MCP server, hotkeys for individual items, and so on?
- [x] **Visual language.** Strictly native macOS: system font, materials and accent color. (Mocks approved Oct 21, `design/mocks/`.)
- [ ] **Repo.** Name and visibility, for example `tmass1/valet`, private until v0.1.

## Sources

- [Coat Check site](https://coatcheckformac.com/) and [repo](https://github.com/coreyhaines31/coatcheck)
- [Coat Check issue #24: macOS 27 support](https://github.com/coreyhaines31/coatcheck/issues/24)
- [MacStories: macOS 27 review, menu bar overflow](https://www.macstories.net/stories/macos-27-the-macstories-review/3/)
- [Badgeify: macOS 27 menu bar changes](https://badgeify.app/macos-27-golden-gate-menu-bar-changes/)
- [Hidden Bar v1.11 release notes](https://newreleases.io/project/github/dwarvesf/hidden/release/v1.11)
- [ChocolateBar on Product Hunt](https://www.producthunt.com/p/chocolatebar/chocolatebar)
