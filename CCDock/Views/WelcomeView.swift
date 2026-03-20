import SwiftUI

struct WelcomeView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 32)

            // App Icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            Spacer().frame(height: 16)

            Text("CCDock")
                .font(.system(size: 28, weight: .bold))

            Text("AI 编程助手会话监控面板")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            Spacer().frame(height: 28)

            // 功能介绍
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "menubar.arrow.up.rectangle",
                    color: .blue,
                    title: "常驻菜单栏",
                    subtitle: "点击右上角  图标查看所有会话"
                )
                FeatureRow(
                    icon: "eye",
                    color: .orange,
                    title: "实时状态监控",
                    subtitle: "工作中 / 等待输入 / 已完成，一目了然"
                )
                FeatureRow(
                    icon: "rectangle.on.rectangle",
                    color: .green,
                    title: "一键跳转终端",
                    subtitle: "点击会话直达对应终端窗口"
                )
                FeatureRow(
                    icon: "pin",
                    color: .purple,
                    title: "悬浮面板",
                    subtitle: "可固定到桌面任意位置"
                )
            }
            .padding(.horizontal, 32)

            Spacer().frame(height: 28)

            // 支持的 Agent
            HStack(spacing: 20) {
                AgentTag(name: "Claude Code", color: .orange)
                AgentTag(name: "Codex", color: .green)
                AgentTag(name: "Gemini", color: .blue)
            }

            Spacer().frame(height: 28)

            Button(action: onStart) {
                Text("开始使用")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.blue))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)

            Spacer().frame(height: 24)
        }
        .frame(width: 360, height: 520)
    }
}

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AgentTag: View {
    let name: String
    let color: Color

    var body: some View {
        Text(name)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .cornerRadius(6)
    }
}
