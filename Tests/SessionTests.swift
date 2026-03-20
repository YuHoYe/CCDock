import XCTest
@testable import CCDock

// MARK: - Session Model

final class SessionModelTests: XCTestCase {

    func testProjectName() {
        let s = Session(id: "1", pid: 1, cwd: "/Users/test/Developer/MyProject", startedAt: Date(), agentType: .claude)
        XCTAssertEqual(s.projectName, "MyProject")
    }

    func testTokenText() {
        var s = Session(id: "1", pid: 1, cwd: "/tmp", startedAt: Date(), agentType: .claude)

        s.totalTokens = 0
        XCTAssertEqual(s.tokenText, "")

        s.totalTokens = 500
        XCTAssertEqual(s.tokenText, "500")

        s.totalTokens = 1_500
        XCTAssertEqual(s.tokenText, "2K")

        s.totalTokens = 1_200_000
        XCTAssertEqual(s.tokenText, "1.2M")
    }

    func testModelShort() {
        var s = Session(id: "1", pid: 1, cwd: "/tmp", startedAt: Date(), agentType: .claude)

        s.model = "claude-opus-4-6"
        XCTAssertEqual(s.modelShort, "opus-4-6")

        s.model = "models/gemini-2.5-pro"
        XCTAssertEqual(s.modelShort, "gemini-2.5-pro")

        s.model = "gpt-5"
        XCTAssertEqual(s.modelShort, "gpt-5")

        s.model = nil
        XCTAssertEqual(s.modelShort, "")
    }

    func testSessionInfoDecoding() throws {
        let json = """
        {"pid":17070,"sessionId":"e4ebbdbc-32f9-47d2-a609-adf893fdb05b","cwd":"/Users/test/project","startedAt":1773921724967}
        """
        let info = try JSONDecoder().decode(SessionInfo.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(info.pid, 17070)
        XCTAssertEqual(info.sessionId, "e4ebbdbc-32f9-47d2-a609-adf893fdb05b")
        XCTAssertEqual(info.cwd, "/Users/test/project")
    }

    func testSessionFromInfo() throws {
        let json = """
        {"pid":100,"sessionId":"abc","cwd":"/tmp","startedAt":1773921724967}
        """
        let info = try JSONDecoder().decode(SessionInfo.self, from: json.data(using: .utf8)!)
        let session = Session(from: info)
        XCTAssertEqual(session.id, "abc")
        XCTAssertEqual(session.status, .unknown)
        XCTAssertEqual(session.startedAt.timeIntervalSince1970, 1773921724.967, accuracy: 0.001)
    }
}

// MARK: - SessionStore

final class SessionStoreTests: XCTestCase {

    func testUpsertNewAndUpdate() {
        let store = SessionStore()
        var s = Session(id: "1", pid: 1, cwd: "/tmp/a", startedAt: Date(), agentType: .claude)
        s.tty = "ttys001"
        store.upsert(s)
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions[0].tty, "ttys001")

        // upsert 同 id，nil tty 不覆盖
        var s2 = Session(id: "1", pid: 1, cwd: "/tmp/a", startedAt: Date(), agentType: .claude)
        s2.tty = nil
        store.upsert(s2)
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions[0].tty, "ttys001")
    }

    func testUpdateStatusTracksChangedAt() {
        let store = SessionStore()
        store.upsert(Session(id: "1", pid: 1, cwd: "/tmp", startedAt: Date(), agentType: .claude))
        XCTAssertNil(store.sessions[0].statusChangedAt)

        store.updateStatus(sessionId: "1", status: .working)
        XCTAssertEqual(store.sessions[0].status, .working)
        XCTAssertNotNil(store.sessions[0].statusChangedAt)

        let firstChange = store.sessions[0].statusChangedAt

        // 同样状态不更新时间
        store.updateStatus(sessionId: "1", status: .working)
        XCTAssertEqual(store.sessions[0].statusChangedAt, firstChange)

        // 不同状态更新时间
        store.updateStatus(sessionId: "1", status: .idle)
        XCTAssertNotEqual(store.sessions[0].statusChangedAt, firstChange)
    }

    func testRemove() {
        let store = SessionStore()
        store.upsert(Session(id: "1", pid: 1, cwd: "/tmp", startedAt: Date(), agentType: .claude))
        store.upsert(Session(id: "2", pid: 2, cwd: "/tmp", startedAt: Date(), agentType: .codex))
        XCTAssertEqual(store.sessions.count, 2)

        store.remove(sessionId: "1")
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions[0].id, "2")
    }

    func testActiveSessionIdsByType() {
        let store = SessionStore()
        store.upsert(Session(id: "c1", pid: 1, cwd: "/tmp", startedAt: Date(), agentType: .claude))
        store.upsert(Session(id: "x1", pid: 2, cwd: "/tmp", startedAt: Date(), agentType: .codex))
        store.upsert(Session(id: "c2", pid: 3, cwd: "/tmp", startedAt: Date(), agentType: .claude))

        XCTAssertEqual(store.activeSessionIds(for: .claude), Set(["c1", "c2"]))
        XCTAssertEqual(store.activeSessionIds(for: .codex), Set(["x1"]))
        XCTAssertTrue(store.activeSessionIds(for: .gemini).isEmpty)
    }
}

