# APIStatusBar — Design Spec

**Date:** 2026-04-25
**Owner:** Dylan
**Status:** Approved (pending user review of this document)

## 1. Goal

A macOS menu bar app that displays remaining quota of a self-hosted [new-api](https://github.com/QuantumNous/new-api) gateway at a glance, with a deeper dashboard for usage history, model breakdowns, and a GitHub-style contribution heatmap.

Built for **macOS 26.0 (Tahoe)** with **Liquid Glass** as the primary visual language, matching the design vocabulary of the user's ARIA project. Distributed via GitHub Releases + Homebrew cask. Built in Swift / SwiftUI under the user's Apple Developer organization.

## 2. Non-Goals

- App Store distribution
- Multi-account support (deferred to v2)
- In-app top-up / payment (link out to web console instead)
- Internationalization (English + Chinese hard-coded only)
- Push notifications (visual indicators only, until proven necessary)

## 3. Backend Surface (new-api, no server changes required)

All endpoints are existing in stock new-api. Auth headers for every call:

```
Authorization: <access_token>     # from Web UI → Personal Settings → Generate Access Token
New-Api-User: <user_id>           # numeric user ID matching the access token
```

| Purpose | Method | Path | Notes |
|---|---|---|---|
| Account snapshot (balance, used, request count) | GET | `/api/user/self` | Polled for status bar label |
| Daily usage breakdown by model | GET | `/api/data/self?start_timestamp=&end_timestamp=` | **Max 30-day window per call** — heatmap fetch is chunked |
| Aggregate stats (quota / RPM / TPM) | GET | `/api/log/self/stat?start_timestamp=&end_timestamp=` | For dashboard summary |
| Per-request log entries | GET | `/api/log/self?...` | Used for "recent activity" list (optional v1.1) |

### Quota → USD conversion

new-api stores `quota` as integer units. Default `QuotaPerUnit = 500000` (i.e. 500000 quota = $1.00). The conversion ratio is configurable per deployment in admin Options. The app stores it in Settings (default 500000, user-editable).

## 4. UI Architecture

Three layers, each progressively heavier:

### 4.1 Menu Bar (always-on)
- Template-image icon (Teal Mint variant rendered as `.template`) + dollar amount text, e.g. `$12.34`
- Format rules: `<$100` → `$xx.xx`, `<$1000` → `$xxx`, ≥`$1000` → `$1.2k`
- Below low-balance threshold → text turns red and adds a small `!` glyph

### 4.2 Popover (single click)
Compact 320 × 360 view:
- Remaining balance (large), today / 7d / 30d usage rows
- 30-day sparkline of daily quota
- Buttons: `Open Dashboard` / `Open Web Console` / `Refresh now` / `Settings…` / `Quit`

### 4.3 Main Window — Dashboard (opens from popover)
- **Account header:** remaining, total used, total requests, account age in days
- **Contribution heatmap:** 53 weeks × 7 days, GitHub-style. Color = Teal Mint `#00BFA5` with 5-step alpha `[empty=neutral grey, 0.15, 0.35, 0.6, 1.0]`. Hover tooltip shows date / USD spent / request count / top 3 models that day.
- **Top Models (last 30d):** horizontal bar chart, model icon (from `Resources/Icons/color/`) + name + spend
- **Top Channels (last 30d):** horizontal bar chart
- **Toolbar:** date range selector (30d / 90d / 1y), refresh button

### 4.4 Settings Window (`Settings` scene)
- Server URL
- Access Token (Keychain-backed, never written to UserDefaults)
- User ID
- Quota-per-unit (default 500000)
- Refresh interval (default 60s, min 15s)
- Low-balance threshold ($, default 5)
- Launch at login toggle (`SMAppService`)
- "Open Web Console" link override

## 5. Theme — Liquid Glass

Target platform: **macOS 26 (Tahoe)**. All translucent surfaces use the Liquid Glass APIs introduced with iOS/macOS 26 — never legacy `Color.opacity()` fakes, never the older `.regularMaterial` background unless explicitly listed below for compatibility on a specific surface.

### Color tokens

| Token | Value | Use |
|---|---|---|
| `accent` | `#00BFA5` Teal Mint | Tint for glass effects, heatmap, charts, action buttons |
| `accentMuted` | `#00BFA5` @ 0.15 | Heatmap level-1, hover overlays |
| `warning` | `systemRed` | Below-threshold balance text and error banners |
| `heatmapEmpty` | adaptive grey (`white 0.93` light / `white 0.18` dark) | Empty heatmap cells — never accent-tinted, so "no usage" reads as "no usage", not "low usage" |

### Glass surface patterns

```swift
// Card pattern — dashboard sections, balance card in popover
content
    .padding(20)
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

// Pill / badge pattern — model labels, status pills
label
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .glassEffect(.regular, in: Capsule())

// Tinted glass — accent emphasis (e.g. "Refresh now" primary action)
button
    .glassEffect(.regular.tint(Theme.accent.opacity(0.4)).interactive())

// Floating cluster — balance + button row in popover, merges glass on hover/animation
GlassEffectContainer(spacing: 16) {
    VStack(alignment: .leading) {
        balanceCard.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        actionRow.glassEffect(.regular, in: Capsule())
    }
}

// Window backdrop — Settings, Dashboard
.glassBackgroundEffect()
```

### Banned patterns

- ❌ `Color.white.opacity(0.6)` or any opacity-fake of glass
- ❌ `.background(.regularMaterial)` on macOS 26 — use `.glassEffect(.regular, in:)` instead
- ❌ Drop shadows below `.glassEffect()` — Liquid Glass renders its own ambient depth; adding a manual shadow looks doubled

### Status bar icon constraint

The menu bar icon **remains a template image** (black-on-alpha SF Symbol or imported PDF). Liquid Glass applies to popover/window content, not to the menu bar icon itself — that's still rendered by `NSStatusItem` infrastructure with system-managed tinting.

## 6. Data Flow

```
            ┌────────────────┐
            │  QuotaPoller   │ — 60s timer
            │ (status bar)   │ ───────► /api/user/self
            └───────┬────────┘
                    │ @Published QuotaSnapshot
                    ▼
        ┌──────────────────────┐
        │ MenuBarLabel /       │
        │ PopoverView          │
        └──────────────────────┘

         (lazy, opened on demand)
            ┌────────────────┐
            │ UsageCache     │ — SQLite under
            │                │   ~/Library/Containers/.../usage.sqlite
            └───────┬────────┘
       writes/reads │
                    ▼
            ┌────────────────┐
            │ UsageFetcher   │ ───────► /api/data/self  (chunked 30d windows)
            │                │ ───────► /api/log/self/stat
            └───────┬────────┘
                    │ DailyUsage[]
                    ▼
            ┌────────────────┐
            │ DashboardView  │
            │ HeatmapView    │
            │ TopModelsChart │
            └────────────────┘
```

### 6.1 Heatmap fetch strategy

- On dashboard open, compute missing date ranges by checking SQLite cache
- Fetch chunks of 30 days each via `/api/data/self`, sequential (rate-friendly)
- Aggregate per-day: `quota`, `count`, `topModels[3]`
- Cache forever for past days; today's row refreshed on each open
- Visible immediately with cached data; new chunks fade in as they arrive

### 6.2 Failure handling

- Status bar poll failure: keep last value, add red dot to icon, surface error in popover footer
- 3 consecutive failures → one system notification (`UserNotifications`), then back off to 5min retry
- Auth failure (401) → status bar shows `⚠ Auth`, popover routes to settings
- Dashboard fetch partial failure: show cached portion + inline retry banner for missing chunks

## 7. Project Layout

```
APIStatusBar/
├─ APIStatusBar.xcodeproj
├─ APIStatusBar/
│  ├─ APIStatusBarApp.swift              # @main, MenuBarExtra + Settings + WindowGroup
│  ├─ Core/
│  │  ├─ NewAPIClient.swift              # async/await URLSession wrapper
│  │  ├─ KeychainStore.swift             # Security framework wrapper for token
│  │  ├─ QuotaModel.swift                # raw → USD, formatting
│  │  ├─ QuotaPoller.swift               # ObservableObject + Timer
│  │  ├─ UsageCache.swift                # SQLite (GRDB or sqlite3 raw)
│  │  └─ UsageFetcher.swift              # chunked /api/data/self
│  ├─ UI/
│  │  ├─ MenuBarLabel.swift
│  │  ├─ Popover/PopoverView.swift
│  │  ├─ Dashboard/
│  │  │  ├─ DashboardView.swift
│  │  │  ├─ HeatmapView.swift            # SwiftUI Canvas + DragGesture for hover
│  │  │  ├─ AccountHeader.swift
│  │  │  ├─ TopModelsChart.swift         # SwiftUI Charts framework
│  │  │  └─ TopChannelsChart.swift
│  │  ├─ Settings/SettingsView.swift
│  │  └─ Theme/
│  │     ├─ Theme.swift                  # color tokens
│  │     └─ MaterialCard.swift           # reusable glass card
│  ├─ Resources/
│  │  ├─ Icons/                          # ✓ already populated (lobe-icons)
│  │  │  ├─ mono/    (310 svg)
│  │  │  ├─ color/   (221 svg)
│  │  │  ├─ text/    (297 svg)
│  │  │  └─ LICENSE-lobe-icons
│  │  └─ Assets.xcassets
│  └─ Info.plist
├─ APIStatusBarTests/                    # XCTest target
├─ scripts/
│  ├─ build-release.sh                   # archive + export signed .app
│  ├─ notarize.sh                        # xcrun notarytool submit + staple
│  └─ make-dmg.sh                        # create-dmg invocation
├─ .github/workflows/release.yml         # tag push → build/sign/notarize/release
├─ docs/
│  └─ superpowers/specs/
│     └─ 2026-04-25-apistatusbar-design.md
└─ README.md
```

## 8. Distribution Pipeline

### 8.1 Signing
- **Developer ID Application** certificate from the user's Apple Developer organization
- Signed during `xcodebuild archive` + `xcodebuild -exportArchive` (export options plist with `signingStyle=manual`, `developmentTeam`, signing certificate name)

### 8.2 Notarization
- `xcrun notarytool submit Build.dmg --keychain-profile "AC_PASSWORD" --wait`
- `xcrun stapler staple Build.dmg`
- Apple ID + app-specific password + Team ID stored as GitHub Actions secrets:
  - `APPLE_ID`
  - `APPLE_APP_SPECIFIC_PASSWORD`
  - `APPLE_TEAM_ID`
  - `DEVELOPER_ID_CERT_P12_BASE64`
  - `DEVELOPER_ID_CERT_PASSWORD`

### 8.3 Packaging
- `create-dmg` produces a styled `.dmg` with drag-to-Applications layout
- SHA256 checksum generated alongside

### 8.4 Release Workflow (GitHub Actions, macos-14 runner)
On tag push `v*.*.*`:
1. Checkout, set up Xcode, restore signing assets from secrets
2. `xcodebuild archive` → `.xcarchive`
3. `xcodebuild -exportArchive` → signed `.app`
4. `create-dmg` → `APIStatusBar-x.y.z.dmg`
5. `xcrun notarytool submit + staple`
6. `gh release create` with `.dmg` + `.dmg.sha256` attached
7. (Optional later) bump `homebrew-tap` cask formula

### 8.5 Homebrew Cask
Tap repo: `dylanthomas/homebrew-tap`. Cask file `Casks/apistatusbar.rb`:

```ruby
cask "apistatusbar" do
  version "x.y.z"
  sha256  "<sha256>"
  url     "https://github.com/dylanthomas/APIStatusBar/releases/download/v#{version}/APIStatusBar-#{version}.dmg"
  name    "API Status Bar"
  desc    "Menu bar quota monitor for new-api gateways"
  homepage "https://github.com/dylanthomas/APIStatusBar"
  app     "APIStatusBar.app"
  zap trash: ["~/Library/Containers/com.<org>.apistatusbar"]
end
```

User installs:
```bash
brew tap dylanthomas/tap
brew install --cask apistatusbar
```

Updates flow through `brew upgrade --cask apistatusbar` — no in-app update mechanism.

## 9. Security

- Access token stored in macOS Keychain (`kSecClassGenericPassword`, account = server URL hash)
- Token never written to UserDefaults, plist, or logs
- TLS-only (reject `http://` URLs in Settings unless explicitly opted in via a hidden flag — most new-api deployments are behind HTTPS)
- All `URLSession` requests scoped to a single host; no third-party telemetry

## 10. Testing

- **Unit:** `NewAPIClient` mocked URLProtocol → assert request shape, response decoding, auth header construction
- **Unit:** `QuotaModel` raw↔USD conversion edge cases (rounding, large/small values)
- **Unit:** `UsageFetcher` chunking — given a 9-month range, expect 9–10 chunked calls with correct boundaries
- **UI snapshot:** HeatmapView with synthetic 365-day fixture (covers empty / sparse / dense days)
- **Integration:** mock new-api server (Python `http.server` script under `scripts/mock-newapi.py`) for end-to-end smoke before release

## 11. Open Items (defer until implementation)

- Exact Bundle ID (`com.<org-domain>.apistatusbar` — fill at scaffold time)
- App icon (separate design task; status bar template icon vs. Dock app icon)
- Whether to use GRDB.swift or raw `sqlite3` C API for `UsageCache` (decide during plan)
- Whether dashboard heatmap should be horizontally scrollable (1y default vs. ability to zoom out further)
