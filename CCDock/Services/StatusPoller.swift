import Foundation
import SQLite3
import UserNotifications

/// 轮询 ccnotify.db 获取会话状态，解析 jsonl 获取 token 用量
class StatusPoller {
    private let store: SessionStore
    private let dbPath: String
    private let projectsDir: String
    private var timer: Timer?
    private var tokenTimer: Timer?

    private let idleThreshold: TimeInterval = 30

    // 跟踪上次状态，用于触发通知
    private var previousStatuses: [String: SessionStatus] = [:]

    init(store: SessionStore) {
        self.store = store
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.dbPath = "\(home)/.claude/plugins/cache/netease-claude-code-plugin-market/notifier/1.0.0/scripts/ccnotify/ccnotify.db"
        self.projectsDir = "\(home)/.claude/projects"
        requestNotificationPermission()
    }

    func start() {
        poll()
        pollTokens()
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
        let sessionIds = store.activeSessionIds()
        guard !sessionIds.isEmpty else { return }

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }

        for sessionId in sessionIds {
            pollSessionStatus(db: db, sessionId: sessionId)
            pollSessionTurnCount(db: db, sessionId: sessionId)
        }
    }

    private func pollSessionStatus(db: OpaquePointer?, sessionId: String) {
        let sql = """
            SELECT prompt, stoped_at, lastWaitUserAt
            FROM prompt WHERE session_id = ? ORDER BY created_at DESC LIMIT 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (sessionId as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            store.updateStatus(sessionId: sessionId, status: .unknown)
            return
        }

        let prompt = sqlite3_column_text(stmt, 0).map { String(cString: $0) }
        let stoppedAt = sqlite3_column_text(stmt, 1)
        let lastWaitUserAt = sqlite3_column_text(stmt, 2)

        let status: SessionStatus
        if let stopAt = stoppedAt {
            let stopStr = String(cString: stopAt)
            if let waitAt = lastWaitUserAt, String(cString: waitAt) > stopStr {
                status = .waitingInput
            } else {
                status = .idle
            }
        } else {
            let session = store.sessions.first { $0.id == sessionId }
            if let cwd = session?.cwd, isSessionLogStale(sessionId: sessionId, cwd: cwd) {
                status = .idle
            } else {
                status = .working
            }
        }

        // 状态变化通知
        let prevStatus = previousStatuses[sessionId]
        if let prev = prevStatus, prev != status {
            let session = store.sessions.first { $0.id == sessionId }
            let projectName = session?.projectName ?? sessionId.prefix(8).description
            sendStatusChangeNotification(projectName: projectName, from: prev, to: status)
        }
        previousStatuses[sessionId] = status

        store.updateStatus(sessionId: sessionId, status: status)
        if let prompt = prompt {
            store.updatePrompt(sessionId: sessionId, prompt: prompt)
        }
    }

    private func pollSessionTurnCount(db: OpaquePointer?, sessionId: String) {
        let sql = "SELECT COUNT(*) FROM prompt WHERE session_id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (sessionId as NSString).utf8String, -1, nil)
        if sqlite3_step(stmt) == SQLITE_ROW {
            let count = Int(sqlite3_column_int(stmt, 0))
            // 仅更新 turnCount，token 由 pollTokens 更新
            if let index = store.sessions.firstIndex(where: { $0.id == sessionId }) {
                store.sessions[index].turnCount = count
            }
        }
    }

    // MARK: - Token 统计

    private func pollTokens() {
        for session in store.sessions {
            let metrics = parseSessionLog(sessionId: session.id, cwd: session.cwd)
            store.updateMetrics(
                sessionId: session.id,
                turnCount: session.turnCount,
                totalTokens: metrics.tokens,
                model: metrics.model,
                gitBranch: metrics.gitBranch,
                version: metrics.version
            )
        }
    }

    private struct SessionMetrics {
        var tokens: Int = 0
        var model: String?
        var gitBranch: String?
        var version: String?
    }

    private func parseSessionLog(sessionId: String, cwd: String) -> SessionMetrics {
        let encodedCwd = cwd.replacingOccurrences(of: "/", with: "-")
        let logPath = "\(projectsDir)/\(encodedCwd)/\(sessionId).jsonl"

        guard let handle = FileHandle(forReadingAtPath: logPath) else { return SessionMetrics() }
        defer { handle.closeFile() }

        let data = handle.readDataToEndOfFile()
        guard let content = String(data: data, encoding: .utf8) else { return SessionMetrics() }

        var metrics = SessionMetrics()
        for line in content.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            // 从任意消息提取 gitBranch 和 version
            if metrics.gitBranch == nil, let branch = obj["gitBranch"] as? String, !branch.isEmpty {
                metrics.gitBranch = branch
            }
            if metrics.version == nil, let ver = obj["version"] as? String {
                metrics.version = ver
            }

            // 从 assistant 消息提取 token 和 model
            guard obj["type"] as? String == "assistant",
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

    // MARK: - 日志文件检查

    private func isSessionLogStale(sessionId: String, cwd: String) -> Bool {
        let encodedCwd = cwd.replacingOccurrences(of: "/", with: "-")
        let logPath = "\(projectsDir)/\(encodedCwd)/\(sessionId).jsonl"
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logPath),
              let modDate = attrs[.modificationDate] as? Date else {
            return true
        }
        return Date().timeIntervalSince(modDate) > idleThreshold
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
