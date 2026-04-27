# APIStatusBar

A macOS menu bar app that shows remaining quota of a self-hosted [new-api](https://github.com/QuantumNous/new-api) gateway at a glance.

> **v0.1** — status bar label, popover, and settings only.
> Dashboard with usage heatmap and Homebrew distribution land in v0.2 / v0.3.

## Requirements

- macOS 26.0 (Tahoe) or later
- A running new-api instance you control
- An Access Token from new-api Web UI → Personal Settings → "Generate Access Token"

## Build from source

```bash
git clone <this repo>
cd APIStatusBar
brew install xcodegen
xcodegen generate
open APIStatusBar.xcodeproj
```

In Xcode, ⌘R. The status bar icon appears top-right.

## First-time setup

1. Click the menu bar icon → "Settings…"
2. Fill in:
   - **Server URL** — e.g. `https://api.your-host.com`
   - **Access Token** — paste from new-api Web UI
3. Click **Verify Connection**
4. Close Settings — the popover refreshes within ~1s

The label refreshes every 60s by default. Below the low-balance threshold, the label and balance turn red.

## Architecture

- `Core/` — networking, Keychain, formatting, polling (fully unit-tested)
- `UI/` — Liquid Glass surfaces (`.glassEffect`, `GlassEffectContainer`) for popover and Settings
- See [docs/superpowers/specs/2026-04-25-apistatusbar-design.md](docs/superpowers/specs/2026-04-25-apistatusbar-design.md) for the full design

## Running tests

```bash
xcodebuild -project APIStatusBar.xcodeproj -scheme APIStatusBar -destination 'platform=macOS' test
```

## Credits

Provider icons under `Resources/Icons/` are from [lobehub/lobe-icons](https://github.com/lobehub/lobe-icons) (MIT).
