# Panels: project guide for Claude

Read this file at the start of every session, then read `handoffs/LATEST.md` (private, gitignored) for the current state and next steps. Keep both up to date as you work (rules in "Handoffs" below).

## What this is

Panels is a windowless macOS workspace app: resizable, dockable panels that hold markdown notes, real terminals, web apps, tasks and a focus timer, grouped into workspaces. Built with SwiftUI and AppKit (macOS 26 and newer, Xcode project, no third party packages). Owner: Aiyan Chowdhury. Bundle id `com.aiyan.Panels`. Repo: `thecatthatflies/panels` on GitHub. The app icon is `panels.icon` (Icon Composer). Font: Instrument Sans, bundled in `Panels/Resources/Fonts` (OFL).

## Commands

```bash
# build (Debug) and run
xcodebuild -project Panels.xcodeproj -scheme Panels -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Panels.app

# release build (what CI ships). Project pins Release to -Osize: -O crashed swiftc (LLVM dominance error)
xcodebuild -project Panels.xcodeproj -scheme Panels -configuration Release -derivedDataPath build MARKETING_VERSION=1.0.0 build

# headless self test: 189 checks, prints PASS or FAIL lines, exits. Always use a scratch data dir.
mkdir -p /tmp/panels-selftest-data && PANELS_SELFTEST=1 CFFIXED_USER_HOME=/tmp/panels-selftest-data PANELS_DATA_DIR=/tmp/panels-selftest-data PANELS_TIMER_SPEED=60 \
  PANELS_SELFTEST_LOG=/tmp/panels-selftest.log build/Build/Products/Debug/Panels.app/Contents/MacOS/Panels
cat /tmp/panels-selftest.log   # last line is ALL PASSED or N FAILED

# render every panel kind at small sizes to PNG (layout regression evidence), then quits
PANELS_DATA_DIR=/tmp/panels-snap-data PANELS_SNAPSHOTS=/tmp/panels-snaps build/Build/Products/Debug/Panels.app/Contents/MacOS/Panels

# same self test as a script (what CI runs): exits 1 on any FAIL, timeout or unfinished run
scripts/selftest.sh build/Build/Products/Debug/Panels.app

# dictation training data and scoring (standard library Python only)
python3 ml/gen_data.py && python3 ml/eval.py
```

Environment variables (all test or developer hooks, never set in normal use):
`PANELS_DATA_DIR` data folder override, `PANELS_SELFTEST=1`, `PANELS_SELFTEST_LOG`, `PANELS_TIMER_SPEED=N` (N times faster timer), `PANELS_SNAPSHOTS=dir`, `PANELS_DICTATION_FILE=audio` (stream a file instead of the microphone), `PANELS_UPDATE_FEED=url` (fake release feed), `PANELS_UPDATE_AUTOINSTALL=1` (install without clicking the pill).

## Repo map (`Panels/`)

| File | Role |
| --- | --- |
| `PanelsApp.swift` | `@main`, scenes (main window, About, Settings), `AppDelegate` (event monitors, autosave, popout restore, test hooks) |
| `Models.swift` | `PanelKind`, `PanelSettings` (one Codable struct for every panel kind, lenient decoder), `Panel`, `Node` (layout tree), `Space` (a workspace), `Workspace` (singleton: all structural operations), `ClosedItem` (undo stack), layout presets |
| `WorkspaceOps.swift` | Lock In, workspace duplicate/move/templates (`TemplateStore`), size shortcuts, file open/save, reopen-last-closed |
| `Persistence.swift`, `AppPaths.swift` | JSON snapshot save/load (autosave every 1.2 s), data folder (`PANELS_DATA_DIR` aware) |
| `Runtime.swift` | Caches live objects per panel id (terminal controller, web controller, note editor host, timer model) so layout changes never kill sessions |
| `PanelSize.swift` | size classes (tiny, small, regular, roomy), per kind minimums, split sizing with minimums; `\.panelSize` and `\.panelDims` environment |
| `Tiling.swift` | auto tiling: `TileLayout` (balanced, main, columns, rows, spiral), `TileEngine` (pure layout builder, fit aware grid), `Workspace` extension: `setTiling`, `retile`, swap and resize by keyboard. `Space.tiling` nil = manual. Edge docking and explicit split turn it off |
| `Components.swift` | Theme environment key, `HostContainer` (reparent-safe native view host), window configuration and traffic light metrics (`WindowChrome`), `Motion` animation constants, buttons and setting controls, `Prompt` |
| `RootView.swift`, `TopBar.swift`, `LayoutViews.swift`, `PanelChrome.swift` | window shell, workspace tabs, split layout and dividers and drag/drop docking, panel frame + header + settings popover + `PanelBodyView` |
| `NotePanel.swift`, `MarkdownEditor.swift`, `Writing.swift` | notes: preview renderer and parser, NSTextView editor with live styling, wiki links, snippets, outline, HTML/PDF export, find |
| `TerminalEmulator.swift`, `TerminalView.swift` | from-scratch VT emulator, PTY controller, NSView renderer |
| `WebPanel.swift`, `WebSupport.swift`, `Sites.swift` | `WKWebView` controller (tweaks, app mode, isolated sessions, blockers), site library, settings router, site editor; WebSupport: downloads, site permissions, JS dialogs, download strip |
| `TasksTimerPanels.swift` | tasks panel, `TimerModel` and the adaptive timer view |
| `Theme.swift`, `ThemeStore.swift` | built-in themes, `Appearance`, density, custom theme store and editor |
| `Sound.swift`, `SoundSettingsView.swift` | synthesized UI/typing/ambient sound engine and settings |
| `Dictation.swift` | SpeechAnalyzer dictation, rule cleanup, live ghost text, HUD |
| `Popouts.swift` | panels in their own floating windows |
| `Onboarding.swift` | first launch overlay (3 steps: theme and spacing, starting template, extras), versioned by `Onboarding.version`, reopened by Help > Show Welcome Again; also `DictationPermissionCard` (mic priming and denial recovery) |
| `FocusMode.swift`, `CommandPalette.swift`, `Menus.swift`, `SettingsWindow.swift`, `About.swift`, `WorkspaceCustomizer.swift`, `Updater.swift` | Lock In HUD, palette, native menus, Settings tabs, About, workspace icon picker, GitHub release updater |
| `SelfTest.swift`, `SnapshotTool.swift` | headless test harness and size snapshots |

