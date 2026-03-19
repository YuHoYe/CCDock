import SwiftUI

// MARK: - Popover 内容

struct PopoverContentView: View {
    let delegate: AppDelegate

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(delegate: delegate)
            Divider().opacity(0.3)
            SessionListView(store: delegate.store, activator: delegate.activator)
            Divider().opacity(0.3)
            StatusBarView(sessions: delegate.store.sessions)
        }
        .frame(width: 340)
        .focusEffectDisabled()
    }
}

// MARK: - Pin 模式内容

struct PinnedContentView: View {
    let delegate: AppDelegate

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                DragBar()
                Spacer()
            }
            .overlay(alignment: .trailing) {
                Button(action: { delegate.isPinned = false }) {
                    Image(systemName: "pin.slash")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("取消固定")
                .padding(.trailing, 10)
            }

            SessionListView(store: delegate.store, activator: delegate.activator)
            Divider().opacity(0.3)
            StatusBarView(sessions: delegate.store.sessions)
        }
        .focusEffectDisabled()
    }
}

struct ToolbarView: View {
    let delegate: AppDelegate

    var body: some View {
        HStack(spacing: 0) {
            Text("CCDock")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            ToolbarButton(icon: "pin", help: "固定到桌面") {
                delegate.isPinned = true
            }

            ToolbarButton(icon: "slider.horizontal.3", help: "自定义布局") {
                delegate.openLayoutEditor()
            }

            ToolbarButton(icon: "power", help: "退出") {
                delegate.quit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct ToolbarButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

// MARK: - 状态指示圆点

struct StatusDot: View {
    let status: SessionStatus
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
            .opacity(dotOpacity)
            .animation(dotAnimation, value: isPulsing)
            .onAppear { isPulsing = true }
            .onChange(of: status) { isPulsing = true }
    }

    private var statusColor: Color {
        switch status {
        case .working: return .blue
        case .waitingInput: return .orange
        case .idle: return .green
        case .unknown: return .gray.opacity(0.5)
        }
    }

    private var dotOpacity: Double {
        switch status {
        case .working: return isPulsing ? 1.0 : 0.4
        case .waitingInput: return isPulsing ? 1.0 : 0.2
        default: return 1.0
        }
    }

    private var dotAnimation: Animation? {
        switch status {
        case .working:
            return .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
        case .waitingInput:
            return .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
        default: return nil
        }
    }
}

// MARK: - 单行会话（基于槽位布局渲染）

struct SessionRowView: View {
    let session: Session
    let onTap: () -> Void
    private let settings = AppSettings.shared

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 10) {
            // Leading slot
            ForEach(settings.fields(in: .leading)) { field in
                fieldView(field)
            }

            // Title + subtitle
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.projectName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    ForEach(settings.fields(in: .titleTrailing)) { field in
                        fieldView(field)
                    }
                }

                let subtitleFields = settings.fields(in: .subtitle)
                if !subtitleFields.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(subtitleFields) { field in
                            fieldView(field)
                        }
                    }
                }
            }

            Spacer()

            // Right side
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    ForEach(settings.fields(in: .topRight)) { field in
                        fieldView(field)
                    }
                }
                let brFields = settings.fields(in: .bottomRight)
                if !brFields.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(brFields) { field in
                            fieldView(field)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(isHovered ? 0.08 : 0.0))
        )
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.easeInOut(duration: 0.3), value: session.status)
        .animation(.easeOut(duration: 0.15), value: isPressed)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.1)) { isPressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 0.1)) { isPressed = false }
                onTap()
            }
        }
        .help(session.cwd)
    }

    @ViewBuilder
    private func fieldView(_ field: DisplayField) -> some View {
        switch field {
        case .statusDot:
            StatusDot(status: session.status)
        case .agentIcon:
            Image(systemName: session.agentType.icon)
                .font(.system(size: 10))
                .foregroundStyle(agentColor(session.agentType))
                .help(session.agentType.rawValue)
        case .statusText:
            Text(session.status.rawValue).font(.system(size: 10)).foregroundStyle(.secondary)
        case .lastPrompt:
            if let prompt = session.lastPrompt, !prompt.isEmpty {
                let truncated = prompt.count > 30 ? String(prompt.prefix(30)) + "…" : prompt
                Text(truncated).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
            }
        case .duration:
            Text(session.durationText).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
        case .turnCount:
            if session.turnCount > 0 {
                Label("\(session.turnCount)", systemImage: "bubble.left.and.bubble.right").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        case .tokenUsage:
            if !session.tokenText.isEmpty {
                Label(session.tokenText, systemImage: "gauge.low").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        case .model:
            if !session.modelShort.isEmpty {
                Text(session.modelShort).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
            }
        case .gitBranch:
            if let branch = session.gitBranch, !branch.isEmpty {
                Label(branch, systemImage: "arrow.triangle.branch").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        case .cwdPath:
            Text(session.cwd).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
        case .pid:
            Text("PID:\(session.pid)").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
        }
    }

    private func agentColor(_ type: AgentType) -> Color {
        switch type {
        case .claude: return .orange
        case .codex: return .green
        case .gemini: return .blue
        }
    }
}

// MARK: - 底部统计栏

struct StatusBarView: View {
    let sessions: [Session]

    var body: some View {
        let total = sessions.count
        let workingCount = sessions.filter { $0.status == .working }.count
        let waitingCount = sessions.filter { $0.status == .waitingInput }.count
        let totalTokens = sessions.reduce(0) { $0 + $1.totalTokens }

        HStack(spacing: 0) {
            Text(summaryText(total: total, working: workingCount, waiting: waitingCount))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            if totalTokens > 0 {
                Text(formatTokens(totalTokens))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func summaryText(total: Int, working: Int, waiting: Int) -> String {
        var parts = ["\(total) 个会话"]
        if working > 0 { parts.append("\(working) 个工作中") }
        if waiting > 0 { parts.append("\(waiting) 个等待") }
        return parts.joined(separator: " · ")
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "共 %.1fM tokens", Double(count) / 1_000_000.0) }
        if count >= 1_000 { return String(format: "共 %.0fK tokens", Double(count) / 1_000.0) }
        return "共 \(count) tokens"
    }
}

// MARK: - 会话列表

struct SessionListView: View {
    let store: SessionStore
    let activator: TerminalActivator

    var body: some View {
        if store.sessions.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 20))
                    .foregroundStyle(.tertiary)
                Text("没有活跃的会话")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
            }
            .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(store.sessions) { session in
                        SessionRowView(session: session) {
                            activator.activate(session: session)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - 拖拽条

struct DragBar: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.primary.opacity(0.15))
            .frame(width: 32, height: 4)
            .padding(.top, 8)
            .padding(.bottom, 6)
    }
}
