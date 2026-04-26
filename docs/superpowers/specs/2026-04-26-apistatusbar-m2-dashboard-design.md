# APIStatusBar M2 — Dashboard & Heatmap Design Spec

**Date:** 2026-04-26
**Owner:** Dylan
**Status:** Approved (pending user review of this document)
**Builds on:** [2026-04-25 main spec](2026-04-25-apistatusbar-design.md) §4.3 Dashboard

## 1. Goal

Add a focused dashboard window that surfaces 30-day usage history and provider breakdown, opened from the existing menu-bar popover. Refines the original M1 spec's §4.3 to a smaller, more compact target — 30-day heatmap instead of 53-week, no Top Channels card, single-pane layout.

## 2. Non-Goals

- 53-week / 1-year heatmap (deferred — 30-day fits new-api's per-call window cap and matches the user's "smaller, more compact" preference)
- Top Channels chart (no clean per-channel quota source until backend exposes it; defer to v0.3)
- Multiple range toggles (30d / 90d / 1y) — fixed 30-day, single window
- Persistent SQLite cache — in-memory cache via existing ModelStatsPoller is sufficient for 30 days
- Per-day detail drill-down panel — hover tooltip is enough at this granularity

## 3. Window

| Property | Value |
|---|---|
| Size | **480 × 380 pt**, fixed (`.windowResizability(.contentSize)`) |
| Title | "用量仪表板" |
| Standard close button | enabled |
| Minimize / maximize | disabled (system handles via fixed size) |
| Multiple instances | single — re-clicking the toolbar button brings existing window forward |
| Keyboard shortcut | `⌘W` to close (system default) |

## 4. Open Mechanism

A new icon button in `PopoverView.actionRow`:

- SF Symbol: `chart.bar.xaxis`
- Position: between **safari** (Web Console) and the right-aligned **gearshape / power** group
- Style: `.buttonStyle(.glass)` (matches Web Console / Settings / Quit; only Refresh stays glassProminent)
- Help tooltip: "用量仪表板"
- Action: opens (or fronts) the dashboard `WindowGroup` via `@Environment(\.openWindow)` with `id: "dashboard"`

## 5. Layout

Three vertically stacked `.regularMaterial` cards inside a `ScrollView` (so future v2.1 additions don't break layout). 16pt page padding, 14pt inter-card spacing.

### 5.1 Account card (`AccountCard.swift`)

A 2 × 2 LabeledContent grid, ~76pt tall:

```
┌──────────────────────────────────────────────┐
│  剩余             $16.31                      │
│  今日             $1.23                        │
│  总消耗           $33.69                       │
│  请求次数         104                          │
└──────────────────────────────────────────────┘
```

- **剩余** — `poller.snapshot.quotaRaw` formatted via `QuotaFormatter`
- **今日** — sum of `dailyBuckets[today].usd` (computed from `/api/data/self` rows; see §7)
- **总消耗** — `poller.snapshot.usedQuotaRaw` formatted
- **请求次数** — `poller.snapshot.requestCount`, `.formatted()`
- All numbers use `.contentTransition(.numericText())` for digit roll on update
- "账户 N 天" deferred — `/api/user/self` does not return `created_at`; will add when backend exposes it

### 5.2 Heatmap card (`HeatmapView.swift`)

```
┌──────────────────────────────────────────────┐
│  用量热力图（最近 30 天）        少 ░ ▒ ▓ █ 多  │
│                                                │
│   一  ▓ ▓ ▒ ░ ▓                                │
│   二  ▓ ▒ ▓ ░ ▒                                │
│   三  ▒ ░ ▓ ▒ ░                                │
│   四  ░ ▓ ▒ ▒ ▓                                │
│   五  ▒ ▒ ▓ ░ ░                                │
│   六  ░ ░ ▒ ▓ ░                                │
│   日  ▒ ░ ░ ▓ ▒                                │
└──────────────────────────────────────────────┘
```

| Property | Value |
|---|---|
| Grid | 5 columns × 7 rows = 35 cells, column = ISO week, row = 一/二/三/四/五/六/日 (Mon-first) |
| Cell | 14 × 14 pt, `RoundedRectangle(cornerRadius: 3)`, 2pt gap |
| Total chart size | ~80 × 100 pt |
| Empty cells | `Theme.heatmapEmpty` (adaptive grey) for cells outside the 30-day window OR future days OR no data on that day |
| Active cells | `Theme.accent` × alpha from 5-step ladder (see §6) |
| Today's cell | 1pt `.white.opacity(0.7)` inner stroke (always visible regardless of fill bucket — accent-on-accent border would disappear when today's bucket is 4) |
| Weekday labels | Inline 一 二 三 四 五 六 日, font `.caption2`, foreground `.tertiary` |
| Legend | Right-aligned, `少 [░] [▒] [▓] [█] 多` mini swatches |
| Hover tooltip | `4月20日 · $1.23 · 12 次请求` (single line, no day breakdown) |

