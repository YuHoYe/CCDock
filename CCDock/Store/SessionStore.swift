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
}