Other folders: `ml/` (dictation model data and eval), `ideas/` (gitignored parked ideas), `handoffs/` (gitignored session handoffs), `.github/workflows/release.yml` (build, self test and publish on every push to `main`), `.github/workflows/ci.yml` (build and self test on PRs and non-main pushes), `scripts/selftest.sh`.

## Architecture rules that matter

- **One model, observable.** `Workspace.shared` owns `spaces: [Space]` and `popouts`. A `Space` owns a `Node` tree (leaf = `Panel`, split = axis + children + weights). Every structural change goes through `Workspace` methods and ends with `Persistence.markDirty()`. After any tree edit the tree must stay valid (every split has 2 or more children, weights positive and the same count, unique panel ids); `SelfTest` checks this.
- **Native views are cached, never recreated.** Terminal, web and note views live in `Runtime` keyed by panel id. SwiftUI hosts them through `HostContainer`, which lets the newest container win and never rips a view out of its new home. Never return a cached NSView directly from `makeNSView`.
- **Settings are one struct.** Add a field to `PanelSettings` in four places: property, `CodingKeys`, decode line (it uses a lenient `v(.key, default)` helper so old files still load), and the UI in `PanelSettingsView`.
- **Persistence** is JSON in `AppPaths.dir` (`workspace.json`, `sites.json`, `templates.json`, `themes.json`, `snippets.json`). Preferences live in `UserDefaults` (appearance, sound, dictation).
- **Animation constants** come from `Motion` (they honor Reduce Motion). Do not scatter literals for structural animations.
- **Sound hooks**: call `Sound.play(.cue)` for UI events and `Sound.type(kind)` from key handlers. Sound is optional and off by default.
- **Size classes**: `PanelView` reads its own size class from `@State` fed by a GeometryReader (an environment value set inside its own body does not reach itself). Children read `\.panelSize`.
- **Note editor caret is custom**: `PanelTextView` draws its own caret on a layer (shape, thickness, blink, smooth glide; `caretRect()` is tested) and its own placeholder. The system caret is disabled (`drawInsertionPoint` no-op) because it spans the whole line box. Markdown symbols collapse to a 0.1 pt font off the active lines when `hideMarks` is on (`EditorStyle.activeLines`). The toolbar (`NoteToolbar`) and Cmd B/I/E all go through `PanelTextView.apply(_ NoteFormat)`.
- **Hard panel minimums**: `PanelSize.minimum(for:)` (note 440x320, tasks 340x280, terminal 480x280, web 520x360, timer 300x220; chosen so each panel's content fits without clipping, checked by the `minsize-*.png` snapshots; the timer switches to its compact layout below 340 pt tall). The window minimum (`RootView.windowMin`) grows to what the active workspace needs (`Workspace.requiredContentSize`), dividers cannot cross a child's minimum, and `addPanel`, `split` and `duplicate` refuse (toast, rollback) when the result would not fit the screen. The required size must never depend on the current window size (that fed back and grew the window to 38000 pt once); it uses only the panels and the screen. `addPanel` returns `Panel?`.
- **Windows at launch**: only the main window may open. About is `.defaultLaunchBehavior(.suppressed)` and nothing restores. The window minimum size is set from AppKit after layout (`RootView.applyWindowMin`), never through a SwiftUI frame that tracks model state (that crashed with a layout pass abort). Web pages cannot open windows without a user gesture.
- **Closing things is undoable**: any close of a panel, workspace or pop-out must `pushClosed(...)`. `Cmd Shift T` reopens the last one.

## Design rules

- Palette from the owner: Olive Wood `7E6551`, Taupe `938581`, Granite `466362`, Lavender Grey `8896AB`, Pale Sky `C5D5E4`. Themes derive from it (Granite default dark, Pale Sky light, Taupe, Lavender, plus user themes). One accent per theme. No purple glows, no neon.
- Type: Instrument Sans for UI. Timer digits use SF Rounded light. Editor fonts are selectable.
- Corner radii and gaps follow the density setting. Header height too.
- UI copy: plain, short, no em dashes anywhere, no filler words like "seamless". Use SF Symbols, one weight family.
- Everything must work with the window small. See the handoff for the scaling gaps.
- Optional and customizable beats hardcoded: sounds, themes, density, per-panel settings.

## Pitfalls learned the hard way

- **Double tap gestures delay single taps** by the double click interval. Use `.onTapGesture { }` plus `.simultaneousGesture(TapGesture(count: 2)...)`, never two `onTapGesture`s.
- **Cmd W** must close the front window, not a panel, when Settings or About is key (handled in `Menus.swift` with `WindowChrome.mainWindow`).
- **Traffic lights**: AppKit re-lays out the title bar and undoes manual positions. `WindowChrome` re-applies after transitions and on `didUpdate` (`enforce`). Only touch the main window's buttons.
- **Synthetic hover does not fire** in computer-use tests (SwiftUI `onHover` needs real mouse events). Header actions show on hover or when the panel is focused for that reason.
- **Cmd K** belongs to the palette; the terminal clear is Cmd Option K, and the editor's link shortcut is Cmd Shift K.
- `Runtime` is intentionally not `@MainActor` (Swift 5 mode, called from many contexts).
- Settings/About windows restore old frames; `SettingsWindowSizer` enforces the size.
- `NSOpenPanel` and `NSSavePanel` opened from Settings must be sheets on the front window (`beginSheetModal`), or Cancel closes Settings.
- Debug builds are much slower than Release; judge speed on Release.

## Testing

- **Test runs must never touch the owner's machine state.** `TestMode.active` (self test or snapshots) silences all sound, hides the window (alpha 0, accessory activation policy) and stops `soundPrefs` being read or written. The self test script also sets `CFFIXED_USER_HOME` so UserDefaults go to the scratch folder. A past bug: the self test ran real timers at 60x through the owner's real sound settings, so they heard timer chimes (1 or 3, pitch varying) and saw the window flash at every test run, and it overwrote their sound preferences.

- Before saying anything works: build, run the headless self test, and for UI changes look at it (screenshot or snapshot sheet). Add a check to `SelfTest.swift` for every bug you fix.
- **Never delete `~/Library/Application Support/Panels`.** Use `PANELS_DATA_DIR` for any experiment. (Past sessions wiped it repeatedly.)
- Computer use tips: the Mac screen may be locked (check `ioreg -n Root -d1 -a` for `IOConsoleLocked`); GUI testing is impossible then, use the self test and snapshot tool. Bring the app forward with `open_application` before display-scope actions; call `app_release` before switching from background `app_*` tools to display tools. Do not click blindly: `Cmd W` and the X buttons delete the user's panels.
- Run the update flow only against a local fake feed (python `http.server` plus `PANELS_UPDATE_FEED`), never against real releases without being asked.

## Working agreement with the owner

- **Work in waves and stop for approval after each wave.** Finish, verify, summarize, ask. Do not start the next wave until told.
- **Do not commit or push unless asked.** When asked for a summary of changes, give one lowercase comma separated line in the style of the owner's commits, for example: `lock in mode, menu bar update, workspaces, site library`.
- **Ask before any download or install** (packages, models, fonts), naming the exact items and sizes. Same for anything outward facing (publishing, sending, creating repos).
- Parked big ideas go in `ideas/` as one markdown file per idea when the owner says to add an idea. Do not build them unasked.
- Be honest about what was and was not verified, including things only checked in code.
- Keep replies short and plain. Put detail in the handoff, not the chat.

## Handoffs (required, every response)

`handoffs/` is gitignored and exists so a new session with zero context can continue.

1. **After every response that changes code, files, plans or decisions**, update the handoff before replying. Do not wait to be asked.
2. Maintain two things in `handoffs/`:
   - `LOG.md`: append one entry per response, newest at the bottom: date and time, what the user asked, what changed (file names), how it was verified, what is left. Two to six lines.
   - A dated handoff file per milestone or topic, `YYYY-MM-DD-topic.md`, containing: current state, what changed and why, verification evidence, known issues, next steps in order, decisions waiting on the user, and exact commands to resume. Update the existing file for the same topic instead of making many near duplicates.
3. Keep `handoffs/LATEST.md` as a one screen index: the newest handoff file name, the three most important next steps, the open questions for the owner, the git state (last pushed commit, list of uncommitted files). Overwrite it every time.
4. When architecture, commands, conventions or the working agreement change, update this `CLAUDE.md` in the same turn.
5. Save screenshots or generated evidence under `handoffs/assets/` and reference them by path.
6. At the start of a session: read `CLAUDE.md`, `handoffs/LATEST.md`, then the newest handoff file, then `git status` and `git log -5`. Tell the owner in two lines what you understood before working.
