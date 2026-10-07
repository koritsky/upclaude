# Clawdboard

Native macOS menu bar app (SwiftUI) for monitoring Claude Code agent sessions.

## Build & Run

```bash
mise run setup    # Install tools and git hooks
mise run build    # swift build
mise run run      # swift run Clawdboard
mise run test     # swift test
mise run format   # Auto-fix formatting
mise run lint     # Check formatting + lint
```

## Tooling

- **mise** manages tool versions and dev tasks. Define new workflow commands as `[tasks.*]` in `.mise.toml`, not as raw shell scripts.
- **swift-format** (Apple's, bundled with Swift toolchain) is the authoritative formatter. Config in `.swift-format`.
- **swiftlint** for additional lint rules. Config in `.swiftlint.yml` — rules are tuned to not conflict with swift-format.
- **Pre-commit hook** runs `mise run pre-commit` (swift-format + swiftlint on staged files). Generated via `mise generate git-pre-commit --write`.

## Architecture

- **SPM library + executable split**: `ClawdboardLib` (all code) + `Clawdboard` (thin `@main` entry point) + `ClawdboardTests` (imports ClawdboardLib). This is required because SPM executable targets can't be imported by test targets.
- **Swift 5 language mode** in Swift 6 toolchain (avoids strict concurrency fights for a PoC).
- **Hooks-first session discovery**: Claude hooks write state files to `~/.clawdboard/sessions/`. The Swift app just reads JSON — all JSONL parsing, cost calculation, and token counting happens in the hook script (`Sources/ClawdboardLib/Resources/clawdboard-hook.py`).
- **Single `@Observable` AppState** owned by the App struct, distributed via `.environment()`.
- **Status is derived in the hook** from `active_tools` / `agent_working`; `Stop` does a full reset to `waiting` (no debounce). **Ghost filtering** in `SessionProcessor` hides sessions that never produced output (30s if never updated, 5min idle).

## Design

- **`docs/DESIGN.md`** is the design manual — colors, typography, layout constants, icons, animations, and every visual component. **Before making any UI/design changes, consult this document first, discuss the change, and update `docs/DESIGN.md` to reflect the new state.** Code and design doc must stay in sync.

## Commit Conventions

- **Conventional Commits**: `type(scope): short summary` — types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `revert`, `style`, `perf`, `ci`, `build`.
- **Scope**: Optional but encouraged (e.g., `feat(ui):`, `fix(hook):`, `docs(design):`).
- **Body**: Optional concise bullet points for non-trivial changes.
- **Trailer**: Configured via `.claude/settings.json` `attribution` — do not add manually.
- **Branch naming**: `type/short-description` (e.g., `feat/session-history`, `fix/stale-timer`). Same type prefixes as commits.

## Key Paths

- `Sources/ClawdboardLib/Resources/clawdboard-hook.py` — Python script installed as Claude hook
- `Sources/ClawdboardLib/` — all library code (models, state, views, discovery)
- `Sources/Clawdboard/ClawdboardApp.swift` — app entry point
- `scripts/bundle.sh` — creates `.app` bundle from release binary