// MARK: - StatusPoller JSONL 解析

final class StatusPollerParsingTests: XCTestCase {

    // MARK: - parseLastEntry

    func testLastEntryUser() {
        let content = #"{"type":"user","message":{"role":"user","content":"hello"}}"#
        let entry = StatusPoller.parseLastEntry(from: content)
        XCTAssert(entry == .userMessage)
    }

    func testLastEntryAssistantDone() {
        let content = """
        {"type":"user","message":{"role":"user","content":"hello"}}
        {"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn"}}
        """
        XCTAssert(StatusPoller.parseLastEntry(from: content) == .assistantDone)
    }

    func testLastEntryAssistantStreaming() {
        let content = """
        {"type":"user","message":{"role":"user","content":"hello"}}
        {"type":"assistant","message":{"role":"assistant","stop_reason":null}}
        """
        XCTAssert(StatusPoller.parseLastEntry(from: content) == .assistantStreaming)
    }

    func testLastEntryLastPrompt() {
        let content = """
        {"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn"}}
        {"type":"last-prompt","lastPrompt":"hello"}
        """
        XCTAssert(StatusPoller.parseLastEntry(from: content) == .assistantDone)
    }

    func testLastEntrySkipsProgress() {
        let content = """
        {"type":"user","message":{"role":"user","content":"fix bug"}}
        {"type":"progress","data":{"type":"tool_use"}}
        {"type":"progress","data":{"type":"tool_result"}}
        """
        XCTAssert(StatusPoller.parseLastEntry(from: content) == .userMessage)
    }

    func testLastEntryEmpty() {
        XCTAssert(StatusPoller.parseLastEntry(from: "") == .unknown)
    }

    // MARK: - inferStatus

    func testInferStatusWorking() {
        let content = #"{"type":"user","message":{"role":"user","content":"hello"}}"#
        XCTAssertEqual(StatusPoller.inferStatus(from: content, timeSinceUpdate: 1), .working)
    }

    func testInferStatusIdle() {
        let content = #"{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn"}}"#
        XCTAssertEqual(StatusPoller.inferStatus(from: content, timeSinceUpdate: 60), .idle)
    }

    func testInferStatusStreaming() {
        let content = #"{"type":"assistant","message":{"role":"assistant","stop_reason":null}}"#
        XCTAssertEqual(StatusPoller.inferStatus(from: content, timeSinceUpdate: 5), .working)
    }

    func testInferStatusUnknownFresh() {
        let content = #"{"type":"queue-operation","operation":"enqueue"}"#
        XCTAssertEqual(StatusPoller.inferStatus(from: content, timeSinceUpdate: 5), .working)
    }

    func testInferStatusUnknownStale() {
        let content = #"{"type":"queue-operation","operation":"enqueue"}"#
        XCTAssertEqual(StatusPoller.inferStatus(from: content, timeSinceUpdate: 60), .unknown)
    }

    // MARK: - parseLastPrompt

    func testParseLastPromptFromLastPrompt() {
        let content = """
        {"type":"user","message":{"role":"user","content":"first prompt"}}
        {"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn"}}
        {"type":"last-prompt","lastPrompt":"first prompt"}
        """
        XCTAssertEqual(StatusPoller.parseLastPrompt(from: content), "first prompt")
    }

    func testParseLastPromptFromUser() {
        let content = """
        {"type":"user","message":{"role":"user","content":"fix the bug"}}
        {"type":"assistant","message":{"role":"assistant","stop_reason":null}}
        """
        XCTAssertEqual(StatusPoller.parseLastPrompt(from: content), "fix the bug")
    }

