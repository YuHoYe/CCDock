import Foundation

/// 轮询 Codex 会话状态
/// 通过解析 jsonl 中的事件类型推断状态
class CodexPoller {
    private let store: SessionStore
    private let sessionsDir: String
    private var timer: Timer?

    init(store: SessionStore) {
        self.store = store
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.sessionsDir = "\(home)/.codex/sessions"
    }

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let codexSessions = store.sessions.filter { $0.agentType == .codex }
        for session in codexSessions {
            let metrics = parseCodexLog(sessionId: session.id)
            if let status = metrics.status {
                store.updateStatus(sessionId: session.id, status: status)
            }
            if let prompt = metrics.lastPrompt {
                store.updatePrompt(sessionId: session.id, prompt: prompt)
            }
            store.updateMetrics(
                sessionId: session.id,
                turnCount: metrics.turnCount,
                totalTokens: metrics.tokens,
                model: metrics.model,
                gitBranch: nil,
                version: metrics.version
            )
        }
    }

    private struct CodexMetrics {
        var status: SessionStatus?
        var lastPrompt: String?
        var tokens: Int = 0
        var turnCount: Int = 0
        var model: String?
        var version: String?
    }

    private func parseCodexLog(sessionId: String) -> CodexMetrics {
        // 在 sessions 目录中搜索匹配的 jsonl 文件
        guard let path = findSessionFile(sessionId: sessionId) else { return CodexMetrics() }
        guard let handle = FileHandle(forReadingAtPath: path) else { return CodexMetrics() }
        defer { handle.closeFile() }

        let data = handle.readDataToEndOfFile()
        guard let content = String(data: data, encoding: .utf8) else { return CodexMetrics() }

        var metrics = CodexMetrics()
        var lastEventType: String?

        for line in content.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            let type = obj["type"] as? String ?? ""

            if type == "session_meta", let payload = obj["payload"] as? [String: Any] {
                metrics.version = payload["cli_version"] as? String
            }

            if type == "event_msg", let payload = obj["payload"] as? [String: Any] {
                let eventType = payload["type"] as? String ?? ""
                lastEventType = eventType
                if eventType == "task_started" {
                    metrics.turnCount += 1
                }
            }

            // 从 response_item 提取 user prompt
            if type == "response_item", let payload = obj["payload"] as? [String: Any] {
                let role = payload["role"] as? String
                if role == "user", let content = payload["content"] as? [[String: Any]] {
                    for c in content {
                        if c["type"] as? String == "input_text", let text = c["text"] as? String {
                            // 过滤掉系统指令
                            if !text.hasPrefix("<") && text.count < 500 {
                                metrics.lastPrompt = text
                            }
                        }
                    }
                }
                // 提取 model
                if let model = payload["model"] as? String {
                    metrics.model = model
                }
            }
        }

        // 根据最后的事件类型推断状态
        switch lastEventType {
        case "task_started": metrics.status = .working
        case "task_completed": metrics.status = .idle
        default: metrics.status = .unknown
        }

        // 如果文件最近被修改且有 task_started 但没 task_completed，就是 working
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let modDate = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modDate) < 30 {
            if metrics.status == .unknown { metrics.status = .working }
        }

        return metrics
    }

    private func findSessionFile(sessionId: String) -> String? {
        let fm = FileManager.default
        // 搜索 sessions 和 archived_sessions
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dirs = [sessionsDir, "\(home)/.codex/archived_sessions"]

        for baseDir in dirs {
            if let path = findRecursive(in: baseDir, sessionId: sessionId, fm: fm) {
                return path
            }
        }
        return nil
    }

    private func findRecursive(in dir: String, sessionId: String, fm: FileManager) -> String? {
        guard let items = try? fm.contentsOfDirectory(atPath: dir) else { return nil }
        for item in items {
            let path = "\(dir)/\(item)"
            if item.hasSuffix(".jsonl") && item.contains(sessionId) {
                return path
            }
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                if let found = findRecursive(in: path, sessionId: sessionId, fm: fm) {
                    return found
                }
            }
        }
        return nil
    }
}
