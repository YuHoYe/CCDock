import Foundation

/// 发现活跃的 Codex 会话
/// Codex 会话文件: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
/// 活跃判断: jsonl 文件在最近 60 秒内被修改过
class CodexDiscovery {
    private let store: SessionStore
    private let sessionsDir: String
    private var timer: Timer?

    private let activeThreshold: TimeInterval = 60

    init(store: SessionStore) {
        self.store = store
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.sessionsDir = "\(home)/.codex/sessions"
    }

    func start() {
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.scan()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func scan() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionsDir) else { return }

        var discoveredIds = Set<String>()

        // 只扫描最近 2 天的目录以减少开销
        let calendar = Calendar.current
        let today = Date()
        for dayOffset in 0...1 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let year = calendar.component(.year, from: date)
            let month = String(format: "%02d", calendar.component(.month, from: date))
            let day = String(format: "%02d", calendar.component(.day, from: date))
            let dayDir = "\(sessionsDir)/\(year)/\(month)/\(day)"

            guard let files = try? fm.contentsOfDirectory(atPath: dayDir) else { continue }
            for file in files where file.hasSuffix(".jsonl") {
                let path = "\(dayDir)/\(file)"

                // 只关注最近修改过的文件（活跃会话）
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let modDate = attrs[.modificationDate] as? Date,
                      Date().timeIntervalSince(modDate) < activeThreshold else { continue }

                guard let meta = parseSessionMeta(path: path) else { continue }
                discoveredIds.insert(meta.id)
                store.upsert(meta)
            }
        }

        // 清理不再活跃的 Codex 会话
        let staleIds = store.activeSessionIds(for: .codex).subtracting(discoveredIds)
        for id in staleIds {
            store.remove(sessionId: id)
        }
    }

    /// 从 jsonl 第一行解析 session_meta
    private func parseSessionMeta(path: String) -> Session? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { handle.closeFile() }

        // 只读前 4KB 拿 session_meta
        let chunk = handle.readData(ofLength: 4096)
        guard let content = String(data: chunk, encoding: .utf8) else { return nil }

        for line in content.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  obj["type"] as? String == "session_meta",
                  let payload = obj["payload"] as? [String: Any],
                  let sessionId = payload["id"] as? String,
                  let cwd = payload["cwd"] as? String,
                  let timestamp = payload["timestamp"] as? String else { continue }

            let startedAt = parseISO8601(timestamp) ?? Date()
            // Codex Desktop 没有简单的 PID，用 0 占位
            var session = Session(id: sessionId, pid: 0, cwd: cwd, startedAt: startedAt, agentType: .codex)
            session.model = payload["model_provider"] as? String
            session.version = payload["cli_version"] as? String
            return session
        }
        return nil
    }

    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
