# panels

multi-layered writing, apps, and terminal in one native and fast app.

A windowless macOS workspace of resizable panels. Each panel is a markdown note, a real terminal, a web app, a task list or a focus timer, and each has its own typeface, accent, surface and padding.

Built with SwiftUI and AppKit. Instrument Sans is bundled (SIL Open Font License).

## Build

```bash
xcodebuild -project Panels.xcodeproj -scheme Panels -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Panels.app
```

Requires Xcode 26 or newer (the app icon is an Icon Composer `.icon` file).

## Shortcuts

| Action | Keys |
| --- | --- |
| Command palette | Cmd K |
| New note / terminal / web | Cmd N / Cmd T / Cmd Shift B |
| Split right / down | Cmd D / Cmd Shift D |
| Zoom panel | Cmd Shift Return |
| Close panel | Cmd W |
| Next / previous panel | Cmd ] / Cmd [ |
| Focus by direction | Cmd Option Arrows |
| Spaces | Cmd 1 to 9, new with Cmd Shift N |

Drag a panel header onto the edge of another panel to dock it, or onto the middle to swap.

## Updates

Every push to `main` runs `.github/workflows/release.yml`, which builds the app and publishes a GitHub release (`v1.0.<run number>`) with `Panels.zip`.

Installed copies check the latest release at launch and every few hours, download it in the background, and show a **Restart to update** pill in the top bar. Check manually from Panels > Check for Updates, or in Settings.

The updater lives in `Panels/Updater.swift`. The repository is set in `UpdateConfig` at the top of that file. The repository must be public for unauthenticated update checks.
