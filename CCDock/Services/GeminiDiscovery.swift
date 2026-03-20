import Foundation

/// 发现活跃的 Gemini CLI 会话
/// Gemini 会话数据: ~/.gemini/tmp/{hash}/logs.json
/// 活跃判断: logs.json 在最近 60 秒内被修改过
class GeminiDiscovery {
    private let store: SessionStore
    private let tmpDir: String
    private var timer: Timer?
    private var cwdCache: [String: String] = [:]

    private let activeThreshold: TimeInterval = 60

    init(store: SessionStore) {
        self.store = store
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.tmpDir = "\(home)/.gemini/tmp"
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
        guard let dirs = try? fm.contentsOfDirectory(atPath: tmpDir) else { return }

        var discoveredIds = Set<String>()

        for dir in dirs {
            let logsPath = "\(tmpDir)/\(dir)/logs.json"

            // 只关注最近修改过的（活跃会话）
            guard let attrs = try? fm.attributesOfItem(atPath: logsPath),
                  let modDate = attrs[.modificationDate] as? Date,
                  Date().timeIntervalSince(modDate) < activeThreshold else { continue }

            guard let meta = parseGeminiSession(dir: dir, logsPath: logsPath, modDate: attrs[.creationDate] as? Date) else { continue }
            discoveredIds.insert(meta.id)
            store.upsert(meta)
        }

        // 清理不再活跃的 Gemini 会话
        let staleIds = store.activeSessionIds(for: .gemini).subtracting(discoveredIds)
        for id in staleIds {
            store.remove(sessionId: id)
        }
    }

    private func parseGeminiSession(dir: String, logsPath: String, modDate: Date?) -> Session? {
        guard let data = FileManager.default.contents(atPath: logsPath),
              let logs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = logs.first else { return nil }

        let sessionId = first["sessionId"] as? String ?? dir

        // 从日志中提取 cwd（Gemini 没有直接记录，用当前工作目录或空字符串）
        // 尝试从消息内容推断，否则使用 ~ 作为默认
        let cwd = cwdCache[dir] ?? extractCwd(from: logs) ?? "~"
        cwdCache[dir] = cwd

        // 提取开始时间
        let startedAt: Date
        if let ts = first["timestamp"] as? String {
            startedAt = parseISO8601(ts) ?? modDate ?? Date()
        } else {
            startedAt = modDate ?? Date()
        }

        // 提取最后一条用户消息作为 lastPrompt
        let lastUserMsg = logs.last(where: { $0["type"] as? String == "user" })
        let lastPrompt = lastUserMsg?["message"] as? String

        var session = Session(id: sessionId, pid: 0, cwd: cwd, startedAt: startedAt, agentType: .gemini)
        session.lastPrompt = lastPrompt
        session.model = "gemini"
        session.turnCount = logs.filter { $0["type"] as? String == "user" }.count
        return session
    }

    /// 尝试从 Gemini 日志中提取工作目录
    private func extractCwd(from logs: [[String: Any]]) -> String? {
        // Gemini CLI 不直接记录 cwd，但消息中可能包含路径信息
        // 作为简单方案，检测是否有 gemini 进程正在运行，获取其 cwd
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", "gemini"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            let pids = output.split(separator: "\n").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            // 取第一个 gemini 进程的 cwd
            for pid in pids {
                let lsof = Process()
                lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
                lsof.arguments = ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]
                let lsofPipe = Pipe()
                lsof.standardOutput = lsofPipe
                lsof.standardError = FileHandle.nullDevice
                try lsof.run()
                lsof.waitUntilExit()
                let lsofData = lsofPipe.fileHandleForReading.readDataToEndOfFile()
                if let lsofStr = String(data: lsofData, encoding: .utf8) {
                    for line in lsofStr.split(separator: "\n") where line.hasPrefix("n/") {
                        return String(line.dropFirst(1))
                    }
                }
            }
        } catch {}
        return nil
    }

    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