    func testParseLastPromptEmpty() {
        XCTAssertNil(StatusPoller.parseLastPrompt(from: ""))
    }

    // MARK: - parseMetrics

    func testParseMetrics() {
        let content = """
        {"type":"user","message":{"role":"user","content":"hello"},"version":"2.1.80","gitBranch":"main"}
        {"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-6","stop_reason":"end_turn","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":200,"cache_creation_input_tokens":0}}}
        {"type":"user","message":{"role":"user","content":"next"}}
        {"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-6","stop_reason":"end_turn","usage":{"input_tokens":150,"output_tokens":80,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
        """
        let m = StatusPoller.parseMetrics(from: content)
        XCTAssertEqual(m.turnCount, 2)
        XCTAssertEqual(m.tokens, 580)
        XCTAssertEqual(m.model, "claude-opus-4-6")
        XCTAssertEqual(m.gitBranch, "main")
        XCTAssertEqual(m.version, "2.1.80")
    }

    func testParseMetricsNoAssistant() {
        let content = #"{"type":"user","message":{"role":"user","content":"hello"}}"#
        let m = StatusPoller.parseMetrics(from: content)
        XCTAssertEqual(m.turnCount, 1)
        XCTAssertEqual(m.tokens, 0)
        XCTAssertNil(m.model)
    }

    func testParseMetricsEmpty() {
        let m = StatusPoller.parseMetrics(from: "")
        XCTAssertEqual(m.turnCount, 0)
        XCTAssertEqual(m.tokens, 0)
    }

    // MARK: - encodeCwd

    func testEncodeCwdNormalPath() {
        XCTAssertEqual(
            StatusPoller.encodeCwd("/Users/test/Developer/MyProject"),
            "-Users-test-Developer-MyProject"
        )
    }

    func testEncodeCwdWorktreePath() {
        // worktree 路径包含 .claude，. 需要被删除
        XCTAssertEqual(
            StatusPoller.encodeCwd("/Users/yuho/Developer/CCDock/.claude/worktrees/sprightly-hatching-kettle"),
            "-Users-yuho-Developer-CCDock--claude-worktrees-sprightly-hatching-kettle"
        )
    }

    func testEncodeCwdDotInPath() {
        // 路径中有多个 .（如 .config、.local），. 替换为 -
        XCTAssertEqual(
            StatusPoller.encodeCwd("/Users/yuho/.config/.local/project"),
            "-Users-yuho--config--local-project"
        )
    }

    func testEncodeCwdHiddenPluginsCachePath() {
        XCTAssertEqual(
            StatusPoller.encodeCwd("/Users/yuho/.claude/plugins-cache/some-plugin"),
            "-Users-yuho--claude-plugins-cache-some-plugin"
        )
    }

    // MARK: - parseLastEntry 跳过本地命令

    func testLastEntrySkipsLocalCommand() {
        let content = """
        {"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn"}}
        {"type":"user","message":{"content":"<command-name>/compact</command-name>"}}
        """
        XCTAssert(StatusPoller.parseLastEntry(from: content) == .assistantDone)
    }

    func testLastEntrySkipsLocalCommandStdout() {
        let content = """
        {"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn"}}
        {"type":"user","message":{"content":"<local-command-stdout>Compacted</local-command-stdout>"}}
        """
        XCTAssert(StatusPoller.parseLastEntry(from: content) == .assistantDone)
    }

    func testLastEntrySkipsLocalCommandCaveat() {
        let content = """
        {"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn"}}
        {"type":"user","message":{"content":"<local-command-caveat>Caveat: messages below were generated locally</local-command-caveat>"}}
        """
        XCTAssert(StatusPoller.parseLastEntry(from: content) == .assistantDone)
    }

    func testLastEntrySkipsContextContinuation() {
        let content = """
        {"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn"}}
        {"type":"user","message":{"content":"This session is being continued from a previous conversation that ran out of context."}}
        """
        XCTAssert(StatusPoller.parseLastEntry(from: content) == .assistantDone)
    }

