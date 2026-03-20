import Foundation
import Observation

@Observable
class SessionStore {
    var sessions: [Session] = []

    func upsert(_ session: Session) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index].tty = session.tty ?? sessions[index].tty
        } else {
            sessions.append(session)
        }
    }

    func remove(sessionId: String) {
        sessions.removeAll { $0.id == sessionId }
    }

    func updateStatus(sessionId: String, status: SessionStatus) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        guard sessions[index].status != status else { return }
        // working → idle 时标记为"刚完成"
        let wasWorking = sessions[index].status == .working
        sessions[index].statusChangedAt = Date()
        sessions[index].status = status
        if wasWorking && status == .idle {
            sessions[index].justCompleted = true
        }
    }

    func clearJustCompleted(sessionId: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[index].justCompleted = false
    }

    func updatePrompt(sessionId: String, prompt: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        guard sessions[index].lastPrompt != prompt else { return }
        sessions[index].lastPrompt = prompt
    }

    func updateMetrics(sessionId: String, turnCount: Int, totalTokens: Int, model: String?, gitBranch: String?, version: String?) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        var changed = false
        if sessions[index].turnCount != turnCount { sessions[index].turnCount = turnCount; changed = true }
        if sessions[index].totalTokens != totalTokens { sessions[index].totalTokens = totalTokens; changed = true }
        if let model = model, sessions[index].model != model { sessions[index].model = model; changed = true }
        if let branch = gitBranch, sessions[index].gitBranch != branch { sessions[index].gitBranch = branch; changed = true }
        if let ver = version, sessions[index].version != ver { sessions[index].version = ver; changed = true }
        _ = changed // suppress unused warning
    }

    func activeSessionIds() -> Set<String> {
        Set(sessions.map { $0.id })
    }

    func activeSessionIds(for agentType: AgentType) -> Set<String> {
        Set(sessions.filter { $0.agentType == agentType }.map { $0.id })
    }

    /// Demo 模式用的 mock 数据，展示各种会话状态
    static func mock() -> SessionStore {
        let store = SessionStore()
        let now = Date()

        var working = Session(id: "mock-1", pid: 1001, cwd: "/Users/dev/my-web-app", startedAt: now.addingTimeInterval(-1800), agentType: .claude)
        working.status = .working
        working.statusChangedAt = now.addingTimeInterval(-120)
        working.lastPrompt = "重构用户认证模块，使用 JWT 替换 session"
        working.turnCount = 12
        working.totalTokens = 285_000
        working.model = "claude-opus-4-6"

        var waiting = Session(id: "mock-2", pid: 1002, cwd: "/Users/dev/ios-app", startedAt: now.addingTimeInterval(-3600), agentType: .claude)
        waiting.status = .waitingInput
        waiting.statusChangedAt = now.addingTimeInterval(-45)
        waiting.lastPrompt = "添加深色模式支持，需要确认配色方案"
        waiting.turnCount = 8
        waiting.totalTokens = 156_000
        waiting.model = "claude-sonnet-4-6"

        var completed = Session(id: "mock-3", pid: 1003, cwd: "/Users/dev/api-server", startedAt: now.addingTimeInterval(-900), agentType: .claude)
        completed.status = .idle
        completed.justCompleted = true
        completed.statusChangedAt = now.addingTimeInterval(-5)
        completed.lastPrompt = "修复分页查询的 N+1 问题"
        completed.turnCount = 5
        completed.totalTokens = 98_000
        completed.model = "claude-sonnet-4-6"

        var codex = Session(id: "mock-4", pid: 1004, cwd: "/Users/dev/data-pipeline", startedAt: now.addingTimeInterval(-2400), agentType: .codex)
        codex.status = .working
        codex.statusChangedAt = now.addingTimeInterval(-60)
        codex.lastPrompt = "优化 ETL 管道的并发处理"
        codex.turnCount = 3
        codex.totalTokens = 42_000

        var gemini = Session(id: "mock-5", pid: 1005, cwd: "/Users/dev/ml-model", startedAt: now.addingTimeInterval(-5400), agentType: .gemini)
        gemini.status = .idle
        gemini.statusChangedAt = now.addingTimeInterval(-300)
        gemini.lastPrompt = "训练数据预处理脚本"
        gemini.turnCount = 6

        store.sessions = [working, waiting, completed, codex, gemini]
        return store
    }
}
