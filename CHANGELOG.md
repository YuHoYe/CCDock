# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [1.1.0] - 2025-03-20

### Added

- First-launch welcome screen with feature overview
- Click "开始使用" automatically opens pinned floating panel

### Fixed

- App crash on other machines due to `Bundle.module` fatalError
- Now builds as universal binary (Apple Silicon + Intel)
- Icon not loading in release builds

## [1.0.0] - 2025-03-20

### Added

- Real-time monitoring for Claude Code, Codex, and Gemini CLI sessions
- Status tracking with visual indicators (Working / Waiting / Completed)
- One-click terminal window jump (supports Ghostty, iTerm2, Terminal.app, tmux)
- Floating panel mode with drag-and-drop positioning
- Native macOS notifications for session state changes
- Customizable layout editor with drag-and-drop modules
- Token usage, turn count, model, and git branch display
- Homebrew Cask installation support
- Code signed and notarized for macOS Gatekeeper

[1.1.0]: https://github.com/YuHoYe/CCDock/releases/tag/v1.1.0
[1.0.0]: https://github.com/YuHoYe/CCDock/releases/tag/v1.0.0
