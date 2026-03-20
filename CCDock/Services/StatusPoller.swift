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
        let claudeSessions = store.sessions.filter { $0.agentType == .claude }
        for session in claudeSessions {
            let status = inferStatus(sessionId: session.id, cwd: session.cwd)
            let prompt = readLastPrompt(sessionId: session.id, cwd: session.cwd)

            // 状态变化通知
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

    // MARK: - 状态推断（纯 jsonl）

    private func inferStatus(sessionId: String, cwd: String) -> SessionStatus {
        let logPath = jsonlPath(sessionId: sessionId, cwd: cwd)

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logPath),
              let modDate = attrs[.modificationDate] as? Date else {
            return .unknown
        }

        let timeSinceUpdate = Date().timeIntervalSince(modDate)

        guard let data = FileManager.default.contents(atPath: logPath),
              let content = String(data: data, encoding: .utf8) else {
            return .unknown
        }

        return StatusPoller.inferStatus(from: content, timeSinceUpdate: timeSinceUpdate, staleThreshold: staleThreshold)
    }

    private func readLastPrompt(sessionId: String, cwd: String) -> String? {
        let logPath = jsonlPath(sessionId: sessionId, cwd: cwd)
        guard let data = FileManager.default.contents(atPath: logPath),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }
        return StatusPoller.parseLastPrompt(from: content)
    }

    private func pollTokens() {
        let claudeSessions = store.sessions.filter { $0.agentType == .claude }
        for session in claudeSessions {
            let logPath = jsonlPath(sessionId: session.id, cwd: session.cwd)
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

    // MARK: - Helpers

    private func jsonlPath(sessionId: String, cwd: String) -> String {
        let encodedCwd = cwd.replacingOccurrences(of: "/", with: "-")
        return "\(projectsDir)/\(encodedCwd)/\(sessionId).jsonl"
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
