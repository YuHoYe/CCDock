# CCDock

[![Build](https://github.com/YuHoYe/CCDock/actions/workflows/build.yml/badge.svg)](https://github.com/YuHoYe/CCDock/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/YuHoYe/CCDock)](https://github.com/YuHoYe/CCDock/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-14.0%2B-brightgreen)](https://www.apple.com/macos/sonoma/)

**macOS 原生菜单栏应用，并行监控多个 AI 编程助手会话。**

在日常开发中，你可能同时运行多个 Claude Code、Codex 或 Gemini CLI 会话处理不同项目。CCDock 常驻菜单栏，让你一眼看清所有会话状态，点击即跳转到对应终端窗口。

<!--
## Screenshots

TODO: 添加应用截图
-->

## ✨ Features

- 🔵 **实时状态监控** — 工作中 / 等待输入 / 已完成，带颜色指示条和动态 Badge
- 🤖 **多 Agent 支持** — Claude Code、OpenAI Codex、Google Gemini CLI
- 🖱️ **一键跳转终端** — 点击会话直达对应终端窗口（支持 Ghostty / iTerm2 / Terminal.app / tmux）
- 📌 **悬浮面板** — 可固定到桌面任意位置，毛玻璃效果
- 🔔 **原生通知** — 会话完成或需要输入时弹出通知
- 🎨 **自定义布局** — 拖拽编辑器，自由排列显示模块
- 📊 **丰富信息** — 时长、Token 用量、轮数、模型、Git 分支、最近 Prompt

## 📦 Install

### Homebrew（推荐）

```bash
brew install --cask YuHoYe/tap/ccdock
```

### 手动下载

从 [Releases](https://github.com/YuHoYe/CCDock/releases) 下载最新 `.zip`，解压后将 `CCDock.app` 拖入 `/Applications`。

> 应用已通过 Apple Developer ID 签名并完成公证（Notarization），可直接运行。

### 从源码构建

```bash
git clone https://github.com/YuHoYe/CCDock.git
cd CCDock
./build-app.sh
open CCDock.app
```

## 🔧 Requirements

- macOS 14.0 (Sonoma) or later
- 以下 AI 编程助手至少安装一个：
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
  - [Codex CLI](https://github.com/openai/codex)
  - [Gemini CLI](https://github.com/google-gemini/gemini-cli)

## 🛠 How It Works

CCDock 通过监听各 Agent 在本地创建的会话文件来发现和追踪会话状态，**不需要任何额外配置**。

| Agent | 会话数据 | 状态检测方式 |
|-------|---------|-------------|
| Claude Code | `~/.claude/sessions/` + `ccnotify.db` | SQLite 轮询 + JSONL 解析 |
| Codex | `~/.codex/sessions/` | JSONL 事件流解析 |
| Gemini CLI | `~/.gemini/tmp/` | `logs.json` 修改时间检测 |

### 状态机

```
              用户提交 Prompt
  完成 ─────────────────────────► 工作中
    ▲                                │
    │           响应完成              │ 响应完成
    └────────────────────────────────┘
                                     │
                                     │ 通知 "waiting for input"
                                     ▼
                                等待输入
                                     │
                                     │ 用户提交 Prompt
                                     └──────► 工作中
```

## 🏗 Architecture

```
CCDock/
├── Models/          # 数据模型（Session, AppSettings）
├── Store/           # @Observable 状态管理
├── Services/        # 会话发现 + 状态轮询 + 终端跳转
└── Views/           # SwiftUI 视图 + NSPanel
```

技术栈：**SwiftUI + AppKit** 混合架构，使用 Swift Package Manager 构建。

- `NSPanel` + `.floating` 实现 Always-on-Top
- `@Observable` (Swift 5.9+) 驱动 UI 更新
- `DispatchSource` 监听文件系统变化
- AppleScript + Accessibility API 实现终端窗口跳转

## 🤝 Contributing

欢迎贡献！请查看 [CONTRIBUTING.md](CONTRIBUTING.md) 了解详情。

无论是 Bug 报告、功能建议还是代码贡献，我们都非常欢迎：

- 🐛 [报告 Bug](https://github.com/YuHoYe/CCDock/issues/new?template=bug_report.md)
- 💡 [功能建议](https://github.com/YuHoYe/CCDock/issues/new?template=feature_request.md)
- 🔧 [提交 PR](https://github.com/YuHoYe/CCDock/pulls)

## 📄 License

[MIT](LICENSE) © YuHo
