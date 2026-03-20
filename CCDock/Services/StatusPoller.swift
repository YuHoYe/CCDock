import Foundation
import UserNotifications

/// 通过 Claude Code 的 jsonl 日志推断会话状态
class StatusPoller {
    private let store: SessionStore
    private let projectsDir: String
    private var timer: Timer?
    private var tokenTimer: Timer?

    /// jsonl 超过这个时间没更新就认为是 idle
    private let staleThreshold: TimeInterval = 30

    /// 中间状态类型，解析 jsonl 时跳过
    private static let skipTypes: Set<String> = ["progress", "queue-operation", "system", "file-history-snapshot"]

    // 跟踪上次状态，用于触发通知
    private var previousStatuses: [String: SessionStatus] = [:]

    // metrics 缓存：文件大小未变则跳过重新解析
    private var lastMetricsFileSize: [String: UInt64] = [:]

    // jsonl 路径缓存：避免每次 poll 都做目录遍历
    private var resolvedPaths: [String: (path: String, resolvedAt: Date)] = [:]

    init(store: SessionStore) {
        self.store = store
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.projectsDir = "\(home)/.claude/projects"
        requestNotificationPermission()
    }

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        // token 统计频率低一些（10s），因为解析 jsonl 开销较大
        tokenTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.pollTokens()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        tokenTimer?.invalidate()
        tokenTimer = nil
    }

    // MARK: - 状态轮询

    private func poll() {
        for session in store.sessions where session.agentType == .claude {
            let logPath = jsonlPath(sessionId: session.id, cwd: session.cwd)

            guard let attrs = try? FileManager.default.attributesOfItem(atPath: logPath),
                  let modDate = attrs[.modificationDate] as? Date else {
                store.updateStatus(sessionId: session.id, status: .unknown)
                continue
            }

            let timeSinceUpdate = Date().timeIntervalSince(modDate)
            let tail = readTail(path: logPath, bytes: 32_768)

            let status = StatusPoller.inferStatus(from: tail, timeSinceUpdate: timeSinceUpdate, staleThreshold: staleThreshold)
            let prompt = StatusPoller.parseLastPrompt(from: tail)

            let prevStatus = previousStatuses[session.id]
            if let prev = prevStatus, prev != status {
                sendStatusChangeNotification(projectName: session.projectName, from: prev, to: status)
            }
            previousStatuses[session.id] = status

            store.updateStatus(sessionId: session.id, status: status)
            if let prompt = prompt {
                store.updatePrompt(sessionId: session.id, prompt: prompt)
            }
        }
    }

    private func pollTokens() {
        for session in store.sessions where session.agentType == .claude {
            let logPath = jsonlPath(sessionId: session.id, cwd: session.cwd)

            // 文件大小未变则跳过，避免重复全量解析
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: logPath),
                  let fileSize = attrs[.size] as? UInt64 else { continue }
            if lastMetricsFileSize[session.id] == fileSize { continue }
            lastMetricsFileSize[session.id] = fileSize

            guard let data = FileManager.default.contents(atPath: logPath),
                  let content = String(data: data, encoding: .utf8) else { continue }
            let metrics = StatusPoller.parseMetrics(from: content)
            store.updateMetrics(
                sessionId: session.id,
                turnCount: metrics.turnCount,
                totalTokens: metrics.tokens,
                model: metrics.model,
                gitBranch: metrics.gitBranch,
                version: metrics.version
            )
        }
    }

    // MARK: - Helpers

    /// 只读文件末尾，避免全量加载大型 jsonl
    private func readTail(path: String, bytes: Int) -> String {
        guard let handle = FileHandle(forReadingAtPath: path) else { return "" }
        defer { handle.closeFile() }
        let size = handle.seekToEndOfFile()
        let offset = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        handle.seek(toFileOffset: offset)
        var data = handle.readDataToEndOfFile()
        // 截断可能切断 UTF-8 多字节序列，跳过开头不完整的字节
        if offset > 0 {
            while !data.isEmpty, String(data: data.prefix(1), encoding: .utf8) == nil {
                data = data.dropFirst()
            }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func jsonlPath(sessionId: String, cwd: String) -> String {
        let cacheKey = "\(sessionId):\(cwd)"

        // 缓存有效期 10 秒，避免每 2 秒都做目录遍历
        if let cached = resolvedPaths[cacheKey],
           Date().timeIntervalSince(cached.resolvedAt) < 10 {
            return cached.path
        }

        let encodedCwd = cwd.replacingOccurrences(of: "/", with: "-")
        let exactPath = "\(projectsDir)/\(encodedCwd)/\(sessionId).jsonl"
        let projectDir = "\(projectsDir)/\(encodedCwd)"

        // 精确匹配的 jsonl 最近有更新，直接用
        if let attrs = try? FileManager.default.attributesOfItem(atPath: exactPath),
           let modDate = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modDate) < staleThreshold {
            resolvedPaths[cacheKey] = (exactPath, Date())
            return exactPath
        }

        // Claude Code 可能在同一 PID 下切换了 sessionId，找同目录最新的 jsonl
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: projectDir) else {
            resolvedPaths[cacheKey] = (exactPath, Date())
            return exactPath
        }
        let newest = files
            .filter { $0.hasSuffix(".jsonl") }
            .compactMap { name -> (String, Date)? in
                let path = "\(projectDir)/\(name)"
                guard let a = try? FileManager.default.attributesOfItem(atPath: path),
                      let mod = a[.modificationDate] as? Date else { return nil }
                return (path, mod)
            }
            .max(by: { $0.1 < $1.1 })

        let result: String
        if let newest = newest,
           Date().timeIntervalSince(newest.1) < staleThreshold {
            result = newest.0
        } else {
            result = exactPath
        }
        resolvedPaths[cacheKey] = (result, Date())
        return result
    }

    // MARK: - 纯函数（可测试）

    enum LastEntryType: Equatable {
        case userMessage
        case assistantStreaming
        case assistantDone
        case waitingInput
        case unknown
    }

    /// 从 jsonl 内容推断最后一个有意义的条目类型
    static func parseLastEntry(from content: String) -> LastEntryType {
        let lines = content.split(separator: "\n")
        for line in lines.reversed() {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = obj["type"] as? String else {
                continue
            }

            if type == "user" { return .userMessage }

            if type == "assistant" {
                if let message = obj["message"] as? [String: Any],
                   let stopReason = message["stop_reason"] as? String,
                   stopReason == "end_turn" {
                    return .assistantDone
                }
                return .assistantStreaming
            }

            if type == "last-prompt" { return .assistantDone }

            if Self.skipTypes.contains(type) { continue }
        }
        return .unknown
    }

    /// 从 jsonl 内容 + 文件新鲜度推断会话状态
    static func inferStatus(from content: String, timeSinceUpdate: TimeInterval, staleThreshold: TimeInterval = 30) -> SessionStatus {
        let lastEntry = parseLastEntry(from: content)
        switch lastEntry {
        case .userMessage:       return .working
        case .assistantStreaming: return .working
        case .assistantDone:     return .idle
        case .waitingInput:      return .waitingInput
        case .unknown:
            return timeSinceUpdate < staleThreshold ? .working : .unknown
        }
    }

    /// 从 jsonl 内容提取最近的用户 prompt
    static func parseLastPrompt(from content: String) -> String? {
        let lines = content.split(separator: "\n")
        for line in lines.reversed() {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = obj["type"] as? String else {
                continue
            }

            if type == "last-prompt", let prompt = obj["lastPrompt"] as? String {
                return prompt
            }
            if type == "user",
               let message = obj["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            }
        }
        return nil
    }

    struct SessionMetrics {
        var tokens: Int = 0
        var turnCount: Int = 0
        var model: String?
        var gitBranch: String?
        var version: String?
    }

    /// 从 jsonl 内容解析 token、轮数、模型等信息
    static func parseMetrics(from content: String) -> SessionMetrics {
        var metrics = SessionMetrics()
        for line in content.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            let type = obj["type"] as? String

            if type == "user" { metrics.turnCount += 1 }

            if metrics.gitBranch == nil, let branch = obj["gitBranch"] as? String, !branch.isEmpty {
                metrics.gitBranch = branch
            }
            if metrics.version == nil, let ver = obj["version"] as? String {
                metrics.version = ver
            }

            guard type == "assistant",
                  let message = obj["message"] as? [String: Any] else { continue }

            if metrics.model == nil, let model = message["model"] as? String {
                metrics.model = model
            }
            if let usage = message["usage"] as? [String: Any] {
                metrics.tokens += usage["input_tokens"] as? Int ?? 0
                metrics.tokens += usage["output_tokens"] as? Int ?? 0
                metrics.tokens += usage["cache_read_input_tokens"] as? Int ?? 0
                metrics.tokens += usage["cache_creation_input_tokens"] as? Int ?? 0
            }
        }
        return metrics
    }

    // MARK: - macOS 原生通知

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendStatusChangeNotification(projectName: String, from: SessionStatus, to: SessionStatus) {
        let shouldNotify: Bool
        switch to {
        case .waitingInput: shouldNotify = true
        case .idle where from == .working: shouldNotify = true
        default: shouldNotify = false
        }
        guard shouldNotify else { return }

        let content = UNMutableNotificationContent()
        content.title = projectName
        content.body = to == .waitingInput ? "等待你的输入" : "任务完成"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "ccdock-\(projectName)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
