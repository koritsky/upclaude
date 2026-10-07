# Upclaude Design Manual

Component catalog documenting the visual language of the Upclaude menu bar panel.
Use this as a reference when making UI changes, discussing design, or onboarding contributors.

Icons follow [Apple's SF Symbols HIG](https://developer.apple.com/design/human-interface-guidelines/sf-symbols). Prefer outlined variants for actions, filled for status indicators. Match symbol weight to adjacent text.

## Overview

- **Type**: macOS menu bar panel (+ optional detached floating window)
- **Width**: 420pt fixed
- **Theme**: Inherits system appearance (light/dark) via semantic SwiftUI colors
- **Design philosophy**: Compact, information-dense, monospaced for technical data

## Color System

All colors are semantic SwiftUI values — they adapt automatically to light/dark mode.

### Status Colors

| Status | Color | Used in |
|--------|-------|---------|
| Working / Pending | Claude orange `#D97757` | StatusMark spinner (rows, header counts, menu bar). Subagent dots stay `.blue` |
| Approve | `.red` | StatusMark dot (rows, header counts), menu bar dot |
| Your turn (waiting) | Neutral grey (`.secondary`; menu bar foreground at 60%) | StatusMark asterisk (rows, header counts, menu bar) |
| Inactive (abandoned) | `.gray` at 40% opacity | StatusDot |
| Unknown | `.gray` | StatusDot |

> **Accessibility**: Red and green are indistinguishable for ~8% of men with color vision deficiency. The critical approve/"your turn" distinction does not rely on color alone — the text label in the metadata line provides a secondary signal.

### Usage Gauge Colors

All usage indicators (context bar, activity chart, usage progress bar) share the same color scale and thresholds. The middle band is yellow, not orange: orange is reserved for Claude's "working" spinner.

| Range | Color | Meaning |
|-------|-------|---------|
| 0–69% | `.secondary` | Healthy |
| 70–89% | `.yellow` | Elevated — worth noting |
| 90%+ | `.red` | Critical — action likely needed |

Applied to: ContextBar (horizontal, per-session context window), SparklineView (stroke, by the session's latest context value), UsageWindowView (horizontal, account usage limits).

### Text Hierarchy

| Level | Style | Use |
|-------|-------|-----|
| Primary | `.primary` (implicit) | Session titles, app title |
| Secondary | `.secondary` | Metadata, labels, action icons, section headers |
| Tertiary | `.tertiary` | Timestamps, empty state, refresh tooltip |

### Backgrounds

| Element | Color |
|---------|-------|
| Gauge tracks (bar) | `.quaternary` |
| Session row | `.quaternary` at 50% opacity |
| Status pill | Status color at 12% opacity |

---

## Components

### Menu Bar Label
**File**: `Sources/Upclaude/UpclaudeApp.swift`

The menu bar icon adapts based on session state:

**Idle (no active sessions)**: `apple.terminal` SF Symbol (template mode). If usage is above threshold, shows a usage ring instead.

**Active sessions**: One mark per session, ordered by urgency. No text — just marks.

| State | Mark |
|-------|------|
| Needs approval | Red dot (`.systemRed`), 8pt. The only state that blocks an agent, so the only one in an alert color |
| Your turn | Grey asterisk `✻`: the menu bar's own foreground color at 60%, so it follows wallpaper tinting |
| Working | Claude Code's spinner in Claude orange (`#D97757`): steps through `· ✢ ✳ ✶ ✻ ✽` and back. With Reduce Motion on, a static orange `✻` |

The asterisks mirror Claude Code itself: its spinner while it works, a grey asterisk when it is idle. The panel keeps its blue/green status colors; only the menu bar differs.

| Property | Value |
|----------|-------|
| Slot | 8pt wide, 4pt apart |
| Asterisk size | 12pt square centered on its slot (13pt bold system font), so neighbors sit edge to edge |
| Edge padding | 2pt each side of the image, so the outermost asterisks aren't clipped |
| Max marks | 8 (capped) |
| Template mode | `false` when marks shown (preserves color) |
| Usage ring | 14pt diameter, 2.5pt stroke, appended after the marks if above threshold |
| Spinner drawing | `MenuBarSpinnerAnimator` overlays the status item button; the SwiftUI label leaves working slots empty and is never animated (doing so breaks clicks) |

---

### StatusMark
**File**: `Sources/UpclaudeLib/Views/Components.swift`

A session's status, drawn the same way in the panel as in the menu bar.

| Status | Mark |
|--------|------|
| Working | Claude Code's spinner in Claude orange, stepping through `· ✢ ✳ ✶ ✻ ✽` and back on the menu bar's schedule. A static `✻` with Reduce Motion on |
| Your turn | Grey `✻` (`.secondary`) |
| Needs approval | Red `StatusDot` |
| Unknown / inactive | Grey `StatusDot` |

| Property | Value |
|----------|-------|
| Frame | 14×14pt |
| Asterisk font | 13pt bold system font |

### StatusDot
**File**: `Sources/UpclaudeLib/Views/Components.swift`

Colored circle, used by StatusMark for the states that are not asterisks.

| Property | Value |
|----------|-------|
| Size | 8×8pt |
| Shape | Filled `Circle()` |

---

### StatusCount
**File**: `Sources/UpclaudeLib/Views/PanelView.swift`

Header summary: how many sessions are in a state, as that state's StatusMark followed by the number. Hidden when the count is zero. The state's name is in the tooltip, not on screen.

| Property | Value |
|----------|-------|
| Count font | `.caption.monospacedDigit().weight(.medium)`, `.secondary` |
| Mark-to-count spacing | 3pt || Dot-to-text spacing | 3pt |
| Pill-to-pill spacing | 6pt |
| Padding | 6pt horizontal, 2pt vertical |
| Text font | `.caption2` |
| Labels | "N approve" (red), "N your turn" (green), "N working" (blue) |

Only shown when count > 0 for that status.

---

### ContextBar
**File**: `Sources/UpclaudeLib/Views/Components.swift`

Horizontal progress bar showing context window usage.

| Property | Value |
|----------|-------|
| Height | 4pt |
| Corner radius | 2pt |
| Track color | `.quaternary` |
| Fill width | Proportional to percentage (capped at 100%) |

**Fill color**: Uses the shared usage gauge color scale (see Color System).

---

### SparklineView
**File**: `Sources/UpclaudeLib/Views/Components.swift`

Miniature line chart showing context usage over time per session.

| Property | Value |
|----------|-------|
| Size | 80 x 24pt |
| Stroke width | 1pt |
| Fill opacity | 15% under line |
| Min data points | 2 snapshots to render |
| Max snapshots | 100 (capped in hook) |
| Renderer | SwiftUI `Canvas` |

**Stroke color**: Uses the shared usage gauge color scale based on latest value (see Color System).

**Placement**: Trailing edge of session row, between content and chevron, paired with PR status icon. Only shown for hook-tracked sessions with 2+ snapshots.

---

### PRStatusIcon
**File**: `Sources/UpclaudeLib/Views/Components.swift`

Displays the pull request status for a session's branch using custom-drawn GitHub-style icons (SwiftUI Canvas). Falls back to a commit count badge when no PR exists but commits were made during the session. PR data fetched via `gh` CLI on the Swift side (`PRStatusProvider`); commit data comes from the hook script.

| Property | Value |
|----------|-------|
| Icon size | 14 x 14pt (PR icons), 10 x 10pt (commit icon) |
| Badge min size | 24 x 24pt (PR), auto-widens for commit count (28pt for 2+ digits) |
| Badge corner radius | 6pt |
| Badge background | Icon color at 12% opacity (22% on hover) |
| Badge border | Icon color at 30% opacity (50% on hover), 0.5pt |

**Priority**: PR status always wins. Commit badge shown only when `prInfo` is `.none` or `nil` and `commitCount > 0`.

**PR States**:
| Status | Icon | Color | Click action |
|--------|------|-------|------|
| No PR / unknown (no commits) | Dashed rounded rectangle outline (no icon) | `.tertiary` | None |
| PR open | `PROpenIcon` — Phosphor git-pull-request | `.green` | Opens PR URL |
| PR merged | `PRMergedIcon` — Phosphor git-merge | `.purple` | Opens PR URL |
| PR closed | `PRClosedIcon` — Phosphor git-pull-request | `.secondary` | Opens PR URL |

**Commit Badge States** (shown when no PR exists):
| Condition | Color | Click action |
|-----------|-------|------|
| All pushed (`unpushedCount == 0`) | `.purple` | Opens GitHub compare URL (`start_sha...head_sha`) |
| Has unpushed (`unpushedCount > 0`) | `.secondary` (subtle background) | Opens GitHub compare URL |
| No upstream (`unpushedCount == nil`) | `.secondary` (subtle background) | Opens GitHub compare URL (if available) |

**Commit badge layout**: Phosphor git-commit icon (10pt) + count text in `.system(size: 9, weight: .semibold).monospacedDigit()`, 1pt spacing, 2pt horizontal padding. Badge widens to 28pt for 2+ digit counts.

All commit badge states use solid border + tinted background (same style as PR badges). Unpushed commits use `.secondary` for a subtle white-ish appearance; transitions to `.purple` (matching merged PR color) once all commits are pushed.

**Dirty indicator**: A 5pt `.blue` dot overlaid on the top-trailing corner of the badge (offset x:1, y:-1). Shown when the session's working tree has uncommitted changes (`gitDirty == true`). Disappears when all changes are committed. Data comes from `git status --porcelain` in the hook script.

**Placement**: Trailing edge of collapsed session row, after sparkline. Always shown (dashed rectangle when no PR or commit data available).

**Data sources**:
- PR data: `PRStatusProvider` polls `gh pr list` with 30s per-session debounce. Requires `gh` CLI to be installed and authenticated. Cache persisted to `~/.upclaude/pr-status-cache.json` for instant display on app launch.
- Commit data: Hook script captures `start_sha` at session start and tracks `head_sha`, `commit_count`, `unpushed_count` on each event via local `git rev-list` / `git rev-parse` commands.

---

### UsageWindowView (Progress Bar)
**File**: `Sources/UpclaudeLib/Views/Components.swift`

Horizontal progress bar for account usage limits.

| Property | Value |
|----------|-------|
| Bar height | 8pt |
| Corner radius | 2pt |
| Track color | `.quaternary` |
| Fill width | Proportional to utilization (capped at 100%) |
| Estimated marker | 1pt wide vertical line, `.primary` at 40% opacity, 8pt tall, positioned at estimated % |

**Bar color**: Uses the shared usage gauge color scale (see Color System).

**Layout** (VStack, 3pt spacing):
- Header row: Percentage in `.caption.monospacedDigit().weight(.semibold)`, bar color | Spacer | Window label ("5h" / "7d") in `.caption.weight(.semibold)`, `.secondary`
- Progress bar with estimated marker overlay
- Footer row: Projection (`on pace for N%`) in `.caption2.monospacedDigit()` | Spacer | Reset time in `.caption2.monospacedDigit()`, `.tertiary`. The projection is where usage ends up if the current rate holds: `.secondary` up to 100%, `.yellow` above 100%, `.red` from 150%. Its tooltip says so in a sentence

Two windows side by side in an HStack with 24pt spacing.

---

### AgentRow
**File**: `Sources/UpclaudeLib/Views/AgentRow.swift`

Single session row. Full row is the primary click target (Fitts's Law).

| Property | Value |
|----------|-------|
| Row padding | 6pt vertical, 8pt horizontal |
| Background | `.quaternary.opacity(0.5)`, 6pt corner radius |
| Hover background | `.quaternary.opacity(0.8)`, 0.1s ease-in-out |
| Element spacing | 8pt (HStack) |
| Expand animation | 0.15s ease-in-out |
| Fallback opacity | 0.6 — non-hook-tracked sessions are visually dimmed to signal incomplete data |

**Interaction model**:
- **Click anywhere on row** = focus session (best available: iTerm2 > VS Code). Falls back to expand/collapse if no IDE/terminal is available.
- **Disclosure chevron** (trailing edge) = toggle expand/collapse explicitly.
- **Right-click context menu** = Focus in iTerm2, Focus in VS Code/Cursor, Copy Session ID, Delete Session.
- **Hover** = background brightens (0.5 → 0.8 opacity) + pointing hand cursor when a focus action is available.

**Layout**: `StatusMark` | Title + status line (VStack) | Spacer | Sparkline + PRStatusIcon, each only when it has something to show | Disclosure chevron

**Title**: `.system(.body, weight: .medium)`. Single line, truncated. Shows AI-generated kebab-case slug title (e.g. `api-refactor`, `auth-module`, `docs-update`) when available, otherwise a placeholder slug like `new-session` (stable per session ID).

**Status line**: `.caption`, `.secondary`, one line: the most recent prompt in quotes, truncated at the tail. Nothing else — the status is the StatusMark at the start of the row, and the machine and directory are in the group header. A session with no prompt yet shows its branch, or failing that its status label, so the line is never empty. The branch is otherwise in the expanded details.

**Widgets**: the Sparkline is shown only with at least two context snapshots in its window, and the PRStatusIcon only when there is a pull request or session commits; otherwise they would be an empty baseline and an empty dashed box. With neither PR nor commits, uncommitted changes show as a bare 6pt `.blue` dot.

**Branch** (inline in metadata):
- Plain text (no icon — PR status is shown via trailing PRStatusIcon)
- If `githubRepo` set: tapping opens `https://github.com/<repo>/compare/<branch>?expand=1` (GitHub redirects to existing PR or shows "Open a pull request" page)
- If no git repo: branch hidden entirely
- Pointing hand cursor on hover

**Diff stats** (expanded details only):
- Format: `+N −N` with `.caption.monospacedDigit()`
- Additions colored `.green`, deletions colored `.red`
- Hidden when no diff data or both zero

**Disclosure chevron** (trailing edge):
- SF Symbol: `chevron.right` (collapsed) / `chevron.down` (expanded)
- Font: `.system(size: 10, weight: .semibold)`, `.tertiary`
- Hit target: 20×20pt, `.plain` button style
- Clicking toggles expand/collapse independently of the row click

**Context menu** (right-click):
- "Focus in iTerm2" (`apple.terminal`) — shown if iTerm2 session exists
- "Focus in VS Code" / "Focus in Cursor" (`macwindow`) — shown if IDE lock exists, label derived from IDE name
- Divider (if any focus actions above)
- "Copy Session ID" (`doc.on.doc`) — always shown
- Divider
- "Delete Session" (`trash`, destructive) — always shown

**Expanded details** (below main row):
- Divider with 2pt vertical padding
- Context bar row: label (60pt) + bar + percentage
- Prompt (most recent, up to 2 lines) and Reply (first line of Claude's last message, up to 3 lines), in the regular `.caption` font
- DetailRow entries: Host, Model (as spoken, followed by the effort the last turn ran at when known, e.g. "Opus 5.5 · medium"), Branch, Changes (+N −N colored), Commits (count + push status), Session (first 8 characters, with a `doc.on.doc` button copying the full id), Uptime (since the session first started; kept across restarts and resumes), Path
- The title is not repeated here
- Subagents section: "Agents" label (60pt, trailing-aligned) + green 5×5pt dots, agent type, truncated ID — aligned with DetailRow labels
- "Restart session for full tracking" warning in `.caption2`, `.orange` (if not hook-tracked)
- Actions row: "Focus in iTerm2" / "Focus in <IDE>" (`arrow.up.forward.app`, `.borderless`, aligned with the values) on the left when the session can be focused; delete button (`trash` icon in `.caption`, `.tertiary`, 28×28pt hit target) on the right — hidden in the collapsed row to prevent accidental clicks

---

### DetailRow
**File**: `Sources/UpclaudeLib/Views/Components.swift`

Key-value pair in expanded detail grid.

| Property | Value |
|----------|-------|
| Label width | 60pt, trailing-aligned |
| Label font | `.caption`, `.secondary` |
| Value font | `.caption.monospaced()`, one line, middle-truncated. Prose values (Prompt, Reply) use `.caption`, wrap up to their line limit, and truncate at the tail |
| Truncation | Single line, middle truncation |

---

### Section Headers (Collapsible)
**File**: `Sources/UpclaudeLib/Views/SessionsTab.swift`

Group headers for sessions by project, machine, and working directory. For GitHub repos, the org prefix is stripped (e.g., "acme/my-app" → "MY-APP"). The header then says where those sessions work: `~/code/my-app` on this machine, `host:~/code/my-app` on a remote one. The home directory is shortened to `~` on either; a remote session reports its own home, and until it has (hook not yet updated) its path is shown in full. The same repo in two directories or on two machines gets a header for each. Tapping the header toggles collapse/expand of the group.

| Property | Value |
|----------|-------|
| Font | `.caption.weight(.semibold)` |
| Color | `.secondary` |
| Case | `.uppercase` |
| Padding | 8pt leading, 4pt trailing, 10pt top (except first group) |
| Location | After the name, 8pt gap, `.caption.monospaced()`, `.tertiary`, not uppercased (paths and host names are case-sensitive), one line, middle-truncated, full text in the tooltip |
| Chevron | `chevron.right` (collapsed) / `chevron.down` (expanded), 8pt system, `.semibold`, `.tertiary` |
| Chevron-to-text spacing | 4pt |
| Collapse animation | 0.15s ease-in-out |
| Session count badge | Shown when collapsed, `.caption2.monospacedDigit()`, `.tertiary`, trailing |

---

### Panel Header
**File**: `Sources/UpclaudeLib/Views/PanelView.swift`

| Element | Spec |
|---------|------|
| Title | "Upclaude" in `.headline` |
| Alignment | `.firstTextBaseline` |
| Status counts | `StatusCount` per state (approve, your turn, working), right-aligned, 10pt spacing |
| Padding | 12pt horizontal, 10pt top, 6pt bottom |

---

### Panel Footer
**File**: `Sources/UpclaudeLib/Views/PanelView.swift`

| Element | Spec |
|---------|------|
| Session count | `.caption`, `.secondary` |
| Float button | `pin` / `pin.fill` icon, `.caption`, `.secondary` — opens or closes the floating window; tooltip explains it |
| Refresh button | `arrow.clockwise` icon, `.caption`, `.secondary` — tooltip shows "Usage updated N ago" |
| Settings menu | `gearshape` icon, `.caption`, `.secondary`, no menu indicator |
| Padding | 12pt horizontal, 8pt vertical |

---

### Empty State
**File**: `Sources/UpclaudeLib/Views/PanelView.swift`

Shown when no sessions exist.

| Element | Spec |
|---------|------|
| Icon | `apple.terminal` SF Symbol, `.title2`, `.tertiary` |
| Title | "No active sessions", `.subheadline`, `.secondary` |
| Subtitle | "Start a Claude Code session to see it here", `.caption`, `.tertiary` |
| Spacing | 6pt between elements |
| Padding | 24pt vertical |

---

## Layout Constants

| Constant | Value |
|----------|-------|
| Panel width | 420pt |
| Header padding | 12pt H, 10pt top, 6pt bottom |
| Footer padding | 12pt H, 8pt V |
| Usage limits padding | 12pt H, 8pt V |
| Stats-to-sessions gap | 8pt (Spacer below usage limits) |
| Sessions list height (menu bar panel) | Fits content, capped at 60% of the screen's visible height; scrolls beyond that |
| Sessions list height (detached window) | Fills the window; scrolls when content overflows |
| Sessions scroll top padding | 10pt (inside ScrollView) |
| Sessions scroll fade | 8pt linear gradient mask (clear → black) at top |
| Sessions list padding | 8pt H, 10pt top, 4pt bottom |
| Session group spacing | 4pt (VStack) |
| Inter-group gap | 10pt top padding |
| Usage windows spacing | 24pt between bars (HStack) |

---

## Icons (SF Symbols)

| Icon | Use | Size/Style |
|------|-----|------------|
| `apple.terminal` | Empty state, menu bar idle | `.title2` |
| `apple.terminal` | Focus iTerm2 | `.body` |
| `macwindow` | Focus IDE (VS Code, JetBrains, etc.) | `.body` |
| `arrow.triangle.pull` | PR / branch link (metadata line) | `.caption2` |
| `trash` | Delete session (expanded detail) | `.caption` |
| `arrow.up.forward.app` | Focus session (expanded detail) | `.caption` |
| `doc.on.doc` | Copy session ID (expanded detail, context menu) | `.caption2` |
| `pin` / `pin.fill` | Open / close the floating window (footer) | `.caption` |
| `chevron.right` / `chevron.down` | Section collapse toggle | 8pt system, `.semibold` |
| `network` | Remote Hosts tab | Settings |
| `gearshape` | Settings menu | `.caption` |
| `speaker.wave.2` | Preview alert sound | Settings |
| `arrow.clockwise` | Refresh usage (footer) | `.caption` |
| `checkmark.circle.fill` | Hooks installed (green) | Settings |
| `xmark.circle` | No hooks (orange) | Settings |
| `exclamationmark.triangle` | SSH error (red) | Settings |
| `questionmark.circle` | Unchecked host (gray) | Settings |
| `plus` | Add remote host | Settings |
| `pencil` | Edit remote host | Settings |
| `trash` | Delete remote host | Settings |

---

## Typography Scale

| Use | Font Spec | Notes |
|-----|-----------|-------|
| App title | `.headline` | "Upclaude" in header |
| Session title | `.body` weight `.medium` | AI-generated or placeholder |
| Metadata | `.caption` | Dot-separated, `.secondary` |
| Small labels | `.caption2` | Context %, pill text |
| Technical data | `.caption.monospaced()` | Paths, session IDs, detail values |
| Numeric data | `.monospacedDigit()` | Percentages, timing, counters |
| Usage percentage | `.caption.monospacedDigit().weight(.semibold)` | Bar header |
| Window label | `.caption.weight(.semibold)` | "5h", "7d" |
| Empty state icon | `.title2` | SF Symbol |
| Empty state title | `.subheadline` | |

---

## Animations

| Animation | Duration | Curve | Details |
|-----------|----------|-------|---------|
| Row hover | 0.1s | ease-in-out | Background opacity 0.5↔0.8, bound to `isHovered` state |
| Row expand/collapse | 0.15s | ease-in-out | Bound to `isExpanded` state |
| Group collapse/expand | 0.15s | ease-in-out | Bound to `collapsedGroups` state |
| Menu bar spinner | 1.68s cycle | discrete | `· ✢ ✳ ✶ ✻ ✽` out and back at 0.12s per frame (Claude Code's step), resting 0.36s on `·` and `✽`. A `contents` keyframe animation on the status item overlay. Not shown when Reduce Motion is on |

---

## Audio Alerts

| Trigger | Behavior |
|---------|----------|
| Session transitions to **needs approval** | Plays user-configured sound file (MP3/WAV/AIFF/M4A) if set |

- Configured in Settings → General → **Notifications** section
- "Choose..." opens a native file picker; the selected file is stored as a security-scoped bookmark so it persists across app restarts
- Preview button (`speaker.wave.2`) plays the sound inline
- "Clear" removes the configured sound
- Sound plays once per transition — a session already in approval state won't re-trigger on subsequent rebuilds

## System Notifications

Standard macOS notifications, posted by `NotificationManager`. Both are opt-in toggles in Settings → General → **Notifications**, off by default.

| Line | Finished (working → your turn) | Needs approval |
|------|--------------------------------|----------------|
| Title | `project · session title` | `project · session title` |
| Subtitle | `Finished after 4m · branch` | `Needs approval · Bash` |
| Body | First line of Claude's reply; falls back to your last prompt in quotes | The command, or the file/URL/pattern the tool wants to act on |

- The project name is the one shown in the panel's group header
- Turn length is omitted for the turn in progress when the app is first updated; branch and tool name are omitted when unknown
- Body is a single line, cut at 200 characters
- One notification per session — a newer event replaces the older one
- Removed from the screen and Notification Center once it is no longer news: you focus the session (from the app, by clicking the notification, or by switching to its pane yourself — checked every 2s while a notification is showing), it starts working again, or it ends. AppleScript-fallback notifications can't be removed
- Silent; the approval alert sound above is separate
- Clicking a notification focuses the session, same as clicking its row
- A session seen for the first time never triggers one
- Skipped when you are already looking at the session: iTerm2 is the frontmost app and showing its pane (inside zellij, also its zellij pane). Sessions in an IDE are always notified
- macOS asks for notification permission when a toggle is first turned on
- Fallback: when the app can't post its own notification — unbundled development builds (`swift run`), or macOS refusing permission, as it does for ad-hoc signed bundles — it posts through `terminal-notifier` if installed (Homebrew or Nix paths), with a click command that focuses the session in iTerm2/zellij. Without `terminal-notifier` it uses AppleScript: that notification appears under Script Editor and clicking it opens Script Editor

---

### DiffStatsLabel
**File**: `Sources/UpclaudeLib/Views/AgentRow.swift`

Inline colored diff stats (used in both metadata line and expanded details).

| Property | Value |
|----------|-------|
| Font | `.caption.monospacedDigit()` |
| Additions color | `.green` |
| Deletions color | `.red` |
| Format | `+N −N` (space-separated, each part independently colored) |

---

### DiffStatsProvider
**File**: `Sources/UpclaudeLib/DiffStatsProvider.swift`

Reactive diff stats collector. Triggered by session changes (no timer/polling) with per-session debounce. Results kept in memory — no state file writes, no rebuild loops.

| Property | Value |
|----------|-------|
| Trigger | Reactive — fires on every `rebuildSessions()` (i.e. every hook event) |
| Debounce | 3 seconds per session (skips if fetched recently) |
| Command | `git diff --shortstat origin/<default>..HEAD` |
| Targets | All local non-abandoned sessions with a `cwd` |
| Storage | In-memory cache (`diffStatsCache`) — merged into sessions by `AppState.mergeDiffStats()` |
| Default branch cache | Cached per-cwd for the session lifetime (avoids repeated lookups) |
| Value dedup | Callback only fires when values actually change |
| Performance | `git diff --shortstat` ~3ms, default branch resolve ~4ms (first call only) |

---

## Session Sort Order

Sessions are sorted by urgency (most attention-needed first):

1. **Approve** (sort order 0)
2. **Your turn** (sort order 1)
3. **Pending/Working** (sort order 2–3)
4. **Unknown** (sort order 4)
5. **Inactive/Abandoned** (sort order 5)

Within each status group, sessions are grouped alphabetically by GitHub repo slug (or project name for local repos), displayed as uppercase section headers.

---

## Platform Behavior

Upclaude must respect standard macOS behaviors. Never hardcode values that the system provides dynamically.

### Appearance Adaptation

- **Menu bar tinting**: The menu bar appearance is driven by the desktop wallpaper, not system dark/light mode. All menu bar elements must visually match the system's menu bar tinting — colored status dots keep their explicit colors, but neutral elements (e.g. the usage ring) must adapt.
- **Semantic colors**: Use semantic colors throughout the panel UI so they adapt to light/dark mode automatically.
- **Dynamic appearance**: The app must react to appearance changes (wallpaper changes, dark mode toggle, space switches) and redraw affected elements. Never assume appearance is static for the lifetime of the app.
