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
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            // 状态变化时记录时间
            if sessions[index].status != status {
                sessions[index].statusChangedAt = Date()
            }
            sessions[index].status = status
        }
    }

    func updatePrompt(sessionId: String, prompt: String) {
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[index].lastPrompt = prompt
        }
    }

    func updateMetrics(sessionId: String, turnCount: Int, totalTokens: Int, model: String?, gitBranch: String?, version: String?) {
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[index].turnCount = turnCount
            sessions[index].totalTokens = totalTokens
            if let model = model { sessions[index].model = model }
            if let branch = gitBranch { sessions[index].gitBranch = branch }
            if let ver = version { sessions[index].version = ver }
        }
    }

    func activeSessionIds() -> Set<String> {
        Set(sessions.map { $0.id })
    }

    func activeSessionIds(for agentType: AgentType) -> Set<String> {
        Set(sessions.filter { $0.agentType == agentType }.map { $0.id })
    }
}
