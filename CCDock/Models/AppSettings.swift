import Foundation
import Observation

/// 可展示的信息模块
enum DisplayField: String, CaseIterable, Identifiable, Codable {
    case statusDot = "状态指示"
    case agentIcon = "Agent 图标"
    case statusText = "状态文字"
    case lastPrompt = "最近 Prompt"
    case duration = "运行时长"
    case turnCount = "对话轮数"
    case tokenUsage = "Token 用量"
    case model = "模型"
    case gitBranch = "Git 分支"
    case cwdPath = "工作目录"
    case pid = "PID"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .statusDot: return "circle.fill"
        case .agentIcon: return "cpu"
        case .statusText: return "text.badge.checkmark"
        case .lastPrompt: return "text.bubble"
        case .duration: return "clock"
        case .turnCount: return "bubble.left.and.bubble.right"
        case .tokenUsage: return "gauge.low"
        case .model: return "cpu"
        case .gitBranch: return "arrow.triangle.branch"
        case .cwdPath: return "folder"
        case .pid: return "number"
        }
    }

    /// 预览用的示例值
    var previewText: String {
        switch self {
        case .statusDot: return "●"
        case .agentIcon: return "C"
        case .statusText: return "工作中"
        case .lastPrompt: return "帮我实现登录功能…"
        case .duration: return "2h30m"
        case .turnCount: return "12"
        case .tokenUsage: return "1.2M"
        case .model: return "opus-4-6"
        case .gitBranch: return "main"
        case .cwdPath: return "/Developer/MyProject"
        case .pid: return "PID:12345"
        }
    }
}

/// 槽位定义
enum LayoutSlot: String, CaseIterable, Identifiable, Codable {
    case leading = "左侧图标"
    case titleTrailing = "标题右侧"
    case subtitle = "副标题行"
    case topRight = "右上角"
    case bottomRight = "右下角"

    var id: String { rawValue }
}

/// 布局配置：每个槽位放了哪些模块
struct LayoutConfig: Codable, Equatable {
    var slots: [LayoutSlot: [DisplayField]]

    static let defaultLayout = LayoutConfig(slots: [
        .leading: [.statusDot],
        .titleTrailing: [.agentIcon],
        .subtitle: [.lastPrompt],
        .topRight: [.statusText, .duration],
        .bottomRight: [.turnCount, .tokenUsage],
    ])

    func fields(in slot: LayoutSlot) -> [DisplayField] {
        slots[slot] ?? []
    }

    /// 所有已分配的字段
    var assignedFields: Set<DisplayField> {
        Set(slots.values.flatMap { $0 })
    }

    /// 未分配的字段
    var unassignedFields: [DisplayField] {
        DisplayField.allCases.filter { !assignedFields.contains($0) }
    }

    mutating func add(_ field: DisplayField, to slot: LayoutSlot) {
        // 先从所有槽位移除
        remove(field)
        var arr = slots[slot] ?? []
        arr.append(field)
        slots[slot] = arr
    }

    mutating func remove(_ field: DisplayField) {
        for slot in LayoutSlot.allCases {
            slots[slot]?.removeAll { $0 == field }
        }
    }

    mutating func insert(_ field: DisplayField, in slot: LayoutSlot, at index: Int) {
        remove(field)
        var arr = slots[slot] ?? []
        let safeIndex = min(index, arr.count)
        arr.insert(field, at: safeIndex)
        slots[slot] = arr
    }
}

// CodingKeys for LayoutSlot as Dictionary key
extension LayoutSlot: CodingKeyRepresentable {}

/// 持久化设置
@Observable
class AppSettings {
    static let shared = AppSettings()

    var layout: LayoutConfig {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: "layoutConfig"),
           let decoded = try? JSONDecoder().decode(LayoutConfig.self, from: data) {
            layout = decoded
        } else {
            layout = .defaultLayout
        }
    }

    func fields(in slot: LayoutSlot) -> [DisplayField] {
        layout.fields(in: slot)
    }

    func resetToDefaults() {
        layout = .defaultLayout
    }

    private func save() {
        if let data = try? JSONEncoder().encode(layout) {
            UserDefaults.standard.set(data, forKey: "layoutConfig")
        }
    }
}
