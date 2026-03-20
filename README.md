# CCDock

A native macOS menubar app for monitoring multiple AI coding agent sessions in parallel.

Supports **Claude Code**, **OpenAI Codex**, and **Google Gemini CLI**.

## Features

- **Real-time session monitoring** — See all active AI agent sessions at a glance
- **Status tracking** — Working / Waiting for input / Completed with animated indicators
- **One-click terminal jump** — Click a session to switch to its terminal window (tmux supported)
- **Floating panel** — Pin to desktop with frosted glass (vibrancy) effect
- **Native notifications** — Get notified when a session completes or needs input
- **Customizable layout** — Drag-and-drop editor to arrange info modules per your preference
- **Rich session info** — Duration, token usage, turn count, model, git branch, last prompt

## Install

### Homebrew (recommended)

```bash
brew install --cask YuHoYe/tap/ccdock
```

### Manual

Download the latest `.zip` from [Releases](https://github.com/YuHoYe/CCDock/releases), unzip, and move `CCDock.app` to `/Applications`.

### Build from source

```bash
git clone https://github.com/YuHoYe/CCDock.git
cd CCDock
./build-app.sh
open CCDock.app
```

## Requirements

- macOS 14.0 (Sonoma) or later
- One or more of: [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex CLI](https://github.com/openai/codex), [Gemini CLI](https://github.com/google-gemini/gemini-cli)

## How It Works

CCDock monitors local session files created by each AI agent:

| Agent | Data Source | Status Detection |
|-------|-----------|-----------------|
| Claude Code | `~/.claude/sessions/` + `ccnotify.db` | SQLite polling + JSONL parsing |
| Codex | `~/.codex/sessions/` | JSONL event stream parsing |
| Gemini CLI | `~/.gemini/tmp/` | `logs.json` modification time |

## License

MIT
