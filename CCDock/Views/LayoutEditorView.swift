import SwiftUI

// MARK: - 布局编辑器窗口

struct LayoutEditorView: View {
    private let settings = AppSettings.shared
    @State private var draggedField: DisplayField?

    private let previewSession = makePreviewSession()

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            previewSection
            Divider()
            slotsSection
            Divider()
            poolSection
        }
        .frame(width: 440, height: 580)
        .focusEffectDisabled()
    }

    // MARK: - 头部

    private var headerView: some View {
        HStack {
            Text("自定义布局")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button("恢复默认") { settings.resetToDefaults() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - 预览

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("预览")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            SessionRowPreview(session: previewSession, settings: settings)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - 槽位编辑

    private var slotsSection: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(LayoutSlot.allCases) { slot in
                    SlotEditorRow(slot: slot, settings: settings)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: - 模块池

    private var poolSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("可用模块（拖入上方槽位）")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            ModulePoolView(settings: settings)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private static func makePreviewSession() -> Session {
        var s = Session(from: SessionInfo(
            pid: 12345, sessionId: "preview",
            cwd: "/Users/demo/Developer/MyProject",
            startedAt: Int64((Date().timeIntervalSince1970 - 9000) * 1000)
        ))
        s.status = .working
        s.lastPrompt = "帮我实现登录功能"
        s.turnCount = 12
        s.totalTokens = 1_230_000
        s.model = "claude-opus-4-6"
        s.gitBranch = "main"
        return s
    }
}

// MARK: - 预览行

struct SessionRowPreview: View {
    let session: Session
    let settings: AppSettings

    var body: some View {
        HStack(spacing: 10) {
            leadingView
            centerView
            Spacer()
            rightView
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    @ViewBuilder private var leadingView: some View {
        let fields = settings.fields(in: .leading)
        ForEach(fields) { field in
            PreviewFieldView(field: field, session: session)
        }
    }

    private var centerView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(session.projectName)
                    .font(.system(size: 13, weight: .medium))
                ForEach(settings.fields(in: .titleTrailing)) { field in
                    PreviewFieldView(field: field, session: session)
                }
            }
            let sub = settings.fields(in: .subtitle)
            if !sub.isEmpty {
                HStack(spacing: 6) {
                    ForEach(sub) { f in PreviewFieldView(field: f, session: session) }
                }
            }
        }
    }

    private var rightView: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                ForEach(settings.fields(in: .topRight)) { f in PreviewFieldView(field: f, session: session) }
            }
            let br = settings.fields(in: .bottomRight)
            if !br.isEmpty {
                HStack(spacing: 6) {
                    ForEach(br) { f in PreviewFieldView(field: f, session: session) }
                }
            }
        }
    }
}

struct PreviewFieldView: View {
    let field: DisplayField
    let session: Session

    var body: some View {
        switch field {
        case .statusDot:
            Circle().fill(.blue).frame(width: 8, height: 8)
        case .agentIcon:
            Image(systemName: session.agentType.icon)
                .font(.system(size: 10))
                .foregroundStyle(.orange)
        case .statusText:
            Text(session.status.rawValue).font(.system(size: 10)).foregroundStyle(.secondary)
        case .lastPrompt:
            Text(session.lastPrompt ?? "").font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
        case .duration:
            Text(session.durationText).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
        case .turnCount:
            Label("\(session.turnCount)", systemImage: "bubble.left.and.bubble.right").font(.system(size: 9)).foregroundStyle(.tertiary)
        case .tokenUsage:
            Label(session.tokenText, systemImage: "gauge.low").font(.system(size: 9)).foregroundStyle(.tertiary)
        case .model:
            Text(session.modelShort).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
        case .gitBranch:
            Label(session.gitBranch ?? "", systemImage: "arrow.triangle.branch").font(.system(size: 9)).foregroundStyle(.tertiary)
        case .cwdPath:
            Text(session.cwd).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
        case .pid:
            Text("PID:\(session.pid)").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - 槽位编辑行

struct SlotEditorRow: View {
    let slot: LayoutSlot
    let settings: AppSettings
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(slot.rawValue)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            slotContent
                .padding(6)
                .background(slotBackground)
                .dropDestination(for: String.self) { items, _ in
                    guard let raw = items.first, let field = DisplayField(rawValue: raw) else { return false }
                    settings.layout.add(field, to: slot)
                    return true
                } isTargeted: { isTargeted = $0 }
        }
    }

    private var slotContent: some View {
        HStack(spacing: 4) {
            let fields = settings.fields(in: slot)
            if fields.isEmpty {
                Text("拖拽模块到此处")
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)
                    .frame(maxWidth: .infinity, minHeight: 28)
            } else {
                ForEach(fields) { field in
                    DraggableChip(field: field, onRemove: {
                        settings.layout.remove(field)
                    })
                }
                Spacer()
            }
        }
    }

    private var slotBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isTargeted ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08),
                        style: StrokeStyle(lineWidth: 1, dash: isTargeted ? [] : [4])
                    )
            )
    }
}

// MARK: - 可拖拽的模块标签

struct DraggableChip: View {
    let field: DisplayField
    let onRemove: () -> Void

    var body: some View {
        ModuleChip(field: field)
            .draggable(field.rawValue)
            .contextMenu {
                Button("移除") { onRemove() }
            }
    }
}

// MARK: - 模块池

struct ModulePoolView: View {
    let settings: AppSettings
    @State private var isTargeted = false

    var body: some View {
        let unassigned = settings.layout.unassignedFields
        Group {
            if unassigned.isEmpty {
                Text("拖拽模块到此处以移除")
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)
                    .frame(maxWidth: .infinity, minHeight: 32)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(unassigned) { field in
                        ModuleChip(field: field)
                            .draggable(field.rawValue)
                    }
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isTargeted ? Color.red.opacity(0.08) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isTargeted ? Color.red.opacity(0.3) : Color.clear,
                            style: StrokeStyle(lineWidth: 1, dash: [4])
                        )
                )
        )
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let field = DisplayField(rawValue: raw) else { return false }
            settings.layout.remove(field)
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

// MARK: - 模块标签

struct ModuleChip: View {
    let field: DisplayField
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: field.icon)
                .font(.system(size: 9))
            Text(field.rawValue)
                .font(.system(size: 11))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(isHovered ? 0.15 : 0.08))
        )
        .foregroundStyle(Color.accentColor)
        .onHover { isHovered = $0 }
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (i, pos) in result.positions.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxW = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxW, x > 0 {
                x = 0; y += rowH + spacing; rowH = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowH = max(rowH, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }
        return (positions, CGSize(width: maxX, height: y + rowH))
    }
}