    func testLastEntrySkipsMultipleLocalCommandsThenFindsAssistant() {
        // 模拟 /compact 后的完整 jsonl 尾部
        let content = """
        {"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn"}}
        {"type":"last-prompt","lastPrompt":"fix bug"}
        {"type":"file-history-snapshot","data":{}}
        {"type":"system","message":"context reset"}
        {"type":"user","message":{"content":"This session is being continued from a previous conversation"}}
        {"type":"user","message":{"content":"<local-command-caveat>Caveat</local-command-caveat>"}}
        {"type":"user","message":{"content":"<command-name>/compact</command-name>"}}
        {"type":"user","message":{"content":"<local-command-stdout>Compacted</local-command-stdout>"}}
        """
        XCTAssert(StatusPoller.parseLastEntry(from: content) == .assistantDone)
    }

    func testLastEntryRealUserMessageAfterLocalCommands() {
        // 本地命令后又有真实用户消息
        let content = """
        {"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn"}}
        {"type":"user","message":{"content":"<command-name>/compact</command-name>"}}
        {"type":"user","message":{"content":"请帮我修复这个 bug"}}
        """
        XCTAssert(StatusPoller.parseLastEntry(from: content) == .userMessage)
    }

    func testLastEntryUserMessageWithStringFormat() {
        // user message 的 message 字段是纯字符串而非对象
        let content = #"{"type":"user","message":"plain text prompt"}"#
        XCTAssert(StatusPoller.parseLastEntry(from: content) == .userMessage)
    }

    // MARK: - inferStatus 跳过本地命令后的状态

    func testInferStatusIdleAfterCompact() {
        let content = """
        {"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn"}}
        {"type":"user","message":{"content":"<command-name>/compact</command-name>"}}
        {"type":"user","message":{"content":"<local-command-stdout>Compacted</local-command-stdout>"}}
        """
        XCTAssertEqual(StatusPoller.inferStatus(from: content, timeSinceUpdate: 120), .idle)
    }
}

// MARK: - SessionStore Mock

final class SessionStoreMockTests: XCTestCase {

    func testMockStoreHasFiveSessions() {
        let store = SessionStore.mock()
        XCTAssertEqual(store.sessions.count, 5)
    }

    func testMockStoreHasAllStatuses() {
        let store = SessionStore.mock()
        let statuses = Set(store.sessions.map { $0.status })
        XCTAssertTrue(statuses.contains(.working))
        XCTAssertTrue(statuses.contains(.waitingInput))
        XCTAssertTrue(statuses.contains(.idle))
    }

    func testMockStoreHasMultipleAgentTypes() {
        let store = SessionStore.mock()
        let types = Set(store.sessions.map { $0.agentType })
        XCTAssertTrue(types.contains(.claude))
        XCTAssertTrue(types.contains(.codex))
        XCTAssertTrue(types.contains(.gemini))
    }

    func testMockStoreHasJustCompleted() {
        let store = SessionStore.mock()
        let completed = store.sessions.filter { $0.justCompleted }
        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(completed[0].status, .idle)
    }

    func testMockStoreSessionsHaveTokens() {
        let store = SessionStore.mock()
        let withTokens = store.sessions.filter { $0.totalTokens > 0 }
        XCTAssertGreaterThanOrEqual(withTokens.count, 3)
    }
}

// MARK: - SessionStore justCompleted

final class SessionStoreJustCompletedTests: XCTestCase {

    func testWorkingToIdleSetsJustCompleted() {
        let store = SessionStore()
        store.upsert(Session(id: "1", pid: 1, cwd: "/tmp", startedAt: Date(), agentType: .claude))
        store.updateStatus(sessionId: "1", status: .working)
        store.updateStatus(sessionId: "1", status: .idle)
        XCTAssertTrue(store.sessions[0].justCompleted)
    }

    func testUnknownToIdleDoesNotSetJustCompleted() {
        let store = SessionStore()
        store.upsert(Session(id: "1", pid: 1, cwd: "/tmp", startedAt: Date(), agentType: .claude))
        store.updateStatus(sessionId: "1", status: .idle)
        XCTAssertFalse(store.sessions[0].justCompleted)
    }

    func testClearJustCompleted() {
        let store = SessionStore()
        store.upsert(Session(id: "1", pid: 1, cwd: "/tmp", startedAt: Date(), agentType: .claude))
        store.updateStatus(sessionId: "1", status: .working)
        store.updateStatus(sessionId: "1", status: .idle)
        XCTAssertTrue(store.sessions[0].justCompleted)

        store.clearJustCompleted(sessionId: "1")
        XCTAssertFalse(store.sessions[0].justCompleted)
    }
}
