# Getting the Most Out of Upclaude

Upclaude monitors your Claude Code sessions from the macOS menu bar. It is a fork of [Clawdboard](https://github.com/apocohq/clawdboard); build it from source:

```bash
git clone https://github.com/koritsky/upclaude.git
cd upclaude
./scripts/bundle.sh
cp -R Upclaude.app /Applications/
open /Applications/Upclaude.app
```

The hooks are set up automatically when the app runs for the first time. There is no Homebrew cask or Claude Code plugin for Upclaude yet.

The rest of this document explains what gets configured and how to do it manually.

---

## How It Works

Upclaude uses Claude Code **hooks** to track session state. Each hook event (session start, tool use, stop, etc.) triggers a Python script that writes a JSON state file to `~/.upclaude/sessions/`. The menu bar app watches that directory and displays live status.

On top of that, there are two IDE-specific integrations that enable the "Focus" button — jumping from Upclaude directly to the right window/pane.

## Pathway 1: Terminal + iTerm2

### What You Get

- Real-time session status in the menu bar
- Context window usage, model, and git branch
- **"Focus in iTerm2"** — switches to the exact pane running that session, even in split panes

### Manual Setup

1. **Enable iTerm2 Python API**: iTerm2 → Settings → General → Magic → Enable Python API

2. **Install integration scripts** (from the repo):
   ```bash
   mkdir -p ~/.config/iterm2/AppSupport/Scripts/AutoLaunch
   cp Sources/UpclaudeLib/Resources/iterm2-integration.py \
      ~/.config/iterm2/AppSupport/Scripts/AutoLaunch/upclaude.py
   cp Sources/UpclaudeLib/Resources/iterm2-focus.py \
      ~/.upclaude/iterm2-focus.py
   chmod 755 ~/.config/iterm2/AppSupport/Scripts/AutoLaunch/upclaude.py \
             ~/.upclaude/iterm2-focus.py
   ```

   Or install from Upclaude's Settings: **iTerm2 Integration → Install**.

3. **Restart iTerm2** so it picks up the AutoLaunch script.

### How It Works

The AutoLaunch script runs in the background inside iTerm2, polling `~/.upclaude/sessions/` every 2 seconds. It matches Claude Code processes to iTerm2 panes by walking the process tree, then writes the pane UUID back into the session file. The "Focus" button uses AppleScript to select that pane.

**Inside zellij**: a multiplexer's server is detached from the pane's shell, so the process-tree match finds nothing. The hook records the session's zellij session and pane instead. On "Focus", the app finds the zellij client currently attached to that session, selects the iTerm2 pane that owns its terminal, and runs `zellij action focus-pane-id` to switch to the right tab and pane. This keeps working after the iTerm2 tab is closed and zellij is re-attached in another one. If no client is attached, it falls back to the pane named by `ITERM_SESSION_ID` at session start. tmux is not supported. Known limitation: right after re-attaching zellij, the first "Focus" brings the iTerm2 pane forward but may not switch the zellij tab until you have interacted with zellij once. Failed focus attempts are logged to `~/.upclaude/focus.log`.

---

## Pathway 2: VS Code + Native macOS Tabs

### What You Get

- Real-time session status in the menu bar
- Context window usage, model, and git branch
- **"Focus in VS Code"** — opens the correct workspace window
- **Native macOS tabs** — manage multiple Claude Code windows as tabs in one window

### Manual Setup

1. **Install the `code` CLI**: In VS Code, **Cmd+Shift+P → "Shell Command: Install 'code' command in PATH"**
   (For Cursor: `cursor`. For Insiders: `code-insiders`.)

2. **Enable native macOS tabs**: Add to VS Code settings (`Cmd+Shift+P → Preferences: Open User Settings (JSON)`):
   ```json
   "window.nativeTabs": true
   ```
   Restart VS Code after changing this.

3. **No additional hook setup needed** — the Claude Code VS Code extension automatically creates lock files that Upclaude reads.

### How It Works

The Claude Code extension writes lock files to `~/.claude/ide/` with workspace folders and PID. Upclaude matches each session's working directory to the most specific workspace folder. The "Focus" button runs `code <workspace-path>` to bring the correct window forward. Native macOS tabs let you merge all VS Code windows into one tabbed window (**Window → Merge All Windows**).

---

## Troubleshooting

**Sessions not appearing**: Hooks load at session start — restart running Claude Code sessions. Check `~/.claude/settings.json` has entries containing "upclaude".

**"Focus in iTerm2" missing**: Check Python API is enabled (Settings → General → Magic). Restart iTerm2 after installing scripts.

**"Focus in VS Code" missing**: Check `code --version` works in terminal. Make sure Claude Code is running inside VS Code, not a standalone terminal.

**Native tabs not working**: Restart VS Code after setting `"window.nativeTabs": true`. Use **Window → Merge All Windows** to combine existing windows.