### 5.3 Top Models card (`TopModelsCard.swift`)

5 rows, last 30 days, sorted by USD desc:

```
┌──────────────────────────────────────────────┐
│  Top Models（最近 30 天）                       │
│                                                │
│  🌸 claude       ████████████  $21.94  65.1%   │
│  ⚪ openai       ███▌          $6.07   18.0%   │
│  🐳 deepseek     ██            $3.37   10.0%   │
│  通 qwen         █             $1.69    5.0%   │
│  G  gemini       ▎             $0.62    1.9%   │
└──────────────────────────────────────────────┘
```

| Property | Value |
|---|---|
| Provider icon | 24×24 pt, `.renderingMode(.original)`, color SVG from `Assets.xcassets/Providers/` |
| Name | font `.callout`, `.foregroundStyle(.primary)` |
| Bar | `Capsule()` track + filled `Capsule()` proportional to provider's USD share of top-1's USD; track tinted `Theme.heatmapEmpty`, fill `Theme.accent` |
| USD | trailing-aligned, monospaced digit, font `.callout` |
| Percent | trailing-aligned, font `.caption`, `.foregroundStyle(.secondary)`, monospaced digit |
| Animation | `.spring(response: 0.5)` on first appearance — bar widths grow from 0 to target |
| Click | non-interactive in v0.1 (future: jump to `/console/log?model=...`) |

## 6. Theme Extensions

No new color tokens needed — reuses `Theme.accent` (Teal Mint) and `Theme.heatmapEmpty` already in `Theme.swift`.

USD-per-day buckets for heatmap alpha (half-open intervals `[lower, upper)` so each USD value falls in exactly one bucket):

| Bucket | USD range | Alpha | Source |
|---|---|---|---|
| 0 (empty) | usd == 0 OR no data | — | `Theme.heatmapEmpty` |
| 1 | `[0.01, 1.00)` | 0.15 | `Theme.heatmapAlphas[1]` |
| 2 | `[1.00, 5.00)` | 0.35 | `Theme.heatmapAlphas[2]` |
| 3 | `[5.00, 20.00)` | 0.6 | `Theme.heatmapAlphas[3]` |
| 4 | `[20.00, ∞)` | 1.0 | `Theme.heatmapAlphas[4]` |

Thresholds tunable via `HeatmapView.bucketEdges = [0.01, 1.0, 5.0, 20.0]` constant; the spec values are sane defaults for personal-scale usage.

## 7. Data Flow

```
            /api/data/self (30-day window, single call)
                          │
                          ▼
                ┌──────────────────────┐
                │  ModelStatsPoller    │
                │  (existing, extended)│
                └─────────┬────────────┘
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
   topProviders     dailyBuckets       (raw rows
   [ProviderUsage]  [Date: DayBucket]   not exposed)
        │                 │
        ▼                 ▼
   PopoverView       DashboardView
   (Top models       (Heatmap +
    strip)            Account today +
                      Top Models card)
```

### 7.1 `ModelStatsPoller` extension

Add a published property:

