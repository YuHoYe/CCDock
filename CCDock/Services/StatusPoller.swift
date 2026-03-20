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

        // 检查文件修改时间
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logPath),
              let modDate = attrs[.modificationDate] as? Date else {
            return .unknown
        }

        let timeSinceUpdate = Date().timeIntervalSince(modDate)

        // 读最后几行判断最终状态
        let lastEntry = readLastEntry(path: logPath)

        switch lastEntry {
        case .userMessage:
            // 用户刚提交 prompt，一定在工作中
            return .working

        case .assistantStreaming:
            // assistant 消息还没 end_turn，正在流式输出
            return .working

        case .assistantDone:
            if timeSinceUpdate < staleThreshold {
                // 刚完成，可能马上会有新的 user 消息
                return .idle
            }
            return .idle

        case .waitingInput:
            return .waitingInput

        case .unknown:
            // 文件最近有更新 → 工作中；否则 → 未知
            return timeSinceUpdate < staleThreshold ? .working : .unknown
        }
    }

    private enum LastEntryType {
        case userMessage
        case assistantStreaming  // assistant 消息但没有 end_turn
        case assistantDone      // assistant 消息且 stop_reason == end_turn
        case waitingInput
        case unknown
    }

    /// 从 jsonl 末尾读取最后一个有意义的条目
    private func readLastEntry(path: String) -> LastEntryType {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            return .unknown
        }

        // 从末尾往前扫描，找最后的 user/assistant/last-prompt 行
        let lines = content.split(separator: "\n")
        for line in lines.reversed() {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = obj["type"] as? String else {
                continue
            }

            if type == "user" {
                return .userMessage
            }

            if type == "assistant" {
                if let message = obj["message"] as? [String: Any],
                   let stopReason = message["stop_reason"] as? String,
                   stopReason == "end_turn" {
                    return .assistantDone
                }
                return .assistantStreaming
            }

            // Claude Code 在 assistant 回复后会写 last-prompt
            if type == "last-prompt" {
                return .assistantDone
            }

            // tool_result 等中间状态 → 继续往前看
            if type == "progress" || type == "queue-operation" {
                continue
            }
        }

        return .unknown
    }

    // MARK: - Prompt 读取

    private func readLastPrompt(sessionId: String, cwd: String) -> String? {
        let logPath = jsonlPath(sessionId: sessionId, cwd: cwd)
        guard let data = FileManager.default.contents(atPath: logPath),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        // 找 last-prompt 或最后一条 user 消息
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

    // MARK: - Token 统计

    private func pollTokens() {
        let claudeSessions = store.sessions.filter { $0.agentType == .claude }
        for session in claudeSessions {
            let metrics = parseSessionLog(sessionId: session.id, cwd: session.cwd)
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

    private struct SessionMetrics {
        var tokens: Int = 0
        var turnCount: Int = 0
        var model: String?
        var gitBranch: String?
        var version: String?
    }

    private func parseSessionLog(sessionId: String, cwd: String) -> SessionMetrics {
        let logPath = jsonlPath(sessionId: sessionId, cwd: cwd)

        guard let data = FileManager.default.contents(atPath: logPath),
              let content = String(data: data, encoding: .utf8) else {
            return SessionMetrics()
        }

        var metrics = SessionMetrics()
        for line in content.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            let type = obj["type"] as? String

            // 统计 user 消息数作为轮数
            if type == "user" {
                metrics.turnCount += 1
            }

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
