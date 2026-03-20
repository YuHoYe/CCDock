import Foundation

enum AgentType: String {
    case claude = "Claude Code"
    case codex = "Codex"
    case gemini = "Gemini"

    var icon: String {
        switch self {
        case .claude: return "c.circle.fill"
        case .codex: return "o.circle.fill"
        case .gemini: return "g.circle.fill"
        }
    }

    var shortName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        }
    }
}

enum SessionStatus: String {
    case working = "工作中"
    case waitingInput = "等待输入"
    case idle = "完成"
    case unknown = "未知"
}

struct SessionInfo: Codable {
    let pid: Int
    let sessionId: String
    let cwd: String
    let startedAt: Int64
}

struct Session: Identifiable {
    let id: String
    let pid: Int
    let cwd: String
    let startedAt: Date
    var agentType: AgentType = .claude
    var status: SessionStatus
    var lastPrompt: String?
    var tty: String?
    var turnCount: Int = 0
    var totalTokens: Int = 0
    var model: String?
    var gitBranch: String?
    var version: String?
    var statusChangedAt: Date?

    /// 距上次状态变化的时间文字，如 "3m"、"1h20m"
    var statusDurationText: String {
        guard let changedAt = statusChangedAt else { return "" }
        let seconds = Int(Date().timeIntervalSince(changedAt))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainMinutes = minutes % 60
        return remainMinutes > 0 ? "\(hours)h\(remainMinutes)m" : "\(hours)h"
    }

    var projectName: String {
        (cwd as NSString).lastPathComponent
    }

    var durationText: String {
        let seconds = Int(Date().timeIntervalSince(startedAt))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainMinutes = minutes % 60
        if remainMinutes > 0 { return "\(hours)h\(remainMinutes)m" }
        return "\(hours)h"
    }

    var tokenText: String {
        if totalTokens == 0 { return "" }
        if totalTokens >= 1_000_000 {
            return String(format: "%.1fM", Double(totalTokens) / 1_000_000.0)
        }
        if totalTokens >= 1_000 {
            return String(format: "%.0fK", Double(totalTokens) / 1_000.0)
        }
        return "\(totalTokens)"
    }

    /// 模型简称: "claude-opus-4-6" → "opus-4-6", "gpt-5" → "gpt-5"
    var modelShort: String {
        guard let model = model else { return "" }
        return model
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "models/", with: "")
    }

    init(from info: SessionInfo) {
        self.id = info.sessionId
        self.pid = info.pid
        self.cwd = info.cwd
        self.startedAt = Date(timeIntervalSince1970: Double(info.startedAt) / 1000.0)
        self.status = .unknown
    }

    init(id: String, pid: Int, cwd: String, startedAt: Date, agentType: AgentType) {
        self.id = id
        self.pid = pid
        self.cwd = cwd
        self.startedAt = startedAt
        self.agentType = agentType
        self.status = .unknown
    }
}