```swift
@Published private(set) var dailyBuckets: [Date: DayBucket] = [:]

struct DayBucket: Equatable {
    let date: Date          // start of day, local timezone
    let quotaRaw: Int
    let usd: Double         // = quotaRaw / quotaPerUnit (computed at aggregate time)
    let requestCount: Int
    let topModels: [String] // top 3 raw model names by quota desc; ties broken alphabetically asc
}
```

Aggregation step in `aggregate(rows:)` (called after each `/api/data/self` response) groups rows by `Calendar.current.startOfDay(for: row.createdAt)` in addition to the existing per-provider rollup. Both outputs derive from the same single fetch.

### 7.2 Cache and refresh policy

- `ModelStatsPoller` already polls every 5 minutes; no new poller introduced
- Dashboard window observes `modelStats.dailyBuckets` and `modelStats.topProviders` — re-renders on change
- Initial open with empty data: cards render skeleton (gray cells / 0% bars), then animate in once data lands
- Manual refresh: dashboard window's toolbar `arrow.clockwise` button calls `Task { await modelStats.refresh() }`

## 8. Project Layout

```
APIStatusBar/
├─ APIStatusBarApp.swift                      # +WindowGroup(id: "dashboard")
├─ Core/
│  └─ ModelStatsPoller.swift                  # +dailyBuckets, +DayBucket
├─ UI/
│  ├─ PopoverView.swift                       # +chart.bar.xaxis button
│  └─ Dashboard/
│     ├─ DashboardView.swift                  # entry point, owns ScrollView + 3 cards
│     ├─ AccountCard.swift                    # 2x2 LabeledContent grid
│     ├─ HeatmapView.swift                    # 5x7 Grid, bucket logic, tooltips
│     └─ TopModelsCard.swift                  # 5-row progress list
```

## 9. Animations

- Window first appear: 3 cards slide in from `+8pt` y-offset + fade, staggered 80ms
- Heatmap cells initial render: each cell fades from `Theme.heatmapEmpty` to its target color, staggered 8ms × cellIndex (~280ms total — feels alive without sluggish)
- Top Models bars: width animates 0 → target on appear with `.spring(response: 0.5)`
- All numeric texts: `.contentTransition(.numericText())`
- Refresh button: 360° rotation on tap (matches popover's refresh affordance)

## 10. Testing

- **Unit (TDD):** `ModelStatsPoller.aggregate(rows:)` — given fixture rows, assert `dailyBuckets[date].usd` and `requestCount` totals match expected per-day sums; assert today's bucket exists when any row falls today
- **Unit:** Heatmap bucket logic — `bucket(forUSD:)` returns 0 / 1 / 2 / 3 / 4 at boundary edges
- **Unit:** Heatmap grid mapping — `cellIndex(for: Date)` returns correct (column, row) given today's weekday
- **Manual:** open dashboard against live new-api, verify 30 days of cells reflect actual usage, hover tooltips populate, today's cell has accent border

## 11. Failure Handling

| Scenario | Behavior |
|---|---|
| `/api/data/self` 401 / 5xx | `modelStats.lastError` set; dashboard cards keep last good data; account card hides "今日" if dailyBuckets empty; heatmap shows all-gray |
| Empty response (new account) | All cells gray, Top Models card shows "暂无用量数据" placeholder |
| Stale data (last fetch >10 min ago) | Subtle stale indicator: account card shows refresh-needed glyph, user can hit toolbar refresh |
| Window closed and reopened | Window re-uses cached `dailyBuckets`; first paint is instant |

## 12. Open Items

- Account "账户 N 天" deferred — needs `created_at` from `/api/user/self`. Mark as TODO in code with comment, unhide once backend exposes
- Heatmap bucket thresholds (`[$0.01, $1, $5, $20]`) are guesses for personal usage scale — might need adjustment after a week of real data
- Top Models v0.2: clicking a row could deep-link to `${serverURL}/console/log?model=...`. Out of scope for v0.1
- Top Channels card revisit when backend or Kaizo status feed exposes per-channel quota (not just heartbeat status)
