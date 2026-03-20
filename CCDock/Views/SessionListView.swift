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
        .frame(minWidth: 320, idealWidth: 380, maxHeight: 520)
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
        ZStack {
            // 等待输入时：外圈呼吸光晕
            if status == .waitingInput {
                Circle()
                    .fill(Color.orange.opacity(0.3))
                    .frame(width: isPulsing ? 16 : 8, height: isPulsing ? 16 : 8)
                    .opacity(isPulsing ? 0 : 0.6)
            }
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .opacity(dotOpacity)
        }
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
        case .waitingInput: return 1.0
        default: return 1.0
        }
    }

    private var dotAnimation: Animation? {
        switch status {
        case .working:
            return .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
        case .waitingInput:
            return .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
        default: return nil
        }
    }
}

// MARK: - 单行会话（方案 C：彩色左边条 + Badge + 状态时长）

struct SessionRowView: View {
    let session: Session
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false
    @State private var barPulsing = false

    var body: some View {
        HStack(spacing: 12) {
            // 左侧：项目名 + badge + 状态时长 + prompt
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(session.projectName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                    StatusBadge(session: session)
                }

                // 等待输入时：单独一行突出显示等待时长
                if session.status == .waitingInput {
                    Text("等待 \(session.statusDurationText.isEmpty ? "刚刚" : session.statusDurationText)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.orange)
                        .opacity(barPulsing ? 1.0 : 0.5)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: barPulsing)
                }

                if let prompt = session.lastPrompt, !prompt.isEmpty {
                    let truncated = prompt.count > 40 ? String(prompt.prefix(40)) + "…" : prompt
                    Text(truncated)
                        .font(.system(size: 11))
                        .foregroundStyle(session.status == .idle ? .quaternary : .tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // 右侧：总时长 + 统计（降低视觉权重）
            VStack(alignment: .trailing, spacing: 3) {
                Text(session.durationText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(session.status == .idle ? .quaternary : .tertiary)

                HStack(spacing: 6) {
                    if session.turnCount > 0 {
                        Text("\(session.turnCount) 轮")
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                    }
                    if !session.tokenText.isEmpty {
                        Text(session.tokenText)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.quaternary)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(statusBackgroundColor)
        )
        // 左侧彩色边条
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(statusAccentColor)
                .frame(width: session.status == .waitingInput ? 5 : 4)
                .opacity(session.status == .waitingInput ? (barPulsing ? 1.0 : 0.4) : 1.0)
                .padding(.vertical, 4)
                .animation(
                    session.status == .waitingInput
                        ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                        : nil,
                    value: barPulsing
                )
        }
        .onAppear { barPulsing = true }
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

    private var titleColor: Color {
        if session.justCompleted { return .primary }
        switch session.status {
        case .waitingInput: return .primary
        case .working: return .primary
        case .idle: return .secondary
        case .unknown: return .secondary
        }
    }

    private var statusAccentColor: Color {
        if session.justCompleted { return .green }
        switch session.status {
        case .working: return .blue
        case .waitingInput: return .orange
        case .idle: return .green
        case .unknown: return .gray.opacity(0.3)
        }
    }

    private var statusBackgroundColor: Color {
        if session.justCompleted { return isHovered ? .green.opacity(0.2) : .green.opacity(0.15) }
        switch session.status {
        case .working: return isHovered ? .blue.opacity(0.1) : .blue.opacity(0.05)
        case .waitingInput: return isHovered ? .orange.opacity(0.15) : .orange.opacity(0.1)
        case .idle: return isHovered ? .white.opacity(0.05) : .white.opacity(0.02)
        case .unknown: return isHovered ? .white.opacity(0.05) : .clear
        }
    }
}

// MARK: - 状态 Badge

struct StatusBadge: View {
    let session: Session

    var body: some View {
        HStack(spacing: 3) {
            if session.status == .waitingInput {
                Text("⚠")
                    .font(.system(size: 10))
            }
            if session.status == .idle {
                Text(session.justCompleted ? "✅" : "✓")
                    .font(.system(size: 10))
            }
            Text(badgeText)
                .font(.system(size: 11, weight: badgeWeight))
        }
        .foregroundStyle(badgeTextColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(badgeBackground)
        .cornerRadius(4)
    }

    private var badgeText: String {
        let statusLabel = session.status.rawValue
        let duration = session.statusDurationText

        switch session.status {
        case .working:
            return duration.isEmpty ? statusLabel : "\(statusLabel) \(duration)"
        case .waitingInput:
            return statusLabel
        case .idle:
            return session.justCompleted ? "刚刚完成!" : (duration.isEmpty ? statusLabel : "\(duration) 前完成")
        case .unknown:
            return statusLabel
        }
    }

    private var badgeWeight: Font.Weight {
        if session.justCompleted { return .bold }
        return session.status == .waitingInput ? .bold : .regular
    }

    private var badgeBackground: Color {
        if session.justCompleted { return .green }
        switch session.status {
        case .working: return .blue.opacity(0.2)
        case .waitingInput: return .orange
        case .idle: return .green.opacity(0.1)
        case .unknown: return .gray.opacity(0.1)
        }
    }

    private var badgeTextColor: Color {
        if session.justCompleted { return .white }
        switch session.status {
        case .working: return .blue
        case .waitingInput: return .black
        case .idle: return .green.opacity(0.7)
        case .unknown: return .gray
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
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            if totalTokens > 0 {
                Text(formatTokens(totalTokens))
                    .font(.system(size: 12, design: .monospaced))
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
                VStack(spacing: 1) {
                    ForEach(store.sessions) { session in
                        SessionRowView(session: session) {
                            if session.justCompleted {
                                store.clearJustCompleted(sessionId: session.id)
                            }
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
