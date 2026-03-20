# Contributing to CCDock

感谢你对 CCDock 的关注！欢迎任何形式的贡献。

## 如何贡献

### 报告 Bug

1. 在 [Issues](https://github.com/YuHoYe/CCDock/issues) 中搜索是否已有类似问题
2. 如果没有，创建新 Issue，请包含：
   - macOS 版本
   - CCDock 版本
   - 使用的 AI Agent（Claude Code / Codex / Gemini CLI）
   - 复现步骤
   - 期望行为 vs 实际行为

### 功能建议

欢迎在 [Issues](https://github.com/YuHoYe/CCDock/issues) 中提交功能建议，请打上 `enhancement` 标签。

### 提交代码

1. Fork 本仓库
2. 创建你的功能分支：`git checkout -b feature/my-feature`
3. 提交更改：`git commit -m "Add my feature"`
4. 推送到你的 Fork：`git push origin feature/my-feature`
5. 提交 Pull Request

### 开发环境

```bash
# 克隆仓库
git clone https://github.com/YuHoYe/CCDock.git
cd CCDock

# 构建运行
./build-app.sh
open CCDock.app
```

**要求：**
- macOS 14.0+ (Sonoma)
- Swift 5.9+
- Xcode Command Line Tools

### 项目结构

```
CCDock/
├── CCDock/
│   ├── CCDockApp.swift           # App 入口
│   ├── Models/
│   │   ├── Session.swift         # 会话数据模型
│   │   └── AppSettings.swift     # 应用设置
│   ├── Store/
│   │   └── SessionStore.swift    # 状态管理
│   ├── Services/
│   │   ├── SessionDiscovery.swift    # Claude Code 会话发现
│   │   ├── CodexDiscovery.swift      # Codex 会话发现
│   │   ├── GeminiDiscovery.swift     # Gemini 会话发现
│   │   ├── StatusPoller.swift        # 状态轮询
│   │   ├── CodexPoller.swift         # Codex 状态轮询
│   │   └── TerminalActivator.swift   # 终端窗口跳转
│   └── Views/
│       ├── FloatingPanel.swift       # 悬浮面板
│       ├── SessionListView.swift     # 会话列表
│       └── LayoutEditorView.swift    # 布局编辑器
├── Package.swift
└── build-app.sh
```

### 代码风格

- 使用 Swift 标准命名规范
- 保持代码简洁，遵循 KISS 原则
- 添加必要的注释说明 "为什么"，而不是 "做了什么"

## 行为准则

请参阅 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)。

## 许可

提交的代码将遵循 [MIT License](LICENSE)。
