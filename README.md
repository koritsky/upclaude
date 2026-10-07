<div align="center">

# Upclaude

### Mission Control for AI Agents

**Every idle agent is wasted capacity.**

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/platform-macOS-black.svg)]()
[![GitHub stars](https://img.shields.io/github/stars/koritsky/upclaude?style=social)](https://github.com/koritsky/upclaude/stargazers)

<!-- 🚀 Product Hunt badge goes here after launch -->

</div>

<p align="center"><img src="assets/demo.gif" width="640" alt="Upclaude demo" /></p>

---

> **Upclaude is a fork of [Clawdboard](https://github.com/apocohq/clawdboard) by [apocohq](https://github.com/apocohq).** It is developed independently and uses its own app name, bundle id, and `~/.upclaude` data directory, so it can be installed alongside the original.

You're running five agents. One needs approval. Two are stuck. **Upclaude sits in your menu bar and shows you which Claude Code session needs your attention.** One click and you're there.

<table align="center">
<tr><th>Agents in your workflow</th><th>Need Upclaude?</th></tr>
<tr><td>1–2</td><td>Probably not (yet)</td></tr>
<tr><td>3–5</td><td>Yes</td></tr>
<tr><td>5+</td><td>Yesterday</td></tr>
</table>

## What Upclaude Solves

**See everything at a glance**
- Status for every session: working, waiting, needs approval, abandoned
- Context window usage: know when an agent is running hot
- Model and git branch display

**Get there in one click**
- Focus in iTerm2: jumps to the exact terminal pane
- Focus in iTerm2 + zellij: brings the iTerm2 pane forward, then switches to the session's zellij tab and pane ([details](docs/SETUP.md#pathway-1-terminal--iterm2))
- Focus in VS Code: opens the right workspace window
- Focus in JetBrains: opens the project, clicks the exact terminal tab

**Works how you work**
- Remote host monitoring via SSH
- Auto-cleanup of stale and crashed sessions
- Native macOS: menu bar, not a browser tab

## Get started

Build from source (requires Xcode with the Swift 6 toolchain):

```bash
git clone https://github.com/koritsky/upclaude.git
cd upclaude
./scripts/bundle.sh
cp -R Upclaude.app /Applications/
open /Applications/Upclaude.app
```

The hooks are set up automatically when the app runs for the first time.

There is no Homebrew cask or Claude Code plugin for Upclaude yet; the upstream `apocohq` cask and plugin install the original Clawdboard, not this fork.

> See the [Setup Guide](docs/SETUP.md) for details on what gets configured and manual installation.

### JetBrains terminal tab focus

For Upclaude to focus the exact terminal tab in JetBrains IDEs, two things are needed:

1. **Disable Claude Code's built-in terminal title** — add to your `~/.bashrc` or `~/.zshrc`:
   ```bash
   export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1
   ```
2. **Install the [Terminal Tab Tailor](https://plugins.jetbrains.com/plugin/23903-terminal-tab-tailor) plugin** in your JetBrains IDE — this propagates ANSI title escapes to the tab name.

## How it works

Upclaude uses Claude Code's [hooks system](https://docs.anthropic.com/en/docs/claude-code/hooks) to receive real-time session events. No polling, no screen scraping, no daemon. Just hooks.

## Development

Requires: Swift 6 toolchain, [mise](https://mise.jdx.dev/)

```bash
mise run setup     # Install tools and git hooks
mise run build     # swift build
mise run run       # swift run Upclaude
mise run test      # swift test
mise run format    # Auto-fix formatting
mise run lint      # Check formatting + lint
```

See [CLAUDE.md](CLAUDE.md) for architecture details and conventions.

### Watch Mode

To run the app with auto-restart on every code change:

```bash
mise run dev
```

## Contributing

We're building fast. If you're into Swift, macOS dev, or just want better agent tooling: [PRs welcome](https://github.com/koritsky/upclaude/issues).

## Star this repo ⭐

You'll get notified when we ship updates. We're shipping a lot.

## Built with

Swift 6 · SwiftUI · macOS native · [Claude Code Hooks API](https://docs.anthropic.com/en/docs/claude-code/hooks)

---

MIT License · Fork of [Clawdboard](https://github.com/apocohq/clawdboard) · Built for [Claude Code](https://claude.ai/code)